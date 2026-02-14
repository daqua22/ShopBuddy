import Foundation
import SwiftUI
import SwiftData
import Combine

@MainActor
final class ScheduleBoardViewModel: ObservableObject {
    private enum ShiftInteractionMode {
        case move
        case resizeTop
        case resizeBottom
    }

    private struct ShiftInteraction {
        let mode: ShiftInteractionMode
        let baseline: ScheduleDraftShift
    }

    @Published var weekStartDate: Date
    @Published var draftShifts: [ScheduleDraftShift] = []
    @Published var originalOptionShifts: [ScheduleDraftShift] = []
    @Published var options: [ScheduleDraftOption] = []
    @Published var selectedOption: ScheduleDraftOption?
    @Published var selectedShiftID: UUID?
    @Published private(set) var previewShifts: [UUID: ScheduleDraftShift] = [:]

    @Published var coverageEvaluation: CoverageEvaluationResult = .empty
    @Published var warnings: [ScheduleDraftWarning] = []

    @Published var visibleStartMinutes: Int
    @Published var visibleEndMinutes: Int
    @Published var pixelsPerMinute: CGFloat
    @Published var dayColumnWidth: CGFloat
    @Published var showHeatMap: Bool = true

    @Published var rosterSearch: String = ""
    @Published var onlyAvailableNow: Bool = false
    @Published var roleFilter: EmployeeRole?

    private var employees: [Employee] = []
    private var coverageBlocks: [CoverageRequirement] = []
    private var availabilityWindows: [EmployeeAvailabilityWindow] = []
    private var unavailableDates: [EmployeeUnavailableDate] = []
    private var shopId: String = ShopContext.activeShopID
    private var timeZone: TimeZone = ShopContext.activeTimeZone

    private var interactions: [UUID: ShiftInteraction] = [:]
    private let minimumShiftDurationMinutes = 30
    private let maxUndoDepth = 80
    private var copiedShiftTemplate: ScheduleDraftShift?
    private var undoStack: [[ScheduleDraftShift]] = []

    init(
        weekStartDate: Date = Date(),
        visibleStartMinutes: Int = 6 * 60 + 30,
        visibleEndMinutes: Int = 18 * 60 + 30,
        pixelsPerMinute: CGFloat = 1.4,
        dayColumnWidth: CGFloat = 180
    ) {
        self.weekStartDate = ScheduleCalendarService.normalizedWeekStart(weekStartDate, in: ShopContext.activeTimeZone)
        self.visibleStartMinutes = visibleStartMinutes
        self.visibleEndMinutes = visibleEndMinutes
        self.pixelsPerMinute = pixelsPerMinute
        self.dayColumnWidth = dayColumnWidth
    }

    var displayTimeZone: TimeZone {
        timeZone
    }

