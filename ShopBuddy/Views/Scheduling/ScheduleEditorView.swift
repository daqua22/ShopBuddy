import SwiftUI
import SwiftData

struct ScheduleEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let shopId: String
    let weekStartDate: Date
    let timeZone: TimeZone
    let employees: [Employee]
    let coverageRequirements: [CoverageRequirement]
    let availabilityContext: EmployeeAvailabilityContext
    let existingPlannedShifts: [PlannedShift]
    let constraints: ScheduleGenerationConstraints
    let selectedOption: ScheduleOption

    @State private var shifts: [DraftShift]
    @State private var originalShifts: [DraftShift]
    @State private var weekGridShifts: [WeekScheduledShift]
    @State private var editableWeekStartDate: Date
    @State private var warnings: [ScheduleWarning] = []
    @State private var showingPublishConfirmation = false
    @State private var showingMonthPublishConfirmation = false
    @State private var publishingError: String?
    @State private var showingPublishingError = false
    @State private var showingSuccess = false
    @State private var successMessage = ""

    init(
        shopId: String,
        weekStartDate: Date,
        timeZone: TimeZone,
        employees: [Employee],
        coverageRequirements: [CoverageRequirement],
        availabilityContext: EmployeeAvailabilityContext,
        existingPlannedShifts: [PlannedShift],
        constraints: ScheduleGenerationConstraints,
        selectedOption: ScheduleOption
    ) {
        self.shopId = shopId
        self.weekStartDate = weekStartDate
        self.timeZone = timeZone
        self.employees = employees
        self.coverageRequirements = coverageRequirements
        self.availabilityContext = availabilityContext
        self.existingPlannedShifts = existingPlannedShifts
        self.constraints = constraints
        self.selectedOption = selectedOption
        _shifts = State(initialValue: selectedOption.shifts)
        _originalShifts = State(initialValue: selectedOption.shifts)
        let employeesByID = Dictionary(uniqueKeysWithValues: employees.map { ($0.id, $0.name) })
        _weekGridShifts = State(
            initialValue: selectedOption.shifts.map { draft in
                WeekScheduledShift(
                    id: draft.id,
                    employeeName: draft.employeeID.flatMap { employeesByID[$0] } ?? "Unassigned",
                    employeeId: draft.employeeID,
                    dayOfWeek: draft.dayOfWeek,
                    startMinutes: draft.startMinutes,
                    endMinutes: draft.endMinutes,
                    color: Self.colorForShift(employeeID: draft.employeeID, fallbackID: draft.id)
                )
            }
        )
        _editableWeekStartDate = State(initialValue: weekStartDate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.grid_2) {
            editorHeader
            warningsSection
            WeekScheduleView(
                weekStartDate: $editableWeekStartDate,
                shifts: $weekGridShifts,
                employees: employees,
                onGenerateOptions: {},
                onPublish: {
                    showingPublishConfirmation = true
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(DesignSystem.Spacing.grid_2)
        .liquidBackground()
        .navigationTitle("Edit \(selectedOption.name)")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Restore Option") {
                    restoreOption()
                }
                .disabled(shifts == originalShifts)
            }
            ToolbarItem(placement: .automatic) {
                Button("Publish Month") {
                    showingMonthPublishConfirmation = true
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Publish") {
                    showingPublishConfirmation = true
                }
            }
        }
        .onAppear {
            shifts = mergeDrafts(from: weekGridShifts, into: shifts)
            recomputeWarnings()
        }
        .onChange(of: weekGridShifts) { _, newValue in
            shifts = mergeDrafts(from: newValue, into: shifts)
        }
        .onChange(of: shifts) { _, _ in
            recomputeWarnings()
        }
        .alert("Publish Schedule?", isPresented: $showingPublishConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Publish", role: .none) {
                publish()
            }
        } message: {
            Text("Publish schedule for week of \(editableWeekStartDate.formatted(date: .abbreviated, time: .omitted))?")
        }
        .alert("Publish Whole Month?", isPresented: $showingMonthPublishConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Publish Month") {
                publishMonth()
            }
        } message: {
            Text("This will apply this week pattern to every matching weekday in \(editableWeekStartDate.formatted(.dateTime.month(.wide).year())).")
        }
        .alert("Publish Failed", isPresented: $showingPublishingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(publishingError ?? "Unknown error")
        }
        .alert("Schedule Published", isPresented: $showingSuccess) {
            Button("Done") {
                dismiss()
            }
        } message: {
            Text(successMessage)
        }
    }

    private var editorHeader: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.grid_2) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Week of \(editableWeekStartDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(DesignSystem.Typography.headline)
                Text("\(shifts.count) shifts • \(String(format: "%.1f", shifts.reduce(0) { $0 + Double($1.durationMinutes) / 60.0 })) hours")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(DesignSystem.Spacing.grid_2)
        .glassCard()
    }

    @ViewBuilder
    private var warningsSection: some View {
        if warnings.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Live Warnings")
                    .font(DesignSystem.Typography.headline)

                ForEach(warnings.prefix(8)) { warning in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: icon(for: warning.kind))
                            .foregroundStyle(color(for: warning.kind))
                        Text(warning.message)
                            .font(DesignSystem.Typography.caption)
                    }
                }

                if warnings.count > 8 {
                    Text("+\(warnings.count - 8) more warnings")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(DesignSystem.Spacing.grid_2)
            .glassCard()
        }
    }

    private func restoreOption() {
        withAnimation(.easeInOut(duration: 0.2)) {
            shifts = originalShifts
            weekGridShifts = originalShifts.map { draft in
                WeekScheduledShift(
                    id: draft.id,
                    employeeName: employeeName(for: draft.employeeID),
                    employeeId: draft.employeeID,
                    dayOfWeek: draft.dayOfWeek,
                    startMinutes: draft.startMinutes,
                    endMinutes: draft.endMinutes,
                    color: Self.colorForShift(employeeID: draft.employeeID, fallbackID: draft.id)
                )
            }
            editableWeekStartDate = weekStartDate
        }
    }

    private func recomputeWarnings() {
        let employeesByID = Dictionary(uniqueKeysWithValues: employees.map { ($0.id, $0) })
        let validationInput = ScheduleValidationInput(
            shopId: shopId,
            weekStartDate: editableWeekStartDate,
            shifts: shifts,
            coverageRequirements: coverageRequirements,
            employeesByID: employeesByID,
            availabilityContext: availabilityContext,
            existingPlannedShifts: existingPlannedShifts,
            constraints: constraints,
            timeZone: timeZone
        )
        warnings = ScheduleValidationService.validate(validationInput)
    }

    private func publish() {
        do {
            let employeesByID = Dictionary(uniqueKeysWithValues: employees.map { ($0.id, $0) })
            let count = try SchedulePublishingService.publish(
                shifts: shifts,
                shopId: shopId,
                weekStartDate: editableWeekStartDate,
                employeesByID: employeesByID,
                modelContext: modelContext,
                timeZone: timeZone
            )
            successMessage = "Published \(count) shifts."
            showingSuccess = true
        } catch {
            publishingError = error.localizedDescription
            showingPublishingError = true
        }
    }

    private func publishMonth() {
        do {
            let employeesByID = Dictionary(uniqueKeysWithValues: employees.map { ($0.id, $0) })
            let count = try SchedulePublishingService.publishMonthFromWeekTemplate(
                shifts: shifts,
                shopId: shopId,
                anchorWeekStartDate: editableWeekStartDate,
                employeesByID: employeesByID,
                modelContext: modelContext,
                timeZone: timeZone
            )
            successMessage = "Published \(count) shifts for \(editableWeekStartDate.formatted(.dateTime.month(.wide).year()))."
            showingSuccess = true
        } catch {
            publishingError = error.localizedDescription
            showingPublishingError = true
        }
    }

    private func color(for kind: ScheduleWarningKind) -> Color {
        switch kind {
        case .conflict, .uncovered:
            return DesignSystem.Colors.error
        case .overtime, .restViolation, .availability:
            return DesignSystem.Colors.warning
        case .invalidShift, .unassigned:
            return DesignSystem.Colors.secondary
        }
    }

    private func icon(for kind: ScheduleWarningKind) -> String {
        switch kind {
        case .conflict:
            return "xmark.octagon.fill"
        case .uncovered:
            return "person.crop.circle.badge.exclamationmark"
        case .overtime:
            return "clock.badge.exclamationmark"
        case .restViolation:
            return "moon.zzz.fill"
        case .availability:
            return "calendar.badge.exclamationmark"
        case .invalidShift:
            return "exclamationmark.triangle.fill"
        case .unassigned:
            return "person.crop.circle.badge.questionmark"
        }
    }

    private func employeeName(for employeeID: UUID?) -> String {
        guard let employeeID else { return "Unassigned" }
        return employees.first(where: { $0.id == employeeID })?.name ?? "Unknown Employee"
    }

    private func mergeDrafts(from weekShifts: [WeekScheduledShift], into existingDrafts: [DraftShift]) -> [DraftShift] {
        let existingByID = Dictionary(uniqueKeysWithValues: existingDrafts.map { ($0.id, $0) })
        return weekShifts.map { weekShift in
            if var existing = existingByID[weekShift.id] {
                existing.employeeID = weekShift.employeeId
                existing.dayOfWeek = weekShift.dayOfWeek
                existing.startMinutes = weekShift.startMinutes
                existing.endMinutes = weekShift.endMinutes
                return existing
            } else {
                return DraftShift(
                    id: weekShift.id,
                    employeeID: weekShift.employeeId,
                    dayOfWeek: weekShift.dayOfWeek,
                    startMinutes: weekShift.startMinutes,
                    endMinutes: weekShift.endMinutes
                )
            }
        }
    }

    private static func colorForShift(employeeID: UUID?, fallbackID: UUID) -> Color {
        let palette: [Color] = [.blue, .teal, .green, .orange, .pink, .purple, .indigo]
        let seed = employeeID?.uuidString ?? fallbackID.uuidString
        let hash = UInt(bitPattern: seed.hashValue)
        return palette[Int(hash % UInt(palette.count))]
    }
}
