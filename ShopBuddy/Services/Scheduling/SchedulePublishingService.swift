import Foundation
import SwiftData

enum SchedulePublishingError: LocalizedError {
    case employeeNotFound
    case invalidShift

    var errorDescription: String? {
        switch self {
        case .employeeNotFound:
            return "One or more shifts are missing an employee assignment."
        case .invalidShift:
            return "One or more shifts has an invalid time range."
        }
    }
}

enum SchedulePublishingService {
    @discardableResult
    static func publish(
        shifts: [DraftShift],
        shopId: String,
        weekStartDate: Date,
        employeesByID: [UUID: Employee],
        modelContext: ModelContext,
        timeZone: TimeZone
    ) throws -> Int {
        try validate(shifts: shifts, employeesByID: employeesByID)

        let normalizedWeekStart = ScheduleCalendarService.normalizedWeekStart(weekStartDate, in: timeZone)
        let calendar = ScheduleCalendarService.calendar(in: timeZone)
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: normalizedWeekStart) ?? normalizedWeekStart

        let existingDescriptor = FetchDescriptor<PlannedShift>(
            predicate: #Predicate { shift in
                shift.shopId == shopId &&
                shift.startDate >= normalizedWeekStart &&
                shift.startDate < weekEnd
            }
        )
        let existing = try modelContext.fetch(existingDescriptor)
        for shift in existing where shift.status != .completed {
            modelContext.delete(shift)
        }

        var publishedCount = 0
        for draft in shifts {
            guard let employeeID = draft.employeeID, let employee = employeesByID[employeeID] else { continue }

            let dayDate = ScheduleCalendarService.date(
                for: normalizedWeekStart,
                dayOfWeek: draft.dayOfWeek,
                minutesFromMidnight: 0,
                in: timeZone
            )
            let startDate = ScheduleCalendarService.date(
                for: normalizedWeekStart,
                dayOfWeek: draft.dayOfWeek,
                minutesFromMidnight: draft.startMinutes,
                in: timeZone
            )
            let endDate = ScheduleCalendarService.date(
                for: normalizedWeekStart,
                dayOfWeek: draft.dayOfWeek,
                minutesFromMidnight: draft.endMinutes,
                in: timeZone
            )

            let planned = PlannedShift(
                shopId: shopId,
                employee: employee,
                dayDate: dayDate,
                startDate: startDate,
                endDate: endDate,
                status: .published,
                roleRequirement: draft.roleRequirement,
                notes: draft.notes
            )
            modelContext.insert(planned)
            publishedCount += 1
        }

        try modelContext.save()
        return publishedCount
    }

    @discardableResult
    static func publishMonthFromWeekTemplate(
        shifts: [DraftShift],
        shopId: String,
        anchorWeekStartDate: Date,
        employeesByID: [UUID: Employee],
        modelContext: ModelContext,
        timeZone: TimeZone
    ) throws -> Int {
        try validate(shifts: shifts, employeesByID: employeesByID)

        let calendar = ScheduleCalendarService.calendar(in: timeZone)
        let normalizedWeekStart = ScheduleCalendarService.normalizedWeekStart(anchorWeekStartDate, in: timeZone)
        guard let monthInterval = calendar.dateInterval(of: .month, for: normalizedWeekStart) else {
            return 0
        }

        let monthStart = calendar.startOfDay(for: monthInterval.start)
        let monthEnd = monthInterval.end

        let existingDescriptor = FetchDescriptor<PlannedShift>(
            predicate: #Predicate { shift in
                shift.shopId == shopId &&
                shift.startDate >= monthStart &&
                shift.startDate < monthEnd
            }
        )
        let existing = try modelContext.fetch(existingDescriptor)
        for shift in existing where shift.status != .completed {
            modelContext.delete(shift)
        }

        let shiftsByDayOfWeek = Dictionary(grouping: shifts, by: \.dayOfWeek)
        var publishedCount = 0
        var cursor = monthStart

        while cursor < monthEnd {
            let dayOfWeek = calendar.component(.weekday, from: cursor)
            let templateShifts = shiftsByDayOfWeek[dayOfWeek] ?? []
            for draft in templateShifts {
                guard let employeeID = draft.employeeID, let employee = employeesByID[employeeID] else { continue }

                let dayStart = calendar.startOfDay(for: cursor)
                let startDate = calendar.date(byAdding: .minute, value: draft.startMinutes, to: dayStart) ?? dayStart
                let endDate = calendar.date(byAdding: .minute, value: draft.endMinutes, to: dayStart) ?? startDate

                let planned = PlannedShift(
                    shopId: shopId,
                    employee: employee,
                    dayDate: dayStart,
                    startDate: startDate,
                    endDate: endDate,
                    status: .published,
                    roleRequirement: draft.roleRequirement,
                    notes: draft.notes
                )
                modelContext.insert(planned)
                publishedCount += 1
            }

            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? monthEnd
        }

        try modelContext.save()
        return publishedCount
    }

    private static func validate(shifts: [DraftShift], employeesByID: [UUID: Employee]) throws {
        for draft in shifts {
            guard draft.endMinutes > draft.startMinutes else {
                throw SchedulePublishingError.invalidShift
            }
            guard let employeeID = draft.employeeID, employeesByID[employeeID] != nil else {
                throw SchedulePublishingError.employeeNotFound
            }
        }
    }
}
