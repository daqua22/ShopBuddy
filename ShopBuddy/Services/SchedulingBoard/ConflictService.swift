import Foundation

enum ConflictService {
    static func detectEmployeeOverlap(
        shifts: [ScheduleDraftShift],
        employeesById: [UUID: Employee]
    ) -> [ScheduleDraftWarning] {
        var warnings: [ScheduleDraftWarning] = []

        let grouped = Dictionary(grouping: shifts) { shift in
            "\(shift.employeeId?.uuidString ?? "open")-\(shift.dayOfWeek)"
        }

        for (_, dayShifts) in grouped {
            let sorted = dayShifts.sorted {
                if $0.startMinutes != $1.startMinutes { return $0.startMinutes < $1.startMinutes }
                return $0.endMinutes < $1.endMinutes
            }

            for index in sorted.indices where index > 0 {
                let previous = sorted[index - 1]
                let current = sorted[index]
                guard let employeeId = current.employeeId else { continue }

                if max(previous.startMinutes, current.startMinutes) < min(previous.endMinutes, current.endMinutes) {
                    let employeeName = employeesById[employeeId]?.name ?? "Employee"
                    warnings.append(
                        ScheduleDraftWarning(
                            kind: .conflict,
                            severity: .critical,
                            message: "Overlap for \(employeeName) on \(ScheduleDayMapper.shortName(for: current.dayOfWeek)).",
                            dayOfWeek: current.dayOfWeek,
                            minute: current.startMinutes,
                            shiftId: current.id,
                            employeeId: employeeId
                        )
                    )
                }
            }
        }

        return warnings
    }

    static func overtimeWarnings(
        shifts: [ScheduleDraftShift],
        employeesById: [UUID: Employee],
        defaultMaxHours: Int = 40
    ) -> [ScheduleDraftWarning] {
        var warnings: [ScheduleDraftWarning] = []
        var minutesByEmployee: [UUID: Int] = [:]

        for shift in shifts {
            guard let employeeId = shift.employeeId else { continue }
            minutesByEmployee[employeeId, default: 0] += shift.durationMinutes
        }

        for (employeeId, minutes) in minutesByEmployee {
            let maxMinutes = defaultMaxHours * 60
            guard minutes > maxMinutes else { continue }

            let name = employeesById[employeeId]?.name ?? "Employee"
            warnings.append(
                ScheduleDraftWarning(
                    kind: .overtime,
                    severity: .warning,
                    message: "\(name) exceeds \(defaultMaxHours)h this week.",
                    dayOfWeek: nil,
                    minute: nil,
                    shiftId: nil,
                    employeeId: employeeId
                )
            )
        }

        return warnings
    }
}
