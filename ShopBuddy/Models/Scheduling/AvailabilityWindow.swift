import Foundation

// Compatibility aliases for the visual scheduling module.
typealias AvailabilityWindow = EmployeeAvailabilityWindow
typealias UnavailableDate = EmployeeUnavailableDate

extension EmployeeAvailabilityWindow {
    var dayIndex: Int {
        get { ScheduleDayMapper.dayIndex(fromWeekday: dayOfWeek) }
        set { dayOfWeek = ScheduleDayMapper.weekday(fromDayIndex: newValue) }
    }

    var employeeId: UUID? {
        employee?.id
    }
}

extension EmployeeUnavailableDate {
    var employeeId: UUID? {
        employee?.id
    }

    var localDateString: String {
        let formatter = DateFormatter()
        formatter.calendar = ScheduleCalendarService.calendar(in: ShopContext.activeTimeZone)
        formatter.timeZone = ShopContext.activeTimeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
