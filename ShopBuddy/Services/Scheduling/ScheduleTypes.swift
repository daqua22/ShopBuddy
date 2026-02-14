import Foundation

struct DraftShift: Identifiable, Hashable {
    var id: UUID = UUID()
    var employeeID: UUID?
    var dayOfWeek: Int
    var startMinutes: Int
    var endMinutes: Int
    var roleRequirementRaw: String?
    var notes: String?

    init(
        id: UUID = UUID(),
        employeeID: UUID?,
        dayOfWeek: Int,
        startMinutes: Int,
        endMinutes: Int,
        roleRequirement: EmployeeRole? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.employeeID = employeeID
        self.dayOfWeek = dayOfWeek
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
        self.roleRequirementRaw = roleRequirement?.rawValue
        self.notes = notes
    }

    var roleRequirement: EmployeeRole? {
        get { roleRequirementRaw.flatMap(EmployeeRole.init(rawValue:)) }
        set { roleRequirementRaw = newValue?.rawValue }
    }

    var durationMinutes: Int {
        max(0, endMinutes - startMinutes)
    }
}

enum ScheduleWarningKind: String, CaseIterable {
    case uncovered = "Uncovered"
    case conflict = "Conflict"
    case overtime = "Overtime"
    case restViolation = "Rest Violation"
    case availability = "Availability"
    case invalidShift = "Invalid Shift"
    case unassigned = "Unassigned"
}

struct ScheduleWarning: Identifiable, Hashable {
    let id = UUID()
    let kind: ScheduleWarningKind
    let message: String
    let dayOfWeek: Int?
    let employeeID: UUID?
}

struct ScheduleOption: Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var score: Int
    var warnings: [ScheduleWarning]
    var shifts: [DraftShift]

    var warningsCount: Int {
        warnings.count
    }

    var totalShiftCount: Int {
        shifts.count
    }

    var totalHours: Double {
        shifts.reduce(0) { $0 + Double($1.durationMinutes) / 60.0 }
    }
}

struct ScheduleGenerationConstraints {
    var maxHoursPerEmployeePerWeek: Double = 40
    var maxShiftLengthHours: Double = 8
    var minRestHoursBetweenShifts: Double = 10
    var preferConsistentStartTimes: Bool = true
    var fairnessWeight: Double = 1.0
    var requestedOptionCount: Int = 5
}

