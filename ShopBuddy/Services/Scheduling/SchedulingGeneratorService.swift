import Foundation

struct SchedulingGeneratorInput {
    let shopId: String
    let weekStartDate: Date
    let coverageRequirements: [CoverageRequirement]
    let employees: [Employee]
    let availabilityContext: EmployeeAvailabilityContext
    let existingPlannedShifts: [PlannedShift]
    let constraints: ScheduleGenerationConstraints
    let timeZone: TimeZone
}

enum SchedulingGeneratorService {
    static func generateOptions(input: SchedulingGeneratorInput) -> [ScheduleOption] {
        let weekStart = ScheduleCalendarService.normalizedWeekStart(input.weekStartDate, in: input.timeZone)
        let scopedCoverage = input.coverageRequirements
            .filter {
                $0.shopId == input.shopId &&
                ScheduleCalendarService.normalizedWeekStart($0.weekStartDate, in: input.timeZone) == weekStart
            }
            .sorted {
                if $0.dayOfWeek != $1.dayOfWeek { return $0.dayOfWeek < $1.dayOfWeek }
                if $0.startMinutes != $1.startMinutes { return $0.startMinutes < $1.startMinutes }
                return $0.endMinutes < $1.endMinutes
            }

        guard !scopedCoverage.isEmpty, !input.employees.isEmpty else { return [] }

        let targetCount = max(1, min(5, input.constraints.requestedOptionCount))
        var generated: [ScheduleOption] = []
        var signatures: Set<String> = []

        let attempts = max(12, targetCount * 8)
        for attempt in 0..<attempts where generated.count < targetCount {
            let option = buildOption(
                input: input,
                weekStart: weekStart,
                coverageRequirements: scopedCoverage,
                attempt: attempt
            )
            let signature = signatureForOption(option)
            if signatures.insert(signature).inserted {
                generated.append(option)
            }
        }

        let sorted = generated.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.warningsCount < rhs.warningsCount
        }

