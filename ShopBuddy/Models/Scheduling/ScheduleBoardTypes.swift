import Foundation
import SwiftUI

// MARK: - Day Mapping (0 = Mon ... 6 = Sun)
enum ScheduleDayMapper {
    static let orderedDays: [Int] = [0, 1, 2, 3, 4, 5, 6]

    static func dayIndex(fromWeekday weekday: Int) -> Int {
        // Calendar weekday: 1=Sun ... 7=Sat
        (weekday + 5) % 7
    }

    static func weekday(fromDayIndex dayIndex: Int) -> Int {
        // 0=Mon -> 2, ... 5=Sat -> 7, 6=Sun -> 1
        ((dayIndex + 1) % 7) + 1
    }

    static func shortName(for dayIndex: Int) -> String {
        switch dayIndex {
        case 0: return "Mon"
        case 1: return "Tue"
        case 2: return "Wed"
        case 3: return "Thu"
        case 4: return "Fri"
        case 5: return "Sat"
        case 6: return "Sun"
        default: return "Day"
        }
    }
}

// MARK: - Draft Types
struct ScheduleDraftShift: Identifiable, Hashable {
    var id: UUID
    var employeeId: UUID?
    var dayOfWeek: Int // 0 = Mon ... 6 = Sun
    var startMinutes: Int
    var endMinutes: Int
    var colorSeed: String
    var notes: String?

    init(
        id: UUID = UUID(),
        employeeId: UUID?,
        dayOfWeek: Int,
        startMinutes: Int,
        endMinutes: Int,
        colorSeed: String = UUID().uuidString,
        notes: String? = nil
    ) {
        self.id = id
        self.employeeId = employeeId
        self.dayOfWeek = max(0, min(6, dayOfWeek))
        self.startMinutes = max(0, startMinutes)
        self.endMinutes = max(self.startMinutes + 15, endMinutes)
        self.colorSeed = colorSeed
        self.notes = notes
    }

    var durationMinutes: Int {
        max(0, endMinutes - startMinutes)
    }
}

struct CoverageBucketState: Identifiable, Hashable {
    let dayOfWeek: Int
    let bucketStartMinutes: Int
    let needed: Int
    let assigned: Int

    var id: String {
        "\(dayOfWeek)-\(bucketStartMinutes)"
    }

    var delta: Int {
        assigned - needed
    }
}

enum ScheduleBoardWarningSeverity: Int, Comparable, Codable {
    case info = 0
    case warning = 1
    case critical = 2

    static func < (lhs: ScheduleBoardWarningSeverity, rhs: ScheduleBoardWarningSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ScheduleBoardWarningKind: String, Codable {
    case coverageGap
    case conflict
    case availability
    case overtime
}

struct ScheduleDraftWarning: Identifiable, Hashable {
    let id = UUID()
    let kind: ScheduleBoardWarningKind
    let severity: ScheduleBoardWarningSeverity
    let message: String
    let dayOfWeek: Int?
    let minute: Int?
    let shiftId: UUID?
    let employeeId: UUID?
}

struct CoverageEvaluationResult: Hashable {
    var bucketsByDay: [Int: [CoverageBucketState]]
    var uncoveredBucketCount: Int
    var overCoveredBucketCount: Int

    static let empty = CoverageEvaluationResult(
        bucketsByDay: [:],
        uncoveredBucketCount: 0,
        overCoveredBucketCount: 0
    )
}

struct ScheduleDraftOption: Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var shifts: [ScheduleDraftShift]
    var score: Int
    var warnings: [ScheduleDraftWarning]

    var warningCount: Int {
        warnings.count
    }
}
