import Foundation

// Compatibility alias for coverage-driven scheduling module.
typealias CoverageBlock = CoverageRequirement

extension CoverageRequirement {
    var dayIndex: Int {
        get { ScheduleDayMapper.dayIndex(fromWeekday: dayOfWeek) }
        set { dayOfWeek = ScheduleDayMapper.weekday(fromDayIndex: newValue) }
    }

    var weekStartLocalDateString: String {
        let formatter = DateFormatter()
        formatter.calendar = ScheduleCalendarService.calendar(in: ShopContext.activeTimeZone)
        formatter.timeZone = ShopContext.activeTimeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: ScheduleCalendarService.normalizedWeekStart(weekStartDate, in: ShopContext.activeTimeZone))
    }
}
