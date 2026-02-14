import Foundation

enum ScheduleScoringService {
    static func scoreDraft(
        shifts: [ScheduleDraftShift],
        evaluation: CoverageEvaluationResult,
        warnings: [ScheduleDraftWarning]
    ) -> Int {
        let warningPenalty = warnings.reduce(into: 0) { partial, warning in
            switch warning.kind {
            case .coverageGap:
                partial += 220
            case .conflict:
                partial += 180
            case .availability:
                partial += 90
            case .overtime:
                partial += 40
            }
        }

        let uncoveredPenalty = evaluation.uncoveredBucketCount * 14
        let overCoveragePenalty = evaluation.overCoveredBucketCount * 3
        let simplicityBonus = max(0, 140 - shifts.count * 5)

        return max(0, 1000 - warningPenalty - uncoveredPenalty - overCoveragePenalty + simplicityBonus)
    }
}
