import SwiftUI
import SwiftData

struct ScheduleBoardView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Employee.name) private var employees: [Employee]
    @Query(sort: [SortDescriptor(\CoverageRequirement.dayOfWeek), SortDescriptor(\CoverageRequirement.startMinutes)])
    private var allCoverageRequirements: [CoverageRequirement]
    @Query private var allAvailabilityWindows: [EmployeeAvailabilityWindow]
    @Query private var allUnavailableDates: [EmployeeUnavailableDate]
    @Query(sort: \PlannedShift.startDate) private var allPlannedShifts: [PlannedShift]

    @StateObject private var viewModel = ScheduleBoardViewModel()

    @State private var showingCoverageEditor = false
    @State private var showingOptionsSheet = false
    @State private var showingPublishConfirmation = false
    @State private var showingPublishError = false
    @State private var publishErrorMessage = ""
    @State private var showingPublishSuccess = false
    @State private var publishSuccessMessage = ""

    private var shopId: String { ShopContext.activeShopID }
    private var timeZone: TimeZone { ShopContext.activeTimeZone }

    private var canManageSchedule: Bool {
        guard let role = coordinator.currentEmployee?.role else { return false }
        return role == .manager || role == .shiftLead
    }

    private var normalizedWeekStart: Date {
        ScheduleCalendarService.normalizedWeekStart(viewModel.weekStartDate, in: timeZone)
    }

    private var scopedCoverageBlocks: [CoverageRequirement] {
        allCoverageRequirements.filter {
            $0.shopId == shopId &&
            ScheduleCalendarService.normalizedWeekStart($0.weekStartDate, in: timeZone) == normalizedWeekStart
        }
    }

    private var scopedAvailabilityWindows: [EmployeeAvailabilityWindow] {
        allAvailabilityWindows.filter { $0.shopId == shopId }
    }

    private var scopedUnavailableDates: [EmployeeUnavailableDate] {
        allUnavailableDates.filter { $0.shopId == shopId }
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

    private var refreshKey: String {
        [
            normalizedWeekStart.description,
            "\(employees.count)",
            "\(scopedCoverageBlocks.count)",
            "\(scopedAvailabilityWindows.count)",
            "\(scopedUnavailableDates.count)",
            "\(scopedPlannedShifts.count)"
        ].joined(separator: "|")
    }

    var body: some View {
        Group {
            if canManageSchedule {
                managerBoard
            } else {
                employeePublishedView
            }
        }
        .liquidBackground()
        .navigationTitle("Schedule")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task(id: refreshKey) {
            refreshBoardData()
        }
        .sheet(isPresented: $showingCoverageEditor) {
            CoverageEditorView(
                shopId: shopId,
                weekStartDate: normalizedWeekStart,
                timeZone: timeZone
            )
            #if os(macOS)
            .frame(minWidth: 780, minHeight: 680)
            #endif
        }
        .sheet(isPresented: $showingOptionsSheet) {
            GenerateOptionsSheet(options: viewModel.options) { option in
                viewModel.applyOption(option)
            }
            #if os(macOS)
            .frame(minWidth: 620, minHeight: 620)
            #endif
        }
        .alert("Publish Schedule?", isPresented: $showingPublishConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Publish") {
                publishSchedule()
            }
        } message: {
            Text("Publish this week schedule for \(ScheduleCalendarService.abbreviatedDateLabel(for: normalizedWeekStart, in: timeZone))?")
        }
        .alert("Publish Failed", isPresented: $showingPublishError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(publishErrorMessage)
        }
        .alert("Published", isPresented: $showingPublishSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(publishSuccessMessage)
        }
    }

    private var managerBoard: some View {
        VStack(spacing: DesignSystem.Spacing.grid_1) {
            topBar

            if scopedCoverageBlocks.isEmpty {
                EmptyStateView(
                    icon: "calendar.badge.plus",
                    title: "No Coverage Requirements",
                    message: "Define coverage first, then drag employees into the board.",
                    actionTitle: "Open Coverage"
                ) {
                    showingCoverageEditor = true
                }
            } else {
                HStack(alignment: .top, spacing: DesignSystem.Spacing.grid_1) {
                    #if os(iOS)
                    if UIDevice.current.userInterfaceIdiom != .phone {
                        EmployeeRosterView(viewModel: viewModel)
                    }
                    #else
                    EmployeeRosterView(viewModel: viewModel)
                    #endif

                    WeekGridCanvasView(viewModel: viewModel, canEdit: true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .glassCard()
                }
            }

            warningFooter
        }
        .padding(DesignSystem.Spacing.grid_1)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var employeePublishedView: some View {
        let viewerShifts = scopedPlannedShifts.filter { $0.status == .published }

        return ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.grid_2) {
                Text("Published Week")
                    .font(DesignSystem.Typography.headline)

                if viewerShifts.isEmpty {
                    EmptyStateView(
                        icon: "calendar.badge.clock",
                        title: "No Published Shifts",
                        message: "There are no published shifts for this week."
                    )
                } else {
                    ForEach(viewerShifts) { shift in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(shift.employee?.name ?? "Unassigned")
                                    .font(DesignSystem.Typography.body)
                                Text("\(shift.startDate.formatted(date: .abbreviated, time: .shortened)) – \(shift.endDate.formatted(date: .omitted, time: .shortened))")
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(shift.durationHours.formatted(.number.precision(.fractionLength(1))))h")
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
            .readableContent(maxWidth: 960)
        }
    }

    private var topBar: some View {
        HStack(spacing: DesignSystem.Spacing.grid_1) {
            Button {
                viewModel.previousWeek()
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.bordered)

            Text(weekRangeLabel)
                .font(DesignSystem.Typography.headline)
                .frame(minWidth: 240, alignment: .leading)

            Button {
                viewModel.nextWeek()
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.bordered)

            Spacer()

            Toggle("Heat Map", isOn: $viewModel.showHeatMap)
                .toggleStyle(.switch)
                .font(DesignSystem.Typography.caption)

            Button {
                showingCoverageEditor = true
            } label: {
                Label("Coverage", systemImage: "square.grid.3x2")
            }
            .buttonStyle(.bordered)

            Button {
                viewModel.generateOptions()
                showingOptionsSheet = true
            } label: {
                Label("Generate Options", systemImage: "sparkles")
            }
            .buttonStyle(.borderedProminent)
            .disabled(scopedCoverageBlocks.isEmpty || employees.filter(\.isActive).isEmpty)

            Button {
                viewModel.restoreSelectedOption()
            } label: {
                Label("Restore Option", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.originalOptionShifts.isEmpty)

            Button {
                showingPublishConfirmation = true
            } label: {
                Label("Publish", systemImage: "paperplane.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.draftShifts.isEmpty || viewModel.hasCriticalWarnings)
        }
        .padding(.horizontal, DesignSystem.Spacing.grid_1)
    }

    @ViewBuilder
    private var warningFooter: some View {
        if viewModel.warnings.isEmpty {
            Text("No warnings. Coverage and assignments look good.")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DesignSystem.Spacing.grid_1)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.warnings.prefix(8)) { warning in
                        Label(warning.message, systemImage: icon(for: warning.kind))
                            .font(DesignSystem.Typography.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(background(for: warning.severity))
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.grid_1)
            }
        }
    }

    private var weekRangeLabel: String {
        let calendar = ScheduleCalendarService.calendar(in: timeZone)
        let end = calendar.date(byAdding: .day, value: 6, to: normalizedWeekStart) ?? normalizedWeekStart
        let startLabel = ScheduleCalendarService.abbreviatedDateLabel(for: normalizedWeekStart, in: timeZone)
        let endLabel = ScheduleCalendarService.abbreviatedDateLabel(for: end, in: timeZone)
        return "\(startLabel) – \(endLabel)"
    }

    private func icon(for kind: ScheduleBoardWarningKind) -> String {
        switch kind {
        case .coverageGap:
            return "exclamationmark.triangle.fill"
        case .conflict:
            return "xmark.octagon.fill"
        case .availability:
            return "calendar.badge.exclamationmark"
        case .overtime:
            return "clock.badge.exclamationmark"
        }
    }

    private func background(for severity: ScheduleBoardWarningSeverity) -> Color {
        switch severity {
        case .critical:
            return DesignSystem.Colors.error.opacity(0.18)
        case .warning:
            return DesignSystem.Colors.warning.opacity(0.18)
        case .info:
            return DesignSystem.Colors.surface.opacity(0.65)
        }
    }

    private func refreshBoardData() {
        let scopedEmployees = employees.filter(\.isActive)
        viewModel.configure(
            employees: scopedEmployees,
            coverageBlocks: scopedCoverageBlocks,
            availabilityWindows: scopedAvailabilityWindows,
            unavailableDates: scopedUnavailableDates,
            shopId: shopId,
            weekStartDate: normalizedWeekStart,
            timeZone: timeZone
        )

        if viewModel.draftShifts.isEmpty {
            let calendar = ScheduleCalendarService.calendar(in: timeZone)
            let draftFromPublished = scopedPlannedShifts
                .filter { $0.status == .planned || $0.status == .published }
                .map { shift in
                    let dayOffset = max(0, min(6, calendar.dateComponents([.day], from: normalizedWeekStart, to: shift.dayDate).day ?? 0))
                    let startMinutes = ScheduleCalendarService.minutesFromMidnight(for: shift.startDate, in: timeZone)
                    let endMinutes = ScheduleCalendarService.minutesFromMidnight(for: shift.endDate, in: timeZone)
                    return ScheduleDraftShift(
                        employeeId: shift.employee?.id,
                        dayOfWeek: dayOffset,
                        startMinutes: startMinutes,
                        endMinutes: max(startMinutes + 15, endMinutes),
                        colorSeed: shift.employee?.id.uuidString ?? shift.id.uuidString,
                        notes: shift.notes
                    )
                }

            viewModel.replaceDraftShifts(draftFromPublished, keepAsOriginal: true)
        }
    }

    private func publishSchedule() {
        do {
            let count = try viewModel.publish(modelContext: modelContext)
            publishSuccessMessage = "Published \(count) shifts."
            showingPublishSuccess = true
        } catch {
            publishErrorMessage = error.localizedDescription
            showingPublishError = true
        }
    }
}

#Preview("Schedule Board") {
    ScheduleBoardPreviewHost()
}

private struct ScheduleBoardPreviewHost: View {
    var body: some View {
        let container = try? ModelContainer(
            for: Schema(versionedSchema: SchemaV3.self),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )

        if let container {
            let coordinator = AppCoordinator()
            let previewManager = Employee(name: "Preview Manager", pin: "0000", role: .manager)
            coordinator.currentEmployee = previewManager
            coordinator.currentViewState = .managerView(previewManager)
            coordinator.isAuthenticated = true

            seedPreviewData(container.mainContext)
            return AnyView(
                NavigationStack {
                    ScheduleBoardView()
                }
                .modelContainer(container)
                .environment(coordinator)
            )
        }

        return AnyView(Text("Preview unavailable"))
    }

    private func seedPreviewData(_ context: ModelContext) {
        let employees = [
            Employee(name: "Avery", pin: "1111", role: .manager),
            Employee(name: "Jordan", pin: "2222", role: .shiftLead),
            Employee(name: "Mia", pin: "3333", role: .employee),
            Employee(name: "Leo", pin: "4444", role: .employee),
            Employee(name: "Noah", pin: "5555", role: .employee),
            Employee(name: "Emma", pin: "6666", role: .employee)
        ]
        employees.forEach(context.insert)

        let weekStart = ScheduleCalendarService.normalizedWeekStart(Date(), in: ShopContext.activeTimeZone)

        for dayIndex in 0...6 {
            let weekday = ScheduleDayMapper.weekday(fromDayIndex: dayIndex)
            context.insert(
                CoverageRequirement(
                    shopId: ShopContext.activeShopID,
                    weekStartDate: weekStart,
                    dayOfWeek: weekday,
                    startMinutes: 7 * 60,
                    endMinutes: 15 * 60,
                    headcount: dayIndex == 5 || dayIndex == 6 ? 1 : 2
                )
            )
        }

        for employee in employees {
            for dayIndex in 0...6 {
                context.insert(
                    EmployeeAvailabilityWindow(
                        shopId: ShopContext.activeShopID,
                        employee: employee,
                        dayOfWeek: ScheduleDayMapper.weekday(fromDayIndex: dayIndex),
                        startMinutes: 6 * 60 + 30,
                        endMinutes: 18 * 60
                    )
                )
            }
        }

        try? context.save()
    }
}
