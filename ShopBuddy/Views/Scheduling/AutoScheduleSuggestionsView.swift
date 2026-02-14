import SwiftUI
import SwiftData

struct AutoScheduleSuggestionsView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Employee.name) private var employees: [Employee]
    @Query(sort: [SortDescriptor(\CoverageRequirement.dayOfWeek), SortDescriptor(\CoverageRequirement.startMinutes)])
    private var allCoverageRequirements: [CoverageRequirement]
    @Query private var allAvailabilityWindows: [EmployeeAvailabilityWindow]
    @Query private var allAvailabilityOverrides: [EmployeeAvailabilityOverride]
    @Query private var allUnavailableDates: [EmployeeUnavailableDate]
    @Query(sort: \PlannedShift.startDate) private var allPlannedShifts: [PlannedShift]
    @Query private var appSettings: [AppSettings]

    @State private var weekAnchorDate: Date = ScheduleCalendarService.normalizedWeekStart(Date(), in: ShopContext.activeTimeZone)
    @State private var showingCoverageSheet = false
    @State private var coverageToEdit: CoverageRequirement?

    @State private var options: [ScheduleOption] = []
    @State private var selectedOption: ScheduleOption?
    @State private var generationConstraints = ScheduleGenerationConstraints()

    @State private var showingGenerationError = false
    @State private var generationError = ""

    private var shopId: String { ShopContext.activeShopID }
    private var timeZone: TimeZone { ShopContext.activeTimeZone }

    private var normalizedWeekStart: Date {
        ScheduleCalendarService.normalizedWeekStart(weekAnchorDate, in: timeZone)
    }

    private var canManageSchedule: Bool {
        guard let role = coordinator.currentEmployee?.role else { return false }
        return role == .manager || role == .shiftLead
    }

    private var availabilityContext: EmployeeAvailabilityContext {
        EmployeeAvailabilityContext(
            weeklyWindows: allAvailabilityWindows.filter { $0.shopId == shopId },
            overrides: allAvailabilityOverrides.filter { $0.shopId == shopId },
            unavailableDates: allUnavailableDates.filter { $0.shopId == shopId }
        )
    }

    private var scopedCoverageRequirements: [CoverageRequirement] {
        allCoverageRequirements.filter {
            $0.shopId == shopId &&
            ScheduleCalendarService.normalizedWeekStart($0.weekStartDate, in: timeZone) == normalizedWeekStart
        }
    }

    private var coverageRequirementsByDay: [Int: [CoverageRequirement]] {
        Dictionary(grouping: scopedCoverageRequirements, by: \.dayOfWeek).mapValues { items in
            items.sorted {
                if $0.startMinutes != $1.startMinutes { return $0.startMinutes < $1.startMinutes }
                return $0.endMinutes < $1.endMinutes
            }
        }
    }

    private var scopedPlannedShifts: [PlannedShift] {
        let calendar = ScheduleCalendarService.calendar(in: timeZone)
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: normalizedWeekStart) ?? normalizedWeekStart
        return allPlannedShifts.filter {
            $0.shopId == shopId &&
            $0.startDate >= normalizedWeekStart &&
            $0.startDate < weekEnd
        }
    }

    private var publishedShiftsForViewer: [PlannedShift] {
        let base = scopedPlannedShifts.filter { $0.status == .published }
        guard !canManageSchedule, let currentEmployeeID = coordinator.currentEmployee?.id else {
            return base
        }
        return base.filter { $0.employee?.id == currentEmployeeID }
    }

    var body: some View {
        #if os(macOS)
        NavigationStack {
            content
        }
        #else
        content
        #endif
    }

    private var content: some View {
        Group {
            if canManageSchedule {
                managerContent
            } else {
                publishedScheduleViewer
            }
        }
        .liquidBackground()
        .navigationTitle("Auto-Schedule")
        .sheet(isPresented: $showingCoverageSheet) {
            CoverageRequirementEditorSheet(
                title: coverageToEdit == nil ? "New Coverage Block" : "Edit Coverage Block",
                initialRequirement: coverageToEdit
            ) { dayOfWeek, startMinutes, endMinutes, headcount, role, notes in
                saveCoverage(
                    dayOfWeek: dayOfWeek,
                    startMinutes: startMinutes,
                    endMinutes: endMinutes,
                    headcount: headcount,
                    role: role,
                    notes: notes
                )
            }
            #if os(macOS)
            .frame(minWidth: 560, minHeight: 560)
            #endif
        }
        .navigationDestination(item: $selectedOption) { option in
            ScheduleEditorView(
                shopId: shopId,
                weekStartDate: normalizedWeekStart,
                timeZone: timeZone,
                employees: employees.filter(\.isActive),
                coverageRequirements: scopedCoverageRequirements,
                availabilityContext: availabilityContext,
                existingPlannedShifts: scopedPlannedShifts,
                constraints: generationConstraints,
                selectedOption: option
            )
        }
        .alert("Unable to Generate", isPresented: $showingGenerationError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(generationError)
        }
    }

    private var managerContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.grid_2) {
                weekSelectorCard
                coverageSetupCard
                optionsCard
            }
            .padding(DesignSystem.Spacing.grid_2)
            .readableContent(maxWidth: 1200)
        }
    }

    private var weekSelectorCard: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.grid_1) {
            Text("Schedule Week")
                .font(DesignSystem.Typography.headline)

            DatePicker(
                "Week of",
                selection: Binding(
                    get: { normalizedWeekStart },
                    set: { newValue in
                        weekAnchorDate = ScheduleCalendarService.normalizedWeekStart(newValue, in: timeZone)
                        options.removeAll()
                    }
                ),
                displayedComponents: .date
            )
            .labelsHidden()
        }
        .padding(DesignSystem.Spacing.grid_2)
        .glassCard()
    }

    private var coverageSetupCard: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.grid_2) {
            HStack {
                Text("Coverage Requirements")
                    .font(DesignSystem.Typography.headline)
                Spacer()
                Button {
                    coverageToEdit = nil
                    showingCoverageSheet = true
                } label: {
                    Label("Add Block", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }

            quickPresetRow
            coverageVisualMap

            if scopedCoverageRequirements.isEmpty {
                EmptyStateView(
                    icon: "calendar.badge.plus",
                    title: "No Coverage Blocks",
                    message: "Add required coverage windows for this week.",
                    actionTitle: "Add Coverage Block"
                ) {
                    coverageToEdit = nil
                    showingCoverageSheet = true
                }
                .frame(maxHeight: 260)
            } else {
                ForEach(scopedCoverageRequirements) { requirement in
                    coverageRow(requirement)
                }
            }
        }
        .padding(DesignSystem.Spacing.grid_2)
        .glassCard()
    }

    private var coverageVisualMap: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.grid_1) {
            Text("Visual Coverage")
                .font(DesignSystem.Typography.body)

            ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { day in
                CoverageRequirementDayTimelineView(
                    dayOfWeek: day,
                    requirements: coverageRequirementsByDay[day] ?? []
                )
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DesignSystem.Colors.surface.opacity(0.45))
        )
    }

    private var quickPresetRow: some View {
        HStack(spacing: DesignSystem.Spacing.grid_1) {
            Button("Preset: Open–Close") {
                applyOpenClosePreset()
            }
            .buttonStyle(.bordered)

            Button("Preset: Morning/Evening") {
                applyMorningEveningPreset()
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private func coverageRow(_ requirement: CoverageRequirement) -> some View {
        HStack(spacing: DesignSystem.Spacing.grid_1) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ScheduleCalendarService.dayName(for: requirement.dayOfWeek))
                    .font(DesignSystem.Typography.body)
                Text("\(ScheduleCalendarService.timeLabel(for: requirement.startMinutes)) - \(ScheduleCalendarService.timeLabel(for: requirement.endMinutes))")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("x\(requirement.headcount)")
                .font(DesignSystem.Typography.headline)
                .monospacedDigit()

            if let role = requirement.roleRequirement {
                Text(role.rawValue)
                    .font(DesignSystem.Typography.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(DesignSystem.Colors.surface.opacity(0.6))
                    .clipShape(Capsule())
            }

            Button {
                coverageToEdit = requirement
                showingCoverageSheet = true
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain)

            Button(role: .destructive) {
                deleteCoverage(requirement)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DesignSystem.Colors.surface.opacity(0.5))
        )
    }

    private var optionsCard: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.grid_2) {
            HStack {
                Text("Generated Options")
                    .font(DesignSystem.Typography.headline)
                Spacer()
                Button {
                    generateOptions()
                } label: {
                    Label("Generate Options", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .disabled(scopedCoverageRequirements.isEmpty || employees.filter(\.isActive).isEmpty)
            }

            if options.isEmpty {
                Text("Generate 3–5 schedule options based on availability and constraints.")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(options) { option in
                    optionCard(option)
                }
            }
        }
        .padding(DesignSystem.Spacing.grid_2)
        .glassCard()
    }

    private func optionCard(_ option: ScheduleOption) -> some View {
        let conflictCount = option.warnings.filter { $0.kind == .conflict }.count
        let uncoveredCount = option.warnings.filter { $0.kind == .uncovered }.count

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(option.name)
                    .font(DesignSystem.Typography.headline)
                Spacer()
                Text("Score \(option.score)")
                    .font(DesignSystem.Typography.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(DesignSystem.Colors.surface.opacity(0.7))
                    .clipShape(Capsule())
            }

            HStack(spacing: 12) {
                Label("\(option.totalShiftCount) shifts", systemImage: "calendar")
                Label("\(String(format: "%.1f", option.totalHours)) hrs", systemImage: "clock")
                Label("\(option.warningsCount) warnings", systemImage: "exclamationmark.triangle")
            }
            .font(DesignSystem.Typography.caption)
            .foregroundStyle(.secondary)

            if option.warningsCount > 0 {
                HStack(spacing: 12) {
                    Text("Conflicts: \(conflictCount)")
                    Text("Uncovered: \(uncoveredCount)")
                }
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button("Preview") {
                    selectedOption = option
                }
                .buttonStyle(.bordered)

                Button("Use This Option") {
                    selectedOption = option
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DesignSystem.Colors.surface.opacity(0.55))
        )
    }

    private var publishedScheduleViewer: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.grid_2) {
                weekSelectorCard

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.grid_1) {
                    Text("Published Schedule")
                        .font(DesignSystem.Typography.headline)

                    if publishedShiftsForViewer.isEmpty {
                        EmptyStateView(
                            icon: "calendar.badge.clock",
                            title: "No Published Shifts",
                            message: "There are no published shifts for this week."
                        )
                        .frame(maxHeight: 260)
                    } else {
                        ForEach(publishedShiftsForViewer) { shift in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(shift.employee?.name ?? "Unassigned")
                                        .font(DesignSystem.Typography.body)
                                    Text(shift.startDate.formatted(date: .abbreviated, time: .shortened))
                                        .font(DesignSystem.Typography.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(String(format: "%.1f", shift.durationHours))h")
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(DesignSystem.Colors.surface.opacity(0.55))
                            )
                        }
                    }
                }
                .padding(DesignSystem.Spacing.grid_2)
                .glassCard()
            }
            .padding(DesignSystem.Spacing.grid_2)
            .readableContent(maxWidth: 1100)
        }
    }

    private func saveCoverage(
        dayOfWeek: Int,
        startMinutes: Int,
        endMinutes: Int,
        headcount: Int,
        role: EmployeeRole?,
        notes: String
    ) {
        if let existing = coverageToEdit {
            existing.dayOfWeek = dayOfWeek
            existing.startMinutes = startMinutes
            existing.endMinutes = endMinutes
            existing.headcount = max(1, headcount)
            existing.roleRequirement = role
            existing.notes = notes.isEmpty ? nil : notes
        } else {
            let requirement = CoverageRequirement(
                shopId: shopId,
                weekStartDate: normalizedWeekStart,
                dayOfWeek: dayOfWeek,
                startMinutes: startMinutes,
                endMinutes: endMinutes,
                headcount: headcount,
                roleRequirement: role,
                notes: notes.isEmpty ? nil : notes
            )
            modelContext.insert(requirement)
        }

        do {
            try modelContext.save()
            coverageToEdit = nil
        } catch {
            generationError = error.localizedDescription
            showingGenerationError = true
        }
    }

    private func deleteCoverage(_ requirement: CoverageRequirement) {
        modelContext.delete(requirement)
        do {
            try modelContext.save()
        } catch {
            generationError = error.localizedDescription
            showingGenerationError = true
        }
    }

    private func applyOpenClosePreset() {
        let settings = appSettings.first
        let operatingDays = settings?.operatingDays ?? Set([2, 3, 4, 5, 6])
        let openMinutes = settings.map { ScheduleCalendarService.minutesFromMidnight(for: $0.openTime, in: timeZone) } ?? (7 * 60)
        let closeMinutes = settings.map { ScheduleCalendarService.minutesFromMidnight(for: $0.closeTime, in: timeZone) } ?? (15 * 60)

        for day in operatingDays.sorted() {
            let requirement = CoverageRequirement(
                shopId: shopId,
                weekStartDate: normalizedWeekStart,
                dayOfWeek: day,
                startMinutes: openMinutes,
                endMinutes: max(openMinutes + 60, closeMinutes),
                headcount: 2
            )
            modelContext.insert(requirement)
        }

        saveContextSilently()
    }

    private func applyMorningEveningPreset() {
        let settings = appSettings.first
        let operatingDays = settings?.operatingDays ?? Set([2, 3, 4, 5, 6])

        for day in operatingDays.sorted() {
            modelContext.insert(
                CoverageRequirement(
                    shopId: shopId,
                    weekStartDate: normalizedWeekStart,
                    dayOfWeek: day,
                    startMinutes: 7 * 60,
                    endMinutes: 13 * 60,
                    headcount: 1
                )
            )
            modelContext.insert(
                CoverageRequirement(
                    shopId: shopId,
                    weekStartDate: normalizedWeekStart,
                    dayOfWeek: day,
                    startMinutes: 13 * 60,
                    endMinutes: 19 * 60,
                    headcount: 1
                )
            )
        }

        saveContextSilently()
    }

    private func generateOptions() {
        let activeEmployees = employees.filter(\.isActive)
        guard !activeEmployees.isEmpty else {
            generationError = "No active employees found."
            showingGenerationError = true
            return
        }
        guard !scopedCoverageRequirements.isEmpty else {
            generationError = "Add at least one coverage requirement first."
            showingGenerationError = true
            return
        }

        let input = SchedulingGeneratorInput(
            shopId: shopId,
            weekStartDate: normalizedWeekStart,
            coverageRequirements: scopedCoverageRequirements,
            employees: activeEmployees,
            availabilityContext: availabilityContext,
            existingPlannedShifts: scopedPlannedShifts,
            constraints: generationConstraints,
            timeZone: timeZone
        )
        options = SchedulingGeneratorService.generateOptions(input: input)

        if options.isEmpty {
            generationError = "No valid options were generated. Check availability or coverage constraints."
            showingGenerationError = true
        }
    }

    private func saveContextSilently() {
        do {
            try modelContext.save()
        } catch {
            generationError = error.localizedDescription
            showingGenerationError = true
        }
    }
}

