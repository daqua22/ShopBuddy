import Foundation
import SwiftData



// MARK: - Employee Role
enum EmployeeRole: String, Codable, CaseIterable {
    case manager = "Manager"
    case shiftLead = "Shift Lead"
    case employee = "Employee"
    
    var sortOrder: Int {
        switch self {
        case .manager: return 0
        case .shiftLead: return 1
        case .employee: return 2
        }
    }
}

// MARK: - Employee
@Model
final class Employee {
    var id: UUID
    var name: String
    var pin: String
    var roleRaw: String
    var hourlyWage: Double?
    var createdAt: Date
    var isActive: Bool
    
    @Relationship(deleteRule: .cascade, inverse: \Shift.employee)
    var shifts: [Shift]
    
    var role: EmployeeRole {
        get { EmployeeRole(rawValue: roleRaw) ?? .employee }
        set { roleRaw = newValue.rawValue }
    }
    
    init(name: String, pin: String, role: EmployeeRole, hourlyWage: Double? = nil) {
        self.id = UUID()
        self.name = name
        self.pin = pin
        self.roleRaw = role.rawValue
        self.hourlyWage = hourlyWage
        self.createdAt = Date()
        self.isActive = true
        self.shifts = []
    }
    
    var isClockedIn: Bool {
        shifts.contains { $0.clockOutTime == nil }
    }
    
    var currentShift: Shift? {
        shifts.first { $0.clockOutTime == nil }
    }
}

// MARK: - Inventory Hierarchy
@Model
final class InventoryCategory {
    var id: UUID
    var name: String // e.g., "Weekly", "Monthly"
    @Relationship(deleteRule: .cascade) var locations: [InventoryLocation] = []
    
    init(name: String) {
        self.id = UUID()
        self.name = name
    }
}

@Model
final class InventoryLocation {
    var id: UUID
    var name: String // e.g., "Bar Fridge", "Back Storage"
    var category: InventoryCategory?
    @Relationship(deleteRule: .cascade) var items: [InventoryItem] = []
    
    init(name: String) {
        self.id = UUID()
        self.name = name
    }
}

@Model
final class InventoryItem {
    var id: UUID
    var name: String
    var stockLevel: Double
    var parLevel: Double
    var unitType: String
    var notes: String?
    var lastRestocked: Date?
    var location: InventoryLocation?
    
    init(name: String, stockLevel: Double, parLevel: Double, unitType: String, notes: String? = nil) {
        self.id = UUID()
        self.name = name
        self.stockLevel = stockLevel
        self.parLevel = parLevel
        self.unitType = unitType
        self.notes = notes
        self.lastRestocked = Date()
    }
    
    var stockPercentage: Double {
        guard parLevel > 0 else { return 0 }
        return min(stockLevel / parLevel, 1.0)
    }
    
    var isBelowPar: Bool {
        stockLevel < parLevel
    }
}

// MARK: - Other Models (Shift, Tips, Payroll, Settings)
@Model
final class Shift {
    var id: UUID
    var employee: Employee?
    var clockInTime: Date
    var clockOutTime: Date?
    
    init(employee: Employee) {
        self.id = UUID()
        self.employee = employee
        self.clockInTime = Date()
    }
    
    var isComplete: Bool { clockOutTime != nil }
    var hoursWorked: Double {
        let end = clockOutTime ?? Date()
        return end.timeIntervalSince(clockInTime) / 3600.0
    }
}

@Model
final class DailyTips {
    var id: UUID
    var date: Date
    var totalAmount: Double
    var isPaid: Bool
    var paidDate: Date?
    
    init(date: Date, totalAmount: Double) {
        self.id = UUID()
        self.date = Calendar.current.startOfDay(for: date)
        self.totalAmount = totalAmount
        self.isPaid = false
    }
}

@Model
final class AppSettings {
    var id: UUID
    var allowEmployeeInventoryEdit: Bool
    
    init() {
        self.id = UUID()
        self.allowEmployeeInventoryEdit = false
    }
}

// Keep Checklist models as they were...
@Model
final class ChecklistTemplate {
    var id: UUID
    var title: String
    @Relationship(deleteRule: .cascade) var tasks: [ChecklistTask] = []
    init(title: String) { self.id = UUID(); self.title = title }
}

@Model
final class ChecklistTask {
    var id: UUID
    var title: String
    var isCompleted: Bool = false
    var sortOrder: Int
    var template: ChecklistTemplate?
    init(title: String, sortOrder: Int) { self.id = UUID(); self.title = title; self.sortOrder = sortOrder }
}

