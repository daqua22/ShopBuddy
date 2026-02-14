import Foundation

struct ScheduleValidationInput {
    let shopId: String
    let weekStartDate: Date
    let shifts: [DraftShift]
    let coverageRequirements: [CoverageRequirement]
    let employeesByID: [UUID: Employee]
    let availabilityContext: EmployeeAvailabilityContext
    let existingPlannedShifts: [PlannedShift]
    let constraints: ScheduleGenerationConstraints
    let timeZone: TimeZone
}

enum ScheduleValidationService {
    static func validate(_ input: ScheduleValidationInput) -> [ScheduleWarning] {
        var warnings: [ScheduleWarning] = []

        warnings.append(contentsOf: validateIndividualShifts(input))
        warnings.append(contentsOf: validateEmployeeConflicts(input))
        warnings.append(contentsOf: validateCoverage(input))
        warnings.append(contentsOf: validateRestWindows(input))
        warnings.append(contentsOf: validateWeeklyHours(input))

        return warnings
    }

    private static func validateIndividualShifts(_ input: ScheduleValidationInput) -> [ScheduleWarning] {
        var warnings: [ScheduleWarning] = []

        for shift in input.shifts {
            guard shift.endMinutes > shift.startMinutes else {
                warnings.append(
                    ScheduleWarning(
                        kind: .invalidShift,
                        message: "Shift has an invalid time range.",
                        dayOfWeek: shift.dayOfWeek,
                        employeeID: shift.employeeID
                    )
                )
                continue
            }

            guard let employeeID = shift.employeeID else {
                warnings.append(
                    ScheduleWarning(
                        kind: .unassigned,
                        message: "Shift on \(ScheduleCalendarService.dayName(for: shift.dayOfWeek)) has no employee assigned.",
                        dayOfWeek: shift.dayOfWeek,
                        employeeID: nil
                    )
                )
                continue
            }

            let dayDate = ScheduleCalendarService.date(
                for: input.weekStartDate,
                dayOfWeek: shift.dayOfWeek,
                minutesFromMidnight: 0,
                in: input.timeZone
            )
            let available = EmployeeAvailabilityService.isAvailable(
                employeeID: employeeID,
                shopId: input.shopId,
                dayDate: dayDate,
                dayOfWeek: shift.dayOfWeek,
                startMinutes: shift.startMinutes,
                endMinutes: shift.endMinutes,
                context: input.availabilityContext,
                timeZone: input.timeZone
            )
            if !available {
                let employeeName = input.employeesByID[employeeID]?.name ?? "Employee"
                warnings.append(
                    ScheduleWarning(
                        kind: .availability,
                        message: "\(employeeName) is outside availability on \(ScheduleCalendarService.dayName(for: shift.dayOfWeek)).",
                        dayOfWeek: shift.dayOfWeek,
                        employeeID: employeeID
                    )
                )
            }

            let durationHours = Double(shift.durationMinutes) / 60.0
            if durationHours > input.constraints.maxShiftLengthHours {
                warnings.append(
                    ScheduleWarning(
                        kind: .invalidShift,
                        message: "Shift exceeds max length (\(Int(input.constraints.maxShiftLengthHours))h).",
                        dayOfWeek: shift.dayOfWeek,
                        employeeID: shift.employeeID
                    )
                )
            }
        }

        return warnings
    }

    private static func validateEmployeeConflicts(_ input: ScheduleValidationInput) -> [ScheduleWarning] {
        var warnings: [ScheduleWarning] = []

        let groupedByEmployee = Dictionary(grouping: input.shifts.compactMap { shift -> (UUID, DraftShift)? in
            guard let employeeID = shift.employeeID else { return nil }
            return (employeeID, shift)
        }, by: { $0.0 })

        for (employeeID, tuples) in groupedByEmployee {
            let shifts = tuples.map(\.1).sorted(by: draftShiftSort)
            for index in shifts.indices {
                let left = shifts[index]
                for otherIndex in shifts.index(after: index)..<shifts.count {
                    let right = shifts[otherIndex]
                    if left.dayOfWeek != right.dayOfWeek {
                        break
                    }
                    if overlaps(left.startMinutes, left.endMinutes, right.startMinutes, right.endMinutes) {
                        warnings.append(
                            ScheduleWarning(
                                kind: .conflict,
                                message: "Overlapping shifts for \(input.employeesByID[employeeID]?.name ?? "employee").",
                                dayOfWeek: left.dayOfWeek,
                                employeeID: employeeID
                            )
                        )
                    }
                }
            }

            let existing = input.existingPlannedShifts.filter {
                $0.shopId == input.shopId && $0.employee?.id == employeeID
            }

            for shift in shifts {
                let shiftStart = ScheduleCalendarService.date(
                    for: input.weekStartDate,
                    dayOfWeek: shift.dayOfWeek,
                    minutesFromMidnight: shift.startMinutes,
                    in: input.timeZone
                )
                let shiftEnd = ScheduleCalendarService.date(
                    for: input.weekStartDate,
                    dayOfWeek: shift.dayOfWeek,
                    minutesFromMidnight: shift.endMinutes,
                    in: input.timeZone
                )

                let hasConflict = existing.contains { planned in
                    overlaps(shiftStart, shiftEnd, planned.startDate, planned.endDate)
                }
                if hasConflict {
                    warnings.append(
                        ScheduleWarning(
                            kind: .conflict,
                            message: "Conflicts with an existing planned shift.",
                            dayOfWeek: shift.dayOfWeek,
                            employeeID: employeeID
                        )
                    )
                }
            }
        }

        return warnings
    }