        return sorted.enumerated().map { index, option in
            var updated = option
            updated.name = "Option \(index + 1)"
            return updated
        }
    }

    private static func buildOption(
        input: SchedulingGeneratorInput,
        weekStart: Date,
        coverageRequirements: [CoverageRequirement],
        attempt: Int
    ) -> ScheduleOption {
        let employeesByID = Dictionary(uniqueKeysWithValues: input.employees.map { ($0.id, $0) })
        let seed = UInt64(attempt &+ 1) &* 0x9E3779B97F4A7C15
        var seeded = SeededGenerator(seed: seed)

        var slots: [CoverageRequirement] = []
        for requirement in coverageRequirements {
            for _ in 0..<max(1, requirement.headcount) {
                slots.append(requirement)
            }
        }

        if attempt % 2 == 1 {
            slots.shuffle(using: &seeded)
        }

        var shifts: [DraftShift] = []
        var assignedHours: [UUID: Double] = [:]

        for slot in slots {
            let candidates = candidateEmployees(
                for: slot,
                input: input,
                shiftsSoFar: shifts,
                assignedHours: assignedHours,
                employeesByID: employeesByID,
                weekStart: weekStart
            )

            guard let selected = pickBestCandidate(
                from: candidates,
                slot: slot,
                shiftsSoFar: shifts,
                assignedHours: assignedHours,
                preferConsistentStarts: input.constraints.preferConsistentStartTimes,
                fairnessWeight: input.constraints.fairnessWeight + Double(attempt % 3) * 0.3,
                rng: &seeded
            ) else {
                continue
            }

            let draftShift = DraftShift(
                employeeID: selected.id,
                dayOfWeek: slot.dayOfWeek,
                startMinutes: slot.startMinutes,
                endMinutes: slot.endMinutes,
                roleRequirement: slot.roleRequirement
            )
            shifts.append(draftShift)
            assignedHours[selected.id, default: 0] += Double(draftShift.durationMinutes) / 60.0
        }

        let condensed = condenseAdjacentShifts(shifts)
        let validationInput = ScheduleValidationInput(
            shopId: input.shopId,
            weekStartDate: weekStart,
            shifts: condensed,
            coverageRequirements: coverageRequirements,
            employeesByID: employeesByID,
            availabilityContext: input.availabilityContext,
            existingPlannedShifts: input.existingPlannedShifts.filter { $0.shopId == input.shopId },
            constraints: input.constraints,
            timeZone: input.timeZone
        )
        let warnings = ScheduleValidationService.validate(validationInput)
        let score = scoreOption(shifts: condensed, warnings: warnings, assignedHours: assignedHours)

        return ScheduleOption(name: "Option", score: score, warnings: warnings, shifts: condensed)
    }

    private static func candidateEmployees(
        for slot: CoverageRequirement,
        input: SchedulingGeneratorInput,
        shiftsSoFar: [DraftShift],
        assignedHours: [UUID: Double],
        employeesByID: [UUID: Employee],
        weekStart: Date
    ) -> [Employee] {
        input.employees.filter { employee in
            if let requiredRole = slot.roleRequirement, employee.role != requiredRole {
                return false
            }

            let dayDate = ScheduleCalendarService.date(
                for: weekStart,
                dayOfWeek: slot.dayOfWeek,
                minutesFromMidnight: 0,
                in: input.timeZone
            )
            let isAvailable = EmployeeAvailabilityService.isAvailable(
                employeeID: employee.id,
                shopId: input.shopId,
                dayDate: dayDate,
                dayOfWeek: slot.dayOfWeek,
                startMinutes: slot.startMinutes,
                endMinutes: slot.endMinutes,
                context: input.availabilityContext,
                timeZone: input.timeZone
            )
            if !isAvailable {
                return false
            }

            let conflictsWithDraft = shiftsSoFar.contains { other in
                guard other.employeeID == employee.id, other.dayOfWeek == slot.dayOfWeek else { return false }
                return overlaps(slot.startMinutes, slot.endMinutes, other.startMinutes, other.endMinutes)
            }
            if conflictsWithDraft {
                return false
            }

            let slotStart = ScheduleCalendarService.date(
                for: weekStart,
                dayOfWeek: slot.dayOfWeek,
                minutesFromMidnight: slot.startMinutes,
                in: input.timeZone
            )
            let slotEnd = ScheduleCalendarService.date(
                for: weekStart,
                dayOfWeek: slot.dayOfWeek,
                minutesFromMidnight: slot.endMinutes,
                in: input.timeZone
            )
            let conflictsWithExisting = input.existingPlannedShifts.contains {
                $0.shopId == input.shopId &&
                $0.employee?.id == employee.id &&
                overlaps(slotStart, slotEnd, $0.startDate, $0.endDate)
            }
            if conflictsWithExisting {
                return false
            }

            let currentHours = assignedHours[employee.id, default: 0]
            let proposedHours = currentHours + Double(slot.endMinutes - slot.startMinutes) / 60.0
            return proposedHours <= input.constraints.maxHoursPerEmployeePerWeek + 4
        }
    }

    private static func pickBestCandidate(
        from candidates: [Employee],
        slot: CoverageRequirement,
        shiftsSoFar: [DraftShift],
        assignedHours: [UUID: Double],
        preferConsistentStarts: Bool,
        fairnessWeight: Double,
        rng: inout SeededGenerator
    ) -> Employee? {
        guard !candidates.isEmpty else { return nil }

        let ranked = candidates.map { employee -> (Employee, Double) in
            let currentHours = assignedHours[employee.id, default: 0]
            let fairnessScore = currentHours * fairnessWeight

            var consistencyPenalty = 0.0
            if preferConsistentStarts {
                let starts = shiftsSoFar
                    .filter { $0.employeeID == employee.id }
                    .map(\.startMinutes)
                if !starts.isEmpty {
                    let averageStart = Double(starts.reduce(0, +)) / Double(starts.count)
                    consistencyPenalty = abs(Double(slot.startMinutes) - averageStart) / 180.0
                }
            }

            let randomJitter = Double.random(in: 0...0.8, using: &rng)
            return (employee, fairnessScore + consistencyPenalty + randomJitter)
        }

        return ranked.min(by: { $0.1 < $1.1 })?.0
    }

    private static func condenseAdjacentShifts(_ shifts: [DraftShift]) -> [DraftShift] {
        let sorted = shifts.sorted {
            if $0.employeeID != $1.employeeID {
                return ($0.employeeID?.uuidString ?? "") < ($1.employeeID?.uuidString ?? "")
            }
            if $0.dayOfWeek != $1.dayOfWeek { return $0.dayOfWeek < $1.dayOfWeek }
            if $0.startMinutes != $1.startMinutes { return $0.startMinutes < $1.startMinutes }
            return $0.endMinutes < $1.endMinutes
        }

        var merged: [DraftShift] = []
        for shift in sorted {
            guard var last = merged.last else {
                merged.append(shift)
                continue
            }
            let sameOwner = last.employeeID == shift.employeeID
            let sameDay = last.dayOfWeek == shift.dayOfWeek
            let sameRole = last.roleRequirementRaw == shift.roleRequirementRaw
            let touching = last.endMinutes == shift.startMinutes
            if sameOwner, sameDay, sameRole, touching {
                last.endMinutes = shift.endMinutes
                merged[merged.count - 1] = last
            } else {
                merged.append(shift)
            }
        }

        return merged
    }

    private static func scoreOption(
        shifts: [DraftShift],
        warnings: [ScheduleWarning],
        assignedHours: [UUID: Double]
    ) -> Int {
        let warningPenalty = warnings.reduce(into: 0) { partial, warning in
            switch warning.kind {
            case .conflict, .uncovered:
                partial += 400
            case .overtime, .restViolation:
                partial += 150
            case .availability, .invalidShift, .unassigned:
                partial += 80
            }
        }

        let fairnessPenalty: Int
        if assignedHours.isEmpty {
            fairnessPenalty = 0
        } else {
            let values = assignedHours.values
            let maxHours = values.max() ?? 0
            let minHours = values.min() ?? 0
            fairnessPenalty = Int((maxHours - minHours) * 15.0)
        }

        let simplicityBonus = max(0, 120 - shifts.count * 4)
        return max(0, 1000 - warningPenalty - fairnessPenalty + simplicityBonus)
    }

    private static func signatureForOption(_ option: ScheduleOption) -> String {
        option.shifts
            .sorted {
                if $0.dayOfWeek != $1.dayOfWeek { return $0.dayOfWeek < $1.dayOfWeek }
                if $0.startMinutes != $1.startMinutes { return $0.startMinutes < $1.startMinutes }
                if $0.endMinutes != $1.endMinutes { return $0.endMinutes < $1.endMinutes }
                return ($0.employeeID?.uuidString ?? "") < ($1.employeeID?.uuidString ?? "")
            }
            .map { shift in
                "\(shift.employeeID?.uuidString ?? "none")-\(shift.dayOfWeek)-\(shift.startMinutes)-\(shift.endMinutes)"
            }
            .joined(separator: "|")
    }

    private static func overlaps(_ lhsStart: Int, _ lhsEnd: Int, _ rhsStart: Int, _ rhsEnd: Int) -> Bool {
        max(lhsStart, rhsStart) < min(lhsEnd, rhsEnd)
    }

    private static func overlaps(_ lhsStart: Date, _ lhsEnd: Date, _ rhsStart: Date, _ rhsEnd: Date) -> Bool {
        max(lhsStart, rhsStart) < min(lhsEnd, rhsEnd)
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0xA4093822299F31D0 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
