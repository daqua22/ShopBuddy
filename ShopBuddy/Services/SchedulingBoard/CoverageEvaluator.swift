import Foundation

enum CoverageEvaluator {
    static func evaluate(
        coverageBlocks: [CoverageRequirement],
        draftShifts: [ScheduleDraftShift],
        visibleStartMinutes: Int,
        visibleEndMinutes: Int
    ) -> CoverageEvaluationResult {
        let start = TimeSnapper.snapAndClamp(visibleStartMinutes, step: 15, min: 0, max: 24 * 60)
        let end = TimeSnapper.snapAndClamp(visibleEndMinutes, step: 15, min: start + 15, max: 24 * 60)

        var needed: [String: Int] = [:]
        var assigned: [String: Int] = [:]

        for block in coverageBlocks {
            let day = block.dayIndex
            let blockStart = max(start, TimeSnapper.snap(block.startMinutes))
            let blockEnd = min(end, TimeSnapper.snap(block.endMinutes))
            guard blockEnd > blockStart else { continue }

            for minute in stride(from: blockStart, to: blockEnd, by: 15) {
                let key = bucketKey(day: day, minute: minute)
                needed[key, default: 0] += max(1, block.headcount)
            }
        }

        for shift in draftShifts {
            let shiftStart = max(start, TimeSnapper.snap(shift.startMinutes))
            let shiftEnd = min(end, TimeSnapper.snap(shift.endMinutes))
            guard shiftEnd > shiftStart else { continue }

            for minute in stride(from: shiftStart, to: shiftEnd, by: 15) {
                let key = bucketKey(day: shift.dayOfWeek, minute: minute)
                assigned[key, default: 0] += 1
            }
        }

        var bucketsByDay: [Int: [CoverageBucketState]] = [:]
        var uncoveredCount = 0
        var overCoveredCount = 0

        for day in ScheduleDayMapper.orderedDays {
            var buckets: [CoverageBucketState] = []
            for minute in stride(from: start, to: end, by: 15) {
                let key = bucketKey(day: day, minute: minute)
                let neededCount = needed[key, default: 0]
                let assignedCount = assigned[key, default: 0]
                let bucket = CoverageBucketState(
                    dayOfWeek: day,
                    bucketStartMinutes: minute,
                    needed: neededCount,
                    assigned: assignedCount
                )
                if bucket.delta < 0 { uncoveredCount += 1 }
                if bucket.delta > 0 { overCoveredCount += 1 }
                buckets.append(bucket)
            }
            bucketsByDay[day] = buckets
        }

        return CoverageEvaluationResult(
            bucketsByDay: bucketsByDay,
            uncoveredBucketCount: uncoveredCount,
            overCoveredBucketCount: overCoveredCount
        )
    }

    static func coverageWarnings(from result: CoverageEvaluationResult) -> [ScheduleDraftWarning] {
        var warnings: [ScheduleDraftWarning] = []
        for day in ScheduleDayMapper.orderedDays {
            let uncovered = (result.bucketsByDay[day] ?? []).filter { $0.delta < 0 }
            guard let first = uncovered.first else { continue }

            warnings.append(
                ScheduleDraftWarning(
                    kind: .coverageGap,
                    severity: .critical,
                    message: "Coverage gap on \(ScheduleDayMapper.shortName(for: day)) around \(ScheduleCalendarService.timeLabel(for: first.bucketStartMinutes)).",
                    dayOfWeek: day,
                    minute: first.bucketStartMinutes,
                    shiftId: nil,
                    employeeId: nil
                )
            )
        }
        return warnings
    }

    private static func bucketKey(day: Int, minute: Int) -> String {
        "\(day)-\(minute)"
    }
}
