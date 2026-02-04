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
    var emoji: String // e.g., "📦", "📅"
    @Relationship(deleteRule: .cascade) var locations: [InventoryLocation] = []
    
    init(name: String, emoji: String = "📦") {
        self.id = UUID()
        self.name = name
        self.emoji = emoji
    }
    
    // Computed properties for statistics
    var locationCount: Int {
        locations.count
    }
    
    var totalItemCount: Int {
        locations.reduce(0) { $0 + $1.items.count }
    }
}

@Model
final class InventoryLocation {
    var id: UUID
    var name: String // e.g., "Bar Fridge", "Back Storage"
    var emoji: String // e.g., "❄️", "📦"
    var category: InventoryCategory?
    @Relationship(deleteRule: .cascade) var items: [InventoryItem] = []
    
    init(name: String, emoji: String = "📍") {
        self.id = UUID()
        self.name = name
        self.emoji = emoji
    }
}

@Model
final class InventoryItem {
    var id: UUID
    var name: String
    var stockLevel: Double
    var parLevel: Double
    var amountOnHand: Double // NEW: Actual amount physically present
    var unitType: String
    var vendor: String? // NEW: Supplier/vendor name
    var notes: String?
    var lastRestocked: Date?
    var location: InventoryLocation?
    
    init(name: String, stockLevel: Double, parLevel: Double, unitType: String, amountOnHand: Double = 0, vendor: String? = nil, notes: String? = nil) {
        self.id = UUID()
        self.name = name
        self.stockLevel = stockLevel
        self.parLevel = parLevel
        self.amountOnHand = amountOnHand
        self.unitType = unitType
        self.vendor = vendor
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

// MARK: - Unit Types
enum UnitType: String, CaseIterable {
    case bottles = "Bottles"
    case cans = "Cans"
    case boxes = "Boxes"
    case bags = "Bags"
    case kilograms = "kg"
    case grams = "g"
    case liters = "L"
    case milliliters = "mL"
    case pounds = "lbs"
    case ounces = "oz"
    case pieces = "Pieces"
    case units = "Units"
    case packs = "Packs"
    case cases = "Cases"
    case other = "Other"
}

// MARK: - Shift
@Model
final class Shift {
    var id: UUID
    var employee: Employee?
    var clockInTime: Date
    var clockOutTime: Date?
    var includeTips: Bool
    
    init(employee: Employee) {
        self.id = UUID()
        self.employee = employee
        self.clockInTime = Date()
        self.includeTips = true
    }
    
    var isComplete: Bool { clockOutTime != nil }
    
    var hoursWorked: Double {
        let end = clockOutTime ?? Date()
        return end.timeIntervalSince(clockInTime) / 3600.0
    }
    
    var durationString: String {
        let hours = Int(hoursWorked)
        let minutes = Int((hoursWorked - Double(hours)) * 60)
        return String(format: "%dh %02dm", hours, minutes)
    }
}

// MARK: - Daily Tips
@Model
final class DailyTips {
    var id: UUID
    var date: Date
    var totalAmount: Double
    var isPaid: Bool
    var paidDate: Date?
    var notes: String?
    
    init(date: Date, totalAmount: Double) {
        self.id = UUID()
        self.date = Calendar.current.startOfDay(for: date)
        self.totalAmount = totalAmount
        self.isPaid = false
    }
    
    func markAsPaid() {
        isPaid = true
        paidDate = Date()
    }
}

// MARK: - App Settings
@Model
final class AppSettings {
    var id: UUID
    var allowEmployeeInventoryEdit: Bool
    
    init() {
        self.id = UUID()
        self.allowEmployeeInventoryEdit = false
    }
}

// MARK: - Checklist Models
@Model
final class ChecklistTemplate {
    var id: UUID
    var title: String
    @Relationship(deleteRule: .cascade) var tasks: [ChecklistTask] = []
    
    init(title: String) {
        self.id = UUID()
        self.title = title
    }
    
    var completionPercentage: Double {
        guard !tasks.isEmpty else { return 0 }
        let completed = tasks.filter { $0.isCompleted }.count
        return (Double(completed) / Double(tasks.count)) * 100
    }
    
    func resetAllTasks() {
        for task in tasks {
            task.isCompleted = false
            task.completedBy = nil
            task.completedAt = nil
        }
    }
}

@Model
final class ChecklistTask {
    var id: UUID
    var title: String
    var isCompleted: Bool
    var sortOrder: Int
    var template: ChecklistTemplate?
    var completedBy: String?
    var completedAt: Date?
    
    init(title: String, sortOrder: Int) {
        self.id = UUID()
        self.title = title
        self.sortOrder = sortOrder
        self.isCompleted = false
    }
    
    func markComplete(by employeeName: String) {
        isCompleted = true
        completedBy = employeeName
        completedAt = Date()
    }
}

// MARK: - Payroll Period
@Model
final class PayrollPeriod {
    var id: UUID
    var startDate: Date
    var endDate: Date
    var isPaid: Bool
    var includeTips: Bool
    var notes: String?
    var paidDate: Date?

    init(startDate: Date = Date(), endDate: Date = Date().addingTimeInterval(1209600), includeTips: Bool = true) {
        self.id = UUID()
        self.startDate = startDate
        self.endDate = endDate
        self.isPaid = false
        self.includeTips = includeTips
    }
}
