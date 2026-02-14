import Foundation

struct EmployeeAvailabilityContext {
    let weeklyWindows: [EmployeeAvailabilityWindow]
    let overrides: [EmployeeAvailabilityOverride]
    let unavailableDates: [EmployeeUnavailableDate]
}

enum EmployeeAvailabilityService {
    static func isAvailable(
        employeeID: UUID,
        shopId: String,
        dayDate: Date,
        dayOfWeek: Int,
        startMinutes: Int,
        endMinutes: Int,
        context: EmployeeAvailabilityContext,
        timeZone: TimeZone
    ) -> Bool {
        guard endMinutes > startMinutes else { return false }

        let normalizedDay = ScheduleCalendarService.normalizedStartOfDay(dayDate, in: timeZone)

        if context.unavailableDates.contains(where: {
            $0.shopId == shopId &&
            $0.employee?.id == employeeID &&
            ScheduleCalendarService.isSameDay($0.date, normalizedDay, in: timeZone)
        }) {
            return false
        }

        let matchingOverrides = context.overrides.filter {
            $0.shopId == shopId &&
            $0.employee?.id == employeeID &&
            ScheduleCalendarService.isSameDay($0.date, normalizedDay, in: timeZone)
        }

        let hasUnavailableOverride = matchingOverrides.contains {
            !$0.isAvailable && overlaps(startMinutes, endMinutes, $0.startMinutes, $0.endMinutes)
        }
        if hasUnavailableOverride {
            return false
        }

        let windowsForDay = context.weeklyWindows.filter {
            $0.shopId == shopId &&
            $0.employee?.id == employeeID &&
            $0.dayOfWeek == dayOfWeek
        }

        let coveredByWindow: Bool
        if windowsForDay.isEmpty {
            coveredByWindow = true
        } else {
            coveredByWindow = windowsForDay.contains { contains($0.startMinutes, $0.endMinutes, startMinutes, endMinutes) }
        }

        if coveredByWindow {
            return true
        }

        return matchingOverrides.contains {
            $0.isAvailable && contains($0.startMinutes, $0.endMinutes, startMinutes, endMinutes)
        }
    }

    private static func contains(_ outerStart: Int, _ outerEnd: Int, _ innerStart: Int, _ innerEnd: Int) -> Bool {
        outerStart <= innerStart && outerEnd >= innerEnd
    }

    private static func overlaps(_ lhsStart: Int, _ lhsEnd: Int, _ rhsStart: Int, _ rhsEnd: Int) -> Bool {
        max(lhsStart, rhsStart) < min(lhsEnd, rhsEnd)
    }
}

