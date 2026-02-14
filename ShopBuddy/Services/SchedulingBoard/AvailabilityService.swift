import Foundation

enum AvailabilityService {
    static func isAvailable(
        employeeId: UUID,
        dayOfWeek: Int,
        startMinutes: Int,
        endMinutes: Int,
        weekStartDate: Date,
        weeklyWindows: [EmployeeAvailabilityWindow],
        unavailableDates: [EmployeeUnavailableDate],
        shopId: String,
        timeZone: TimeZone
    ) -> Bool {
        guard endMinutes > startMinutes else { return false }

        let calendar = ScheduleCalendarService.calendar(in: timeZone)
        let dayDate = calendar.date(byAdding: .day, value: dayOfWeek, to: ScheduleCalendarService.normalizedWeekStart(weekStartDate, in: timeZone))
            ?? weekStartDate
        let normalizedDay = calendar.startOfDay(for: dayDate)

        let isUnavailableDate = unavailableDates.contains {
            $0.shopId == shopId &&
            $0.employee?.id == employeeId &&
            calendar.isDate($0.date, inSameDayAs: normalizedDay)
        }
        if isUnavailableDate { return false }

        let weekday = ScheduleDayMapper.weekday(fromDayIndex: dayOfWeek)
        let windows = weeklyWindows.filter {
            $0.shopId == shopId &&
            $0.employee?.id == employeeId &&
            $0.dayOfWeek == weekday
        }

        // If no windows are defined, treat as available (MVP default behavior).
        guard !windows.isEmpty else { return true }

        return windows.contains { window in
            window.startMinutes <= startMinutes && window.endMinutes >= endMinutes
        }
    }

    static func availabilityStatusNow(
        employeeId: UUID,
        weekStartDate: Date,
        weeklyWindows: [EmployeeAvailabilityWindow],
        unavailableDates: [EmployeeUnavailableDate],
        shopId: String,
        timeZone: TimeZone
    ) -> EmployeeAvailabilityStatus {
        let now = Date()
        let calendar = ScheduleCalendarService.calendar(in: timeZone)
        let weekday = calendar.component(.weekday, from: now)
        let dayIndex = ScheduleDayMapper.dayIndex(fromWeekday: weekday)
        let minutes = ScheduleCalendarService.minutesFromMidnight(for: now, in: timeZone)

        let canWorkNow = isAvailable(
            employeeId: employeeId,
            dayOfWeek: dayIndex,
            startMinutes: minutes,
            endMinutes: minutes + 15,
            weekStartDate: weekStartDate,
            weeklyWindows: weeklyWindows,
            unavailableDates: unavailableDates,
            shopId: shopId,
            timeZone: timeZone
        )

        if canWorkNow { return .available }

        let weekdayValue = ScheduleDayMapper.weekday(fromDayIndex: dayIndex)
        let hasAnyWindowToday = weeklyWindows.contains {
            $0.shopId == shopId &&
            $0.employee?.id == employeeId &&
            $0.dayOfWeek == weekdayValue
        }
        return hasAnyWindowToday ? .partial : .unavailable
    }
}

enum EmployeeAvailabilityStatus {
    case available
    case partial
    case unavailable
}
