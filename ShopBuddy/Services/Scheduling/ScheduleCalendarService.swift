import Foundation

enum ScheduleCalendarService {
    static func calendar(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        // Scheduling UI is Monday-first (Mon..Sun) for consistent column/date mapping.
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    static func normalizedStartOfDay(_ date: Date, in timeZone: TimeZone) -> Date {
        calendar(in: timeZone).startOfDay(for: date)
    }

    static func normalizedWeekStart(_ date: Date, in timeZone: TimeZone) -> Date {
        let calendar = calendar(in: timeZone)
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components).map { calendar.startOfDay(for: $0) } ?? calendar.startOfDay(for: date)
    }

    static func dayOfWeek(for date: Date, in timeZone: TimeZone) -> Int {
        calendar(in: timeZone).component(.weekday, from: date)
    }

    static func minutesFromMidnight(for date: Date, in timeZone: TimeZone) -> Int {
        let calendar = calendar(in: timeZone)
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    static func date(
        for weekStart: Date,
        dayOfWeek: Int,
        minutesFromMidnight: Int,
        in timeZone: TimeZone
    ) -> Date {
        let calendar = calendar(in: timeZone)
        let normalizedWeekStart = normalizedWeekStart(weekStart, in: timeZone)
        let weekStartDay = calendar.component(.weekday, from: normalizedWeekStart)
        let dayOffset = (dayOfWeek - weekStartDay + 7) % 7
        let dayDate = calendar.date(byAdding: .day, value: dayOffset, to: normalizedWeekStart) ?? normalizedWeekStart
        return calendar.date(byAdding: .minute, value: minutesFromMidnight, to: dayDate) ?? dayDate
    }

    static func isSameDay(_ lhs: Date, _ rhs: Date, in timeZone: TimeZone) -> Bool {
        calendar(in: timeZone).isDate(lhs, inSameDayAs: rhs)
    }

    static func timeLabel(for minutes: Int) -> String {
        let safe = max(0, min(minutes, 24 * 60))
        let hours = safe / 60
        let mins = safe % 60
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "h:mm a"
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(year: 2000, month: 1, day: 1, hour: hours, minute: mins)) ?? Date()
        return formatter.string(from: date)
    }

    static func dayName(for dayOfWeek: Int) -> String {
        let symbols = calendar(in: ShopContext.activeTimeZone).weekdaySymbols
        let index = max(1, min(7, dayOfWeek)) - 1
        return symbols[index]
    }

    static func abbreviatedDateLabel(for date: Date, in timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.locale = Locale.current
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}
