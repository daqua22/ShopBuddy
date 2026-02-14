import Foundation

enum TimeSnapper {
    static func snap(_ minutes: Int, step: Int = 15) -> Int {
        guard step > 0 else { return minutes }
        let lower = (minutes / step) * step
        let upper = lower + step
        return (minutes - lower) < (upper - minutes) ? lower : upper
    }

    static func clamp(_ minutes: Int, min minValue: Int, max maxValue: Int) -> Int {
        max(minValue, min(maxValue, minutes))
    }

    static func snapAndClamp(_ minutes: Int, step: Int = 15, min minValue: Int, max maxValue: Int) -> Int {
        clamp(snap(minutes, step: step), min: minValue, max: maxValue)
    }
}