    private static func validateCoverage(_ input: ScheduleValidationInput) -> [ScheduleWarning] {
        var warnings: [ScheduleWarning] = []

        let requirements = input.coverageRequirements.filter {
            $0.shopId == input.shopId &&
            ScheduleCalendarService.normalizedWeekStart($0.weekStartDate, in: input.timeZone)
            == ScheduleCalendarService.normalizedWeekStart(input.weekStartDate, in: input.timeZone)
        }

        for requirement in requirements {
            let coveringCount = input.shifts.filter { shift in
                shift.dayOfWeek == requirement.dayOfWeek &&
                shift.employeeID != nil &&
                shift.startMinutes <= requirement.startMinutes &&
                shift.endMinutes >= requirement.endMinutes &&
                roleMatches(requirementRole: requirement.roleRequirement, shift: shift, employeesByID: input.employeesByID)
            }.count

            if coveringCount < requirement.headcount {
                let missing = requirement.headcount - coveringCount
                warnings.append(
                    ScheduleWarning(
                        kind: .uncovered,
                        message: "Uncovered slots: \(missing) needed on \(ScheduleCalendarService.dayName(for: requirement.dayOfWeek)) \(ScheduleCalendarService.timeLabel(for: requirement.startMinutes))-\(ScheduleCalendarService.timeLabel(for: requirement.endMinutes)).",
                        dayOfWeek: requirement.dayOfWeek,
                        employeeID: nil
                    )
                )
            }
        }

        return warnings
    }

    private static func validateRestWindows(_ input: ScheduleValidationInput) -> [ScheduleWarning] {
        var warnings: [ScheduleWarning] = []

        let grouped = Dictionary(grouping: input.shifts.compactMap { shift -> (UUID, DraftShift)? in
            guard let employeeID = shift.employeeID else { return nil }
            return (employeeID, shift)
        }, by: { $0.0 })

        for (employeeID, tuples) in grouped {
            let intervals = tuples.map { tuple -> (Date, Date, Int) in
                let shift = tuple.1
                let start = ScheduleCalendarService.date(
                    for: input.weekStartDate,
                    dayOfWeek: shift.dayOfWeek,
                    minutesFromMidnight: shift.startMinutes,
                    in: input.timeZone
                )
                let end = ScheduleCalendarService.date(
                    for: input.weekStartDate,
                    dayOfWeek: shift.dayOfWeek,
                    minutesFromMidnight: shift.endMinutes,
                    in: input.timeZone
                )
                return (start, end, shift.dayOfWeek)
            }
            .sorted { $0.0 < $1.0 }

            guard intervals.count > 1 else { continue }

            for pairIndex in 1..<intervals.count {
                let previous = intervals[pairIndex - 1]
                let current = intervals[pairIndex]
                let restHours = current.0.timeIntervalSince(previous.1) / 3600.0
                if restHours < input.constraints.minRestHoursBetweenShifts {
                    warnings.append(
                        ScheduleWarning(
                            kind: .restViolation,
                            message: "\(input.employeesByID[employeeID]?.name ?? "Employee") has only \(String(format: "%.1f", max(0, restHours)))h rest between shifts.",
                            dayOfWeek: current.2,
                            employeeID: employeeID
                        )
                    )
                }
            }
        }

        return warnings
    }

    private static func validateWeeklyHours(_ input: ScheduleValidationInput) -> [ScheduleWarning] {
        var warnings: [ScheduleWarning] = []

        var weeklyHours: [UUID: Double] = [:]
        for shift in input.shifts {
            guard let employeeID = shift.employeeID else { continue }
            weeklyHours[employeeID, default: 0] += Double(shift.durationMinutes) / 60.0
        }

        for planned in input.existingPlannedShifts where planned.shopId == input.shopId {
            guard let employeeID = planned.employee?.id else { continue }
            weeklyHours[employeeID, default: 0] += planned.durationHours
        }

        for (employeeID, hours) in weeklyHours where hours > input.constraints.maxHoursPerEmployeePerWeek {
            warnings.append(
                ScheduleWarning(
                    kind: .overtime,
                    message: "\(input.employeesByID[employeeID]?.name ?? "Employee") exceeds \(Int(input.constraints.maxHoursPerEmployeePerWeek))h/week (\(String(format: "%.1f", hours))h).",
                    dayOfWeek: nil,
                    employeeID: employeeID
                )
            )
        }

        return warnings
    }

    nonisolated private static func draftShiftSort(lhs: DraftShift, rhs: DraftShift) -> Bool {
        if lhs.dayOfWeek != rhs.dayOfWeek {
            return lhs.dayOfWeek < rhs.dayOfWeek
        }
        if lhs.startMinutes != rhs.startMinutes {
            return lhs.startMinutes < rhs.startMinutes
        }
        return lhs.endMinutes < rhs.endMinutes
    }

    nonisolated private static func overlaps(_ lhsStart: Int, _ lhsEnd: Int, _ rhsStart: Int, _ rhsEnd: Int) -> Bool {
        max(lhsStart, rhsStart) < min(lhsEnd, rhsEnd)
    }

    nonisolated private static func overlaps(_ lhsStart: Date, _ lhsEnd: Date, _ rhsStart: Date, _ rhsEnd: Date) -> Bool {
        max(lhsStart, rhsStart) < min(lhsEnd, rhsEnd)
    }

    nonisolated private static func roleMatches(
        requirementRole: EmployeeRole?,
        shift: DraftShift,
        employeesByID: [UUID: Employee]
    ) -> Bool {
        guard let requirementRole else { return true }
        guard let employeeID = shift.employeeID else { return false }
        return employeesByID[employeeID]?.role == requirementRole
    }
}