    var filteredEmployees: [Employee] {
        allEmployees
            .filter(\.isActive)
            .filter { employee in
                roleFilter == nil || employee.role == roleFilter
            }
            .filter { employee in
                rosterSearch.isEmpty || employee.name.localizedCaseInsensitiveContains(rosterSearch)
            }
            .filter { employee in
                if !onlyAvailableNow { return true }
                return availabilityStatus(for: employee.id) == .available
            }
            .sorted { lhs, rhs in
                if lhs.role.sortOrder != rhs.role.sortOrder {
                    return lhs.role.sortOrder < rhs.role.sortOrder
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    var allEmployees: [Employee] {
        employees.sorted { lhs, rhs in
            if lhs.role.sortOrder != rhs.role.sortOrder {
                return lhs.role.sortOrder < rhs.role.sortOrder
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    var employeesById: [UUID: Employee] {
        Dictionary(uniqueKeysWithValues: employees.map { ($0.id, $0) })
    }

    var warningsByShiftId: [UUID: [ScheduleDraftWarning]] {
        Dictionary(grouping: warnings.compactMap { warning -> (UUID, ScheduleDraftWarning)? in
            guard let shiftId = warning.shiftId else { return nil }
            return (shiftId, warning)
        }, by: { $0.0 })
        .mapValues { $0.map(\.1) }
    }

    var scheduledMinutesByEmployee: [UUID: Int] {
        draftShifts.reduce(into: [:]) { partial, shift in
            guard let employeeId = shift.employeeId else { return }
            partial[employeeId, default: 0] += shift.durationMinutes
        }
    }

    var hasCriticalWarnings: Bool {
        warnings.contains { $0.severity == .critical }
    }

    var visibleTotalMinutes: Int {
        max(60, visibleEndMinutes - visibleStartMinutes)
    }

    var isInteractingWithShift: Bool {
        !interactions.isEmpty
    }

    var displayedShifts: [ScheduleDraftShift] {
        draftShifts.map { previewShifts[$0.id] ?? $0 }
    }

    var canCopyOrCutSelection: Bool {
        selectedShift != nil
    }

    var canPaste: Bool {
        copiedShiftTemplate != nil
    }

    var canUndo: Bool {
        !undoStack.isEmpty
    }

    private var selectedShift: ScheduleDraftShift? {
        guard let selectedShiftID else { return nil }
        return draftShifts.first(where: { $0.id == selectedShiftID })
    }

    func configure(
        employees: [Employee],
        coverageBlocks: [CoverageRequirement],
        availabilityWindows: [EmployeeAvailabilityWindow],
        unavailableDates: [EmployeeUnavailableDate],
        shopId: String,
        weekStartDate: Date,
        timeZone: TimeZone
    ) {
        self.employees = employees
        self.coverageBlocks = coverageBlocks
        self.availabilityWindows = availabilityWindows
        self.unavailableDates = unavailableDates
        self.shopId = shopId
        self.weekStartDate = ScheduleCalendarService.normalizedWeekStart(weekStartDate, in: timeZone)
        self.timeZone = timeZone

        recalculateWarningsAndCoverage()
    }

    func previousWeek() {
        let calendar = ScheduleCalendarService.calendar(in: timeZone)
        let next = calendar.date(byAdding: .day, value: -7, to: weekStartDate) ?? weekStartDate
        weekStartDate = ScheduleCalendarService.normalizedWeekStart(next, in: timeZone)
    }

    func nextWeek() {
        let calendar = ScheduleCalendarService.calendar(in: timeZone)
        let next = calendar.date(byAdding: .day, value: 7, to: weekStartDate) ?? weekStartDate
        weekStartDate = ScheduleCalendarService.normalizedWeekStart(next, in: timeZone)
    }

    func dateForDayIndex(_ dayIndex: Int) -> Date {
        let calendar = ScheduleCalendarService.calendar(in: timeZone)
        let normalized = ScheduleCalendarService.normalizedWeekStart(weekStartDate, in: timeZone)
        return calendar.date(byAdding: .day, value: dayIndex, to: normalized) ?? normalized
    }

    func applyOption(_ option: ScheduleDraftOption) {
        previewShifts.removeAll()
        interactions.removeAll()
        undoStack.removeAll()
        selectedShiftID = nil
        selectedOption = option
        options = options
        originalOptionShifts = option.shifts
        draftShifts = option.shifts
        recalculateWarningsAndCoverage()
    }

    func replaceDraftShifts(_ shifts: [ScheduleDraftShift], keepAsOriginal: Bool = false) {
        previewShifts.removeAll()
        interactions.removeAll()
        undoStack.removeAll()
        selectedShiftID = nil
        draftShifts = shifts.map(sanitizeShift)
        if keepAsOriginal {
            originalOptionShifts = draftShifts
            selectedOption = nil
        }
        recalculateWarningsAndCoverage()
    }

    func restoreSelectedOption() {
        guard !originalOptionShifts.isEmpty else { return }
        previewShifts.removeAll()
        interactions.removeAll()
        undoStack.removeAll()
        selectedShiftID = nil
        draftShifts = originalOptionShifts
        recalculateWarningsAndCoverage()
    }

    func generateOptions() {
        let input = AutoSchedulerInput(
            shopId: shopId,
            weekStartDate: weekStartDate,
            employees: employees.filter(\.isActive),
            coverageBlocks: coverageBlocks,
            availabilityWindows: availabilityWindows,
            unavailableDates: unavailableDates,
            visibleStartMinutes: visibleStartMinutes,
            visibleEndMinutes: visibleEndMinutes,
            timeZone: timeZone
        )
        options = AutoSchedulerService.generateOptions(input: input)
    }

    func addShift(
        employeeId: UUID?,
        dayOfWeek: Int,
        startMinutes: Int,
        durationMinutes: Int = 4 * 60
    ) {
        let clampedStart = TimeSnapper.snapAndClamp(
            startMinutes,
            step: 15,
            min: visibleStartMinutes,
            max: max(visibleStartMinutes + minimumShiftDurationMinutes, visibleEndMinutes - minimumShiftDurationMinutes)
        )
        let clampedEnd = TimeSnapper.snapAndClamp(
            clampedStart + durationMinutes,
            step: 15,
            min: clampedStart + minimumShiftDurationMinutes,
            max: visibleEndMinutes
        )

        recordUndoSnapshotIfNeeded()
        let shift = ScheduleDraftShift(
            employeeId: employeeId,
            dayOfWeek: max(0, min(6, dayOfWeek)),
            startMinutes: clampedStart,
            endMinutes: max(clampedStart + minimumShiftDurationMinutes, clampedEnd),
            colorSeed: employeeId?.uuidString ?? UUID().uuidString
        )
        draftShifts.append(shift)
        selectedShiftID = shift.id
        recalculateWarningsAndCoverage()
    }

    func selectShift(_ shiftID: UUID?) {
        selectedShiftID = shiftID
    }

    func copySelection() {
        guard let selectedShift else { return }
        copiedShiftTemplate = selectedShift
    }

    func cutSelection() {
        guard let selectedShift else { return }
        copiedShiftTemplate = selectedShift
        deleteShift(selectedShift.id)
    }

    func pasteCopiedShift() {
        guard let copiedShiftTemplate else { return }

        let anchorShift = selectedShift ?? copiedShiftTemplate
        let duration = max(minimumShiftDurationMinutes, copiedShiftTemplate.durationMinutes)
        let startMinutes = TimeSnapper.snapAndClamp(
            anchorShift.startMinutes + 15,
            step: 15,
            min: visibleStartMinutes,
            max: max(visibleStartMinutes, visibleEndMinutes - duration)
        )
        let pastedShift = ScheduleDraftShift(
            employeeId: copiedShiftTemplate.employeeId,
            dayOfWeek: anchorShift.dayOfWeek,
            startMinutes: startMinutes,
            endMinutes: min(visibleEndMinutes, startMinutes + duration),
            colorSeed: copiedShiftTemplate.employeeId?.uuidString ?? copiedShiftTemplate.colorSeed,
            notes: copiedShiftTemplate.notes
        )

        recordUndoSnapshotIfNeeded()
        draftShifts.append(pastedShift)
        selectedShiftID = pastedShift.id
        recalculateWarningsAndCoverage()
    }

    func undoLastChange() {
        guard let previous = undoStack.popLast() else { return }
        previewShifts.removeAll()
        interactions.removeAll()
        draftShifts = previous
        if let selectedShiftID, !draftShifts.contains(where: { $0.id == selectedShiftID }) {
            self.selectedShiftID = nil
        }
        recalculateWarningsAndCoverage()
    }

    func updateShift(_ updated: ScheduleDraftShift) {
        guard let index = draftShifts.firstIndex(where: { $0.id == updated.id }) else { return }
        let sanitized = sanitizeShift(updated)
        guard draftShifts[index] != sanitized else { return }
        recordUndoSnapshotIfNeeded()
        draftShifts[index] = sanitized
        selectedShiftID = updated.id
        recalculateWarningsAndCoverage()
    }

    func deleteShift(_ shiftId: UUID) {
        previewShifts.removeValue(forKey: shiftId)
        interactions.removeValue(forKey: shiftId)
        guard let index = draftShifts.firstIndex(where: { $0.id == shiftId }) else { return }
        recordUndoSnapshotIfNeeded()
        draftShifts.remove(at: index)
        if selectedShiftID == shiftId {
            selectedShiftID = nil
        }
        recalculateWarningsAndCoverage()
    }

    func reassignShift(_ shiftId: UUID, employeeId: UUID) {
        guard let index = draftShifts.firstIndex(where: { $0.id == shiftId }) else { return }
        guard draftShifts[index].employeeId != employeeId else { return }
        recordUndoSnapshotIfNeeded()
        draftShifts[index].employeeId = employeeId
        draftShifts[index].colorSeed = employeeId.uuidString
        selectedShiftID = shiftId
        recalculateWarningsAndCoverage()
    }

    func beginDrag(for shiftId: UUID) {
        selectedShiftID = shiftId
        beginInteraction(for: shiftId, mode: .move)
    }

    func dragShift(_ shiftId: UUID, translation: CGSize) {
        guard let interaction = interaction(for: shiftId, mode: .move) else { return }
        let base = interaction.baseline

        let deltaMinutes = Int((translation.height / max(0.5, pixelsPerMinute)).rounded())
        let snappedDeltaMinutes = TimeSnapper.snap(deltaMinutes)
        let dayStride = max(100, dayColumnWidth)
        let rawDayDelta = translation.width / dayStride
        let deltaDays: Int
        if abs(rawDayDelta) < 0.35 {
            deltaDays = 0
        } else {
            deltaDays = Int(rawDayDelta.rounded())
        }

        var shifted = base
        shifted.dayOfWeek = max(0, min(6, base.dayOfWeek + deltaDays))

        let duration = max(minimumShiftDurationMinutes, base.durationMinutes)
        let newStart = TimeSnapper.snapAndClamp(
            base.startMinutes + snappedDeltaMinutes,
            step: 15,
            min: visibleStartMinutes,
            max: max(visibleStartMinutes, visibleEndMinutes - duration)
        )
        shifted.startMinutes = newStart
        shifted.endMinutes = min(visibleEndMinutes, newStart + duration)

        setPreviewShiftIfNeeded(shifted, for: shiftId)
    }

    func endDrag(for shiftId: UUID) {
        commitInteraction(for: shiftId)
    }

    func resizeShiftStart(_ shiftId: UUID, deltaY: CGFloat) {
        guard let interaction = interaction(for: shiftId, mode: .resizeTop) else { return }
        let baseline = interaction.baseline

        let deltaMinutes = TimeSnapper.snap(Int((deltaY / max(0.5, pixelsPerMinute)).rounded()))
        let newStart = TimeSnapper.snapAndClamp(
            baseline.startMinutes + deltaMinutes,
            step: 15,
            min: visibleStartMinutes,
            max: baseline.endMinutes - minimumShiftDurationMinutes
        )

        var updated = baseline
        updated.startMinutes = newStart
        setPreviewShiftIfNeeded(updated, for: shiftId)
    }

    func resizeShiftEnd(_ shiftId: UUID, deltaY: CGFloat) {
        guard let interaction = interaction(for: shiftId, mode: .resizeBottom) else { return }
        let baseline = interaction.baseline

        let deltaMinutes = TimeSnapper.snap(Int((deltaY / max(0.5, pixelsPerMinute)).rounded()))
        let newEnd = TimeSnapper.snapAndClamp(
            baseline.endMinutes + deltaMinutes,
            step: 15,
            min: baseline.startMinutes + minimumShiftDurationMinutes,
            max: visibleEndMinutes
        )

        var updated = baseline
        updated.endMinutes = newEnd
        setPreviewShiftIfNeeded(updated, for: shiftId)
    }

    func endResize(for shiftId: UUID) {
        commitInteraction(for: shiftId)
    }

    func yPosition(for shift: ScheduleDraftShift) -> CGFloat {
        CGFloat(shift.startMinutes - visibleStartMinutes) * pixelsPerMinute
    }

    func height(for shift: ScheduleDraftShift) -> CGFloat {
        max(18, CGFloat(shift.durationMinutes) * pixelsPerMinute)
    }

    func minutes(fromY y: CGFloat) -> Int {
        let raw = visibleStartMinutes + Int((y / max(0.5, pixelsPerMinute)).rounded())
        return TimeSnapper.snapAndClamp(
            raw,
            step: 15,
            min: visibleStartMinutes,
            max: visibleEndMinutes - minimumShiftDurationMinutes
        )
    }

    func shiftBorderColor(_ shift: ScheduleDraftShift) -> Color {
        if shift.id == selectedShiftID {
            return DesignSystem.Colors.accent
        }
        let warnings = warningsByShiftId[shift.id] ?? []
        if warnings.contains(where: { $0.severity == .critical }) { return DesignSystem.Colors.error }
        if warnings.contains(where: { $0.severity == .warning }) { return DesignSystem.Colors.warning }
        return Color.white.opacity(0.28)
    }

    func availabilityStatus(for employeeId: UUID) -> EmployeeAvailabilityStatus {
        AvailabilityService.availabilityStatusNow(
            employeeId: employeeId,
            weekStartDate: weekStartDate,
            weeklyWindows: availabilityWindows,
            unavailableDates: unavailableDates,
            shopId: shopId,
            timeZone: timeZone
        )
    }

    func publish(modelContext: ModelContext) throws -> Int {
        let normalizedWeekStart = ScheduleCalendarService.normalizedWeekStart(weekStartDate, in: timeZone)
        let calendar = ScheduleCalendarService.calendar(in: timeZone)
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: normalizedWeekStart) ?? normalizedWeekStart
        let scopedShopId = shopId

        let descriptor = FetchDescriptor<PlannedShift>(
            predicate: #Predicate { shift in
                shift.shopId == scopedShopId &&
                shift.startDate >= normalizedWeekStart &&
                shift.startDate < weekEnd
            }
        )
        let existing = try modelContext.fetch(descriptor)
        for shift in existing where shift.status != .completed {
            modelContext.delete(shift)
        }

        let employeesById = self.employeesById
        var count = 0
        for shift in draftShifts {
            guard shift.endMinutes > shift.startMinutes else { continue }
            guard let employeeId = shift.employeeId, let employee = employeesById[employeeId] else { continue }

            let dayDate = calendar.date(byAdding: .day, value: shift.dayOfWeek, to: normalizedWeekStart) ?? normalizedWeekStart
            let dayStart = calendar.startOfDay(for: dayDate)
            let startDate = calendar.date(byAdding: .minute, value: shift.startMinutes, to: dayStart) ?? dayStart
            let endDate = calendar.date(byAdding: .minute, value: shift.endMinutes, to: dayStart) ?? startDate

            modelContext.insert(
                PlannedShift(
                    shopId: shopId,
                    employee: employee,
                    dayDate: dayStart,
                    startDate: startDate,
                    endDate: endDate,
                    status: .published,
                    notes: shift.notes
                )
            )
            count += 1
        }

        try modelContext.save()
        return count
    }

    private func sanitizeShift(_ shift: ScheduleDraftShift) -> ScheduleDraftShift {
        var adjusted = shift
        adjusted.dayOfWeek = max(0, min(6, adjusted.dayOfWeek))

        let start = TimeSnapper.snapAndClamp(
            adjusted.startMinutes,
            step: 15,
            min: visibleStartMinutes,
            max: visibleEndMinutes - minimumShiftDurationMinutes
        )
        let end = TimeSnapper.snapAndClamp(
            adjusted.endMinutes,
            step: 15,
            min: start + minimumShiftDurationMinutes,
            max: visibleEndMinutes
        )

        adjusted.startMinutes = start
        adjusted.endMinutes = max(start + minimumShiftDurationMinutes, end)
        return adjusted
    }

    private func beginInteraction(for shiftId: UUID, mode: ShiftInteractionMode) {
        guard let shift = draftShifts.first(where: { $0.id == shiftId }) else { return }
        if interactions[shiftId]?.mode != mode {
            interactions[shiftId] = ShiftInteraction(mode: mode, baseline: shift)
            previewShifts.removeValue(forKey: shiftId)
        }
    }

    private func setPreviewShiftIfNeeded(_ shift: ScheduleDraftShift, for shiftId: UUID) {
        let current = previewShifts[shiftId] ?? draftShifts.first(where: { $0.id == shiftId })
        guard current != shift else { return }
        previewShifts[shiftId] = shift
    }

    private func recordUndoSnapshotIfNeeded() {
        if undoStack.last == draftShifts {
            return
        }
        undoStack.append(draftShifts)
        if undoStack.count > maxUndoDepth {
            undoStack.removeFirst(undoStack.count - maxUndoDepth)
        }
    }

    private func interaction(for shiftId: UUID, mode: ShiftInteractionMode) -> ShiftInteraction? {
        if let existing = interactions[shiftId], existing.mode == mode {
            return existing
        }
        beginInteraction(for: shiftId, mode: mode)
        return interactions[shiftId]
    }

    private func commitInteraction(for shiftId: UUID) {
        defer {
            interactions.removeValue(forKey: shiftId)
            previewShifts.removeValue(forKey: shiftId)
        }

        guard let preview = previewShifts[shiftId] else { return }
        guard let index = draftShifts.firstIndex(where: { $0.id == shiftId }) else { return }
        let sanitized = sanitizeShift(preview)
        guard draftShifts[index] != sanitized else { return }
        recordUndoSnapshotIfNeeded()
        draftShifts[index] = sanitized
        selectedShiftID = shiftId
        recalculateWarningsAndCoverage()
    }

    func recalculateWarningsAndCoverage() {
        coverageEvaluation = CoverageEvaluator.evaluate(
            coverageBlocks: coverageBlocks,
            draftShifts: draftShifts,
            visibleStartMinutes: visibleStartMinutes,
            visibleEndMinutes: visibleEndMinutes
        )

        var computedWarnings = CoverageEvaluator.coverageWarnings(from: coverageEvaluation)
        computedWarnings.append(
            contentsOf: ConflictService.detectEmployeeOverlap(
                shifts: draftShifts,
                employeesById: employeesById
            )
        )
        computedWarnings.append(
            contentsOf: ConflictService.overtimeWarnings(
                shifts: draftShifts,
                employeesById: employeesById
            )
        )

        for shift in draftShifts {
            guard let employeeId = shift.employeeId else { continue }
            let available = AvailabilityService.isAvailable(
                employeeId: employeeId,
                dayOfWeek: shift.dayOfWeek,
                startMinutes: shift.startMinutes,
                endMinutes: shift.endMinutes,
                weekStartDate: weekStartDate,
                weeklyWindows: availabilityWindows,
                unavailableDates: unavailableDates,
                shopId: shopId,
                timeZone: timeZone
            )
            if !available {
                let employeeName = employeesById[employeeId]?.name ?? "Employee"
                computedWarnings.append(
                    ScheduleDraftWarning(
                        kind: .availability,
                        severity: .warning,
                        message: "\(employeeName) is outside availability on \(ScheduleDayMapper.shortName(for: shift.dayOfWeek)).",
                        dayOfWeek: shift.dayOfWeek,
                        minute: shift.startMinutes,
                        shiftId: shift.id,
                        employeeId: employeeId
                    )
                )
            }
        }

        warnings = computedWarnings
            .sorted { lhs, rhs in
                if lhs.severity != rhs.severity { return lhs.severity > rhs.severity }
                return lhs.message < rhs.message
            }
    }
}
