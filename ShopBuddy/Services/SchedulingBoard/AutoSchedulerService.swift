import Foundation

struct AutoSchedulerInput {
    let shopId: String
    let weekStartDate: Date
    let employees: [Employee]
    let coverageBlocks: [CoverageRequirement]
    let availabilityWindows: [EmployeeAvailabilityWindow]
    let unavailableDates: [EmployeeUnavailableDate]
    let visibleStartMinutes: Int
    let visibleEndMinutes: Int
    let timeZone: TimeZone
}

enum AutoSchedulerService {
    static func generateOptions(input: AutoSchedulerInput) -> [ScheduleDraftOption] {
        guard !input.coverageBlocks.isEmpty else { return [] }

        let modes: [GenerationMode] = [.fairness, .consistency, .fewestShifts, .strictAvailability, .balanced]
        var options: [ScheduleDraftOption] = []
        var seenSignatures: Set<String> = []

        for (index, mode) in modes.enumerated() {
            let shifts = buildDraftShifts(input: input, mode: mode, seed: UInt64(index + 1))
            let signature = shifts
                .sorted {
                    if $0.dayOfWeek != $1.dayOfWeek { return $0.dayOfWeek < $1.dayOfWeek }
                    if $0.startMinutes != $1.startMinutes { return $0.startMinutes < $1.startMinutes }
                    if $0.endMinutes != $1.endMinutes { return $0.endMinutes < $1.endMinutes }
                    return ($0.employeeId?.uuidString ?? "open") < ($1.employeeId?.uuidString ?? "open")
                }
                .map { "\($0.employeeId?.uuidString ?? "open")-\($0.dayOfWeek)-\($0.startMinutes)-\($0.endMinutes)" }
                .joined(separator: "|")

            guard !signature.isEmpty else { continue }
            guard seenSignatures.insert(signature).inserted else { continue }

            let warnings = draftWarnings(shifts: shifts, input: input)
            let evaluation = CoverageEvaluator.evaluate(
                coverageBlocks: input.coverageBlocks,
                draftShifts: shifts,
                visibleStartMinutes: input.visibleStartMinutes,
                visibleEndMinutes: input.visibleEndMinutes
            )
            let coverageWarnings = CoverageEvaluator.coverageWarnings(from: evaluation)
            let mergedWarnings = Array(Set(warnings + coverageWarnings))

            let score = ScheduleScoringService.scoreDraft(
                shifts: shifts,
                evaluation: evaluation,
                warnings: mergedWarnings
            )

            options.append(
                ScheduleDraftOption(
                    name: mode.title,
                    shifts: shifts,
                    score: score,
                    warnings: mergedWarnings
                )
            )
        }

        return options
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.warningCount < $1.warningCount
            }
            .enumerated()
            .map { idx, option in
                var updated = option
                updated.name = "Option \(Character(UnicodeScalar(65 + idx)!)) · \(option.name)"
                return updated
            }
    }

    private static func buildDraftShifts(
        input: AutoSchedulerInput,
        mode: GenerationMode,
        seed: UInt64
    ) -> [ScheduleDraftShift] {
        var generator = SeededGenerator(seed: seed &* 0x9E3779B97F4A7C15)
        let blocks = input.coverageBlocks
            .sorted {
                if $0.dayIndex != $1.dayIndex { return $0.dayIndex < $1.dayIndex }
                if $0.startMinutes != $1.startMinutes { return $0.startMinutes < $1.startMinutes }
                return $0.endMinutes < $1.endMinutes
            }

        let activeEmployees = input.employees.filter(\.isActive)
        var shifts: [ScheduleDraftShift] = []
        var minutesByEmployee: [UUID: Int] = [:]

        for block in blocks {
            for _ in 0..<max(1, block.headcount) {
                let availableCandidates = activeEmployees.filter { employee in
                    isCandidateValid(
                        employeeId: employee.id,
                        dayOfWeek: block.dayIndex,
                        startMinutes: block.startMinutes,
                        endMinutes: block.endMinutes,
                        shifts: shifts,
                        input: input,
                        requireAvailability: true
                    )
                }

                let fallbackCandidates = activeEmployees.filter { employee in
                    isCandidateValid(
                        employeeId: employee.id,
                        dayOfWeek: block.dayIndex,
                        startMinutes: block.startMinutes,
                        endMinutes: block.endMinutes,
                        shifts: shifts,
                        input: input,
                        requireAvailability: false
                    )
                }

                let candidatePool: [Employee]
                if mode == .strictAvailability {
                    candidatePool = availableCandidates
                } else {
                    candidatePool = availableCandidates.isEmpty ? fallbackCandidates : availableCandidates
                }

                guard !candidatePool.isEmpty else {
                    shifts.append(
                        ScheduleDraftShift(
                            employeeId: nil,
                            dayOfWeek: block.dayIndex,
                            startMinutes: block.startMinutes,
                            endMinutes: block.endMinutes,
                            colorSeed: "open"
                        )
                    )
                    continue
                }

                let selected = candidatePool.min { lhs, rhs in
                    let lhsScore = candidateScore(
                        employee: lhs,
                        mode: mode,
                        dayOfWeek: block.dayIndex,
                        startMinutes: block.startMinutes,
                        existingShifts: shifts,
                        minutesByEmployee: minutesByEmployee,
                        random: Double.random(in: 0...0.35, using: &generator)
                    )
                    let rhsScore = candidateScore(
                        employee: rhs,
                        mode: mode,
                        dayOfWeek: block.dayIndex,
                        startMinutes: block.startMinutes,
                        existingShifts: shifts,
                        minutesByEmployee: minutesByEmployee,
                        random: Double.random(in: 0...0.35, using: &generator)
                    )
                    return lhsScore < rhsScore
                }

                guard let employee = selected else { continue }

                shifts.append(
                    ScheduleDraftShift(
                        employeeId: employee.id,
                        dayOfWeek: block.dayIndex,
                        startMinutes: block.startMinutes,
                        endMinutes: block.endMinutes,
                        colorSeed: employee.id.uuidString
                    )
                )
                minutesByEmployee[employee.id, default: 0] += max(0, block.endMinutes - block.startMinutes)
            }
        }

        return condense(shifts)
    }

    private static func candidateScore(
        employee: Employee,
        mode: GenerationMode,
        dayOfWeek: Int,
        startMinutes: Int,
        existingShifts: [ScheduleDraftShift],
        minutesByEmployee: [UUID: Int],
        random: Double
    ) -> Double {
        let assignedMinutes = Double(minutesByEmployee[employee.id, default: 0])

        let starts = existingShifts
            .filter { $0.employeeId == employee.id }
            .map(\.startMinutes)

        let consistencyPenalty: Double
        if starts.isEmpty {
            consistencyPenalty = 0
        } else {
            let avg = Double(starts.reduce(0, +)) / Double(starts.count)
            consistencyPenalty = abs(Double(startMinutes) - avg) / 120.0
        }

        let contiguousBonus = existingShifts.contains {
            $0.employeeId == employee.id &&
            $0.dayOfWeek == dayOfWeek &&
            ($0.endMinutes == startMinutes || $0.startMinutes == startMinutes)
        } ? -18.0 : 0

        switch mode {
        case .fairness:
            return assignedMinutes + consistencyPenalty * 30 + random * 20
        case .consistency:
            return consistencyPenalty * 80 + assignedMinutes * 0.25 + random * 20
        case .fewestShifts:
            return assignedMinutes * 0.7 + contiguousBonus + random * 25
        case .strictAvailability:
            return assignedMinutes + consistencyPenalty * 16 + random * 12
        case .balanced:
            return assignedMinutes * 0.65 + consistencyPenalty * 32 + contiguousBonus + random * 16
        }
    }

    private static func isCandidateValid(
        employeeId: UUID,
        dayOfWeek: Int,
        startMinutes: Int,
        endMinutes: Int,
        shifts: [ScheduleDraftShift],
        input: AutoSchedulerInput,
        requireAvailability: Bool
    ) -> Bool {
        let hasOverlap = shifts.contains {
            $0.employeeId == employeeId &&
            $0.dayOfWeek == dayOfWeek &&
            max($0.startMinutes, startMinutes) < min($0.endMinutes, endMinutes)
        }
        guard !hasOverlap else { return false }

        if requireAvailability {
            return AvailabilityService.isAvailable(
                employeeId: employeeId,
                dayOfWeek: dayOfWeek,
                startMinutes: startMinutes,
                endMinutes: endMinutes,
                weekStartDate: input.weekStartDate,
                weeklyWindows: input.availabilityWindows,
                unavailableDates: input.unavailableDates,
                shopId: input.shopId,
                timeZone: input.timeZone
            )
        }

        return true
    }

    private static func condense(_ shifts: [ScheduleDraftShift]) -> [ScheduleDraftShift] {
        let sorted = shifts.sorted {
            if $0.dayOfWeek != $1.dayOfWeek { return $0.dayOfWeek < $1.dayOfWeek }
            if $0.employeeId != $1.employeeId { return ($0.employeeId?.uuidString ?? "") < ($1.employeeId?.uuidString ?? "") }
            if $0.startMinutes != $1.startMinutes { return $0.startMinutes < $1.startMinutes }
            return $0.endMinutes < $1.endMinutes
        }

        var condensed: [ScheduleDraftShift] = []
        for shift in sorted {
            guard var last = condensed.last else {
                condensed.append(shift)
                continue
            }

            let canMerge =
                last.employeeId == shift.employeeId &&
                last.dayOfWeek == shift.dayOfWeek &&
                last.endMinutes == shift.startMinutes

            if canMerge {
                last.endMinutes = shift.endMinutes
                condensed[condensed.count - 1] = last
            } else {
                condensed.append(shift)
            }
        }

        return condensed
    }

    private static func draftWarnings(shifts: [ScheduleDraftShift], input: AutoSchedulerInput) -> [ScheduleDraftWarning] {
        let employeesById = Dictionary(uniqueKeysWithValues: input.employees.map { ($0.id, $0) })
        var warnings = ConflictService.detectEmployeeOverlap(shifts: shifts, employeesById: employeesById)

        warnings.append(contentsOf: ConflictService.overtimeWarnings(shifts: shifts, employeesById: employeesById))

        for shift in shifts {
            guard let employeeId = shift.employeeId else { continue }
            let isAvailable = AvailabilityService.isAvailable(
                employeeId: employeeId,
                dayOfWeek: shift.dayOfWeek,
                startMinutes: shift.startMinutes,
                endMinutes: shift.endMinutes,
                weekStartDate: input.weekStartDate,
                weeklyWindows: input.availabilityWindows,
                unavailableDates: input.unavailableDates,
                shopId: input.shopId,
                timeZone: input.timeZone
            )
            if !isAvailable {
                let employeeName = employeesById[employeeId]?.name ?? "Employee"
                warnings.append(
                    ScheduleDraftWarning(
                        kind: .availability,
                        severity: .warning,
                        message: "\(employeeName) is outside availability on \(ScheduleDayMapper.shortName(for: shift.dayOfWeek)).",
                        dayOfWeek: shift.dayOfWeek,
                        minute: shift.startMinutes,
                        shiftId: shift.id,
                        employeeId: employeeId
                    )
                )
            }
        }

        return warnings
    }
}

private enum GenerationMode: CaseIterable {
    case fairness
    case consistency
    case fewestShifts
    case strictAvailability
    case balanced

    var title: String {
        switch self {
        case .fairness: return "Fairness First"
        case .consistency: return "Consistency First"
        case .fewestShifts: return "Fewest Shifts"
        case .strictAvailability: return "Strict Availability"
        case .balanced: return "Balanced"
        }
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
