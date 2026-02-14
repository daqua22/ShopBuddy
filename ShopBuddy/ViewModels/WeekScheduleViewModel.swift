import SwiftUI
import Foundation
import Combine

struct WeekScheduledShift: Identifiable, Hashable {
    var id: UUID
    var employeeName: String
    var employeeId: UUID?
    var dayOfWeek: Int // Calendar weekday style: 1=Sun ... 7=Sat
    var startMinutes: Int
    var endMinutes: Int
    var color: Color

    init(
        id: UUID = UUID(),
        employeeName: String,
        employeeId: UUID? = nil,
        dayOfWeek: Int,
        startMinutes: Int,
        endMinutes: Int,
        color: Color = .blue
    ) {
        self.id = id
        self.employeeName = employeeName
        self.employeeId = employeeId
        self.dayOfWeek = dayOfWeek
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
        self.color = color
    }

    var durationMinutes: Int {
        max(0, endMinutes - startMinutes)
    }
}

final class WeekScheduleViewModel: ObservableObject {
    @Published var weekStartDate: Date
    @Published var shifts: [WeekScheduledShift]
    @Published var visibleStartMinutes: Int
    @Published var visibleEndMinutes: Int
    @Published var pixelsPerMinute: CGFloat
    @Published var dayColumnWidth: CGFloat

    private var dragStartCache: [UUID: (start: Int, end: Int)] = [:]

    init(
        weekStartDate: Date,
        shifts: [WeekScheduledShift],
        visibleStartMinutes: Int = 6 * 60 + 30,
        visibleEndMinutes: Int = 18 * 60 + 30,
        pixelsPerMinute: CGFloat = 1.4,
        dayColumnWidth: CGFloat = 180
    ) {
        self.weekStartDate = ScheduleCalendarService.normalizedWeekStart(weekStartDate, in: ShopContext.activeTimeZone)
        self.shifts = shifts
        self.visibleStartMinutes = visibleStartMinutes
        self.visibleEndMinutes = visibleEndMinutes
        self.pixelsPerMinute = pixelsPerMinute
        self.dayColumnWidth = dayColumnWidth
    }

    var totalVisibleMinutes: Int {
        max(60, visibleEndMinutes - visibleStartMinutes)
    }

    var dayOrderMondayFirst: [Int] {
        [2, 3, 4, 5, 6, 7, 1]
    }

    var isDraggingShift: Bool {
        !dragStartCache.isEmpty
    }

    func snapToQuarter(_ minutes: Int) -> Int {
        let remainder = minutes % 15
        if remainder == 0 { return minutes }
        let down = minutes - remainder
        let up = down + 15
        return (minutes - down) < (up - minutes) ? down : up
    }

    func beginDrag(for shiftID: UUID) {
        guard let shift = shifts.first(where: { $0.id == shiftID }) else { return }
        dragStartCache[shiftID] = (shift.startMinutes, shift.endMinutes)
    }

    func moveShift(_ shiftID: UUID, deltaMinutes: Int) {
        guard let base = dragStartCache[shiftID] else { return }
        let snappedDelta = snapToQuarter(deltaMinutes)
        updateShiftTime(
            shiftID,
            newStart: base.start + snappedDelta,
            newEnd: base.end + snappedDelta
        )
    }

    func endDrag(for shiftID: UUID) {
        dragStartCache[shiftID] = nil
    }

    func updateShiftTime(_ shiftID: UUID, newStart: Int, newEnd: Int) {
        guard let index = shifts.firstIndex(where: { $0.id == shiftID }) else { return }
        let duration = max(15, shifts[index].durationMinutes)
        var clampedStart = snapToQuarter(newStart)
        var clampedEnd = snapToQuarter(newEnd)

        if clampedEnd <= clampedStart {
            clampedEnd = clampedStart + duration
        }

        let minStart = visibleStartMinutes
        let maxEnd = visibleEndMinutes
        if clampedStart < minStart {
            let diff = minStart - clampedStart
            clampedStart += diff
            clampedEnd += diff
        }
        if clampedEnd > maxEnd {
            let diff = clampedEnd - maxEnd
            clampedStart -= diff
            clampedEnd -= diff
        }

        clampedStart = max(minStart, clampedStart)
        clampedEnd = min(maxEnd, max(clampedStart + 15, clampedEnd))

        shifts[index].startMinutes = clampedStart
        shifts[index].endMinutes = clampedEnd
    }

    func updateShift(_ updated: WeekScheduledShift) {
        guard let index = shifts.firstIndex(where: { $0.id == updated.id }) else { return }
        shifts[index] = updated
    }

    func deleteShift(_ shiftID: UUID) {
        shifts.removeAll { $0.id == shiftID }
    }

    func addShift(_ shift: WeekScheduledShift) {
        shifts.append(shift)
    }

    func shiftYPosition(_ shift: WeekScheduledShift) -> CGFloat {
        CGFloat(shift.startMinutes - visibleStartMinutes) * pixelsPerMinute
    }

    func shiftHeight(_ shift: WeekScheduledShift) -> CGFloat {
        max(18, CGFloat(shift.durationMinutes) * pixelsPerMinute)
    }

    func previousWeek() {
        let calendar = ScheduleCalendarService.calendar(in: ShopContext.activeTimeZone)
        let next = calendar.date(byAdding: .day, value: -7, to: weekStartDate) ?? weekStartDate
        weekStartDate = ScheduleCalendarService.normalizedWeekStart(next, in: ShopContext.activeTimeZone)
    }

    func nextWeek() {
        let calendar = ScheduleCalendarService.calendar(in: ShopContext.activeTimeZone)
        let next = calendar.date(byAdding: .day, value: 7, to: weekStartDate) ?? weekStartDate
        weekStartDate = ScheduleCalendarService.normalizedWeekStart(next, in: ShopContext.activeTimeZone)
    }
}