private struct CoverageRequirementDayTimelineView: View {
    let dayOfWeek: Int
    let requirements: [CoverageRequirement]

    private let timelineStart = 5 * 60
    private let timelineEnd = 23 * 60

    private var totalMinutes: Int {
        max(1, timelineEnd - timelineStart)
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(shortDay(dayOfWeek))
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                        .frame(height: 24)

                    ForEach(requirements) { requirement in
                        let clampedStart = max(timelineStart, requirement.startMinutes)
                        let clampedEnd = min(timelineEnd, requirement.endMinutes)
                        if clampedEnd > clampedStart {
                            let x = proxy.size.width * CGFloat(clampedStart - timelineStart) / CGFloat(totalMinutes)
                            let width = max(
                                18,
                                proxy.size.width * CGFloat(clampedEnd - clampedStart) / CGFloat(totalMinutes)
                            )
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(blockColor(for: requirement.headcount))
                                .frame(width: width, height: 20)
                                .offset(x: x, y: 2)
                                .overlay(alignment: .center) {
                                    Text("x\(requirement.headcount)")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.95))
                                }
                        }
                    }

                    if requirements.isEmpty {
                        Text("No coverage")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 8)
                    }
                }
            }
            .frame(height: 24)
        }
    }

    private func shortDay(_ value: Int) -> String {
        switch value {
        case 1: return "Sun"
        case 2: return "Mon"
        case 3: return "Tue"
        case 4: return "Wed"
        case 5: return "Thu"
        case 6: return "Fri"
        case 7: return "Sat"
        default: return "-"
        }
    }

    private func blockColor(for headcount: Int) -> Color {
        if headcount >= 3 { return .orange }
        if headcount == 2 { return .blue }
        return .teal
    }
}
