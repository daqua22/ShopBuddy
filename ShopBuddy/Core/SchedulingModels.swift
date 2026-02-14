import Foundation
import SwiftData

enum PlannedShiftStatus: String, Codable, CaseIterable {
    case planned = "Planned"
    case published = "Published"
    case completed = "Completed"
}

@Model
final class CoverageRequirement {
    var id: UUID
    var shopId: String
    var weekStartDate: Date
    var dayOfWeek: Int
    var startMinutes: Int
    var endMinutes: Int
    var headcount: Int
    var roleRequirementRaw: String?
    var notes: String?

    init(
        shopId: String,
        weekStartDate: Date,
        dayOfWeek: Int,
        startMinutes: Int,
        endMinutes: Int,
        headcount: Int,
        roleRequirement: EmployeeRole? = nil,
        notes: String? = nil
    ) {
        self.id = UUID()
        self.shopId = shopId
        self.weekStartDate = weekStartDate
        self.dayOfWeek = dayOfWeek
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
        self.headcount = max(1, headcount)
        self.roleRequirementRaw = roleRequirement?.rawValue
        self.notes = notes
    }

    var roleRequirement: EmployeeRole? {
        get { roleRequirementRaw.flatMap(EmployeeRole.init(rawValue:)) }
        set { roleRequirementRaw = newValue?.rawValue }
    }
}

@Model
final class EmployeeAvailabilityWindow {
    var id: UUID
    var shopId: String
    var dayOfWeek: Int
    var startMinutes: Int
    var endMinutes: Int
    var employee: Employee?

    init(
        shopId: String,
        employee: Employee?,
        dayOfWeek: Int,
        startMinutes: Int,
        endMinutes: Int
    ) {
        self.id = UUID()
        self.shopId = shopId
        self.employee = employee
        self.dayOfWeek = dayOfWeek
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
    }
}

@Model
final class EmployeeAvailabilityOverride {
    var id: UUID
    var shopId: String
    var date: Date
    var startMinutes: Int
    var endMinutes: Int
    var isAvailable: Bool
    var notes: String?
    var employee: Employee?

    init(
        shopId: String,
        employee: Employee?,
        date: Date,
        startMinutes: Int,
        endMinutes: Int,
        isAvailable: Bool,
        notes: String? = nil
    ) {
        self.id = UUID()
        self.shopId = shopId
        self.employee = employee
        self.date = date
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
        self.isAvailable = isAvailable
        self.notes = notes
    }
}

@Model
final class EmployeeUnavailableDate {
    var id: UUID
    var shopId: String
    var date: Date
    var reason: String?
    var employee: Employee?

    init(shopId: String, employee: Employee?, date: Date, reason: String? = nil) {
        self.id = UUID()
        self.shopId = shopId
        self.employee = employee
        self.date = date
        self.reason = reason
    }
}

@Model
final class PlannedShift {
    var id: UUID
    var shopId: String
    var dayDate: Date
    var startDate: Date
    var endDate: Date
    var statusRaw: String
    var notes: String?
    var createdAt: Date
    var publishedAt: Date?
    var roleRequirementRaw: String?
    var employee: Employee?

    init(
        shopId: String,
        employee: Employee?,
        dayDate: Date,
        startDate: Date,
        endDate: Date,
        status: PlannedShiftStatus = .planned,
        roleRequirement: EmployeeRole? = nil,
        notes: String? = nil
    ) {
        self.id = UUID()
        self.shopId = shopId
        self.employee = employee
        self.dayDate = dayDate
        self.startDate = startDate
        self.endDate = endDate
        self.statusRaw = status.rawValue
        self.notes = notes
        self.createdAt = Date()
        self.publishedAt = status == .published ? Date() : nil
        self.roleRequirementRaw = roleRequirement?.rawValue
    }

    var status: PlannedShiftStatus {
        get { PlannedShiftStatus(rawValue: statusRaw) ?? .planned }
        set {
            statusRaw = newValue.rawValue
            if newValue == .published {
                publishedAt = publishedAt ?? Date()
            }
        }
    }

    var roleRequirement: EmployeeRole? {
        get { roleRequirementRaw.flatMap(EmployeeRole.init(rawValue:)) }
        set { roleRequirementRaw = newValue?.rawValue }
    }

    var durationHours: Double {
        max(0, endDate.timeIntervalSince(startDate) / 3600.0)
    }
}

