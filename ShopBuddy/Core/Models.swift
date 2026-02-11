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
    var birthday: Date?
    var createdAt: Date
    var isActive: Bool
    
    @Relationship(deleteRule: .cascade, inverse: \Shift.employee)
    var shifts: [Shift]
    
    var role: EmployeeRole {
        get { EmployeeRole(rawValue: roleRaw) ?? .employee }
        set { roleRaw = newValue.rawValue }
    }
    
    init(name: String, pin: String, role: EmployeeRole, hourlyWage: Double? = nil, birthday: Date? = nil) {
        self.id = UUID()
        self.name = name
        self.pin = pin
        self.roleRaw = role.rawValue
        self.hourlyWage = hourlyWage
        self.birthday = birthday
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

    /// Centralized PIN write path so auth storage can be upgraded later.
    func setPIN(_ newPIN: String) {
        pin = newPIN
    }

    /// Centralized PIN compare path so auth logic stays decoupled from raw storage.
    func matchesPIN(_ candidatePIN: String) -> Bool {
        pin == candidatePIN
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
    var sortOrder: Int
    
    init(name: String, stockLevel: Double, parLevel: Double, unitType: String, amountOnHand: Double = 0, vendor: String? = nil, notes: String? = nil, sortOrder: Int = 0) {
        self.id = UUID()
        self.name = name
        self.stockLevel = stockLevel
        self.parLevel = parLevel
        self.amountOnHand = amountOnHand
        self.unitType = unitType
        self.vendor = vendor
        self.notes = notes
        self.lastRestocked = Date()
        self.sortOrder = sortOrder
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

    /// Returns the overlap between this shift and a date range in hours.
    func hoursWorked(in range: DateRange) -> Double {
        let shiftEnd = clockOutTime ?? Date()
        let overlapStart = max(clockInTime, range.start)
        let overlapEnd = min(shiftEnd, range.end)
        guard overlapEnd > overlapStart else { return 0 }
        return overlapEnd.timeIntervalSince(overlapStart) / 3600.0
    }
}

// MARK: - Daily Tips
@Model
final class DailyTips {
    var id: UUID
    var date: Date
    var totalAmount: Double
    @Attribute(originalName: "isPaid")
    var isDistributed: Bool
    @Attribute(originalName: "paidDate")
    var distributedDate: Date?
    var notes: String?
    
    init(date: Date, totalAmount: Double) {
        self.id = UUID()
        self.date = Calendar.current.startOfDay(for: date)
        self.totalAmount = totalAmount
        self.isDistributed = false
    }
    
    func markDistributed() {
        isDistributed = true
        distributedDate = Date()
    }
}

// MARK: - App Settings
@Model
final class AppSettings {
    var id: UUID
    var allowEmployeeInventoryEdit: Bool
    var requireClockInForChecklists: Bool = false
    var enableDragAndDrop: Bool = true
    var operatingDaysRaw: String = "[2,3,4,5,6]"
    var openTime: Date = {
        Calendar.current.date(from: DateComponents(hour: 9, minute: 0)) ?? Date()
    }()
    var closeTime: Date = {
        Calendar.current.date(from: DateComponents(hour: 17, minute: 0)) ?? Date()
    }()

    init() {
        self.id = UUID()
        self.allowEmployeeInventoryEdit = false
        self.requireClockInForChecklists = false
        self.enableDragAndDrop = true
        // Default Mon–Fri
        self.operatingDaysRaw = "[2,3,4,5,6]"
        // Default 9:00 AM
        let cal = Calendar.current
        self.openTime = cal.date(from: DateComponents(hour: 9, minute: 0)) ?? Date()
        self.closeTime = cal.date(from: DateComponents(hour: 17, minute: 0)) ?? Date()
    }

    var operatingDays: Set<Int> {
        get {
            guard let data = operatingDaysRaw.data(using: .utf8),
                  let arr = try? JSONDecoder().decode([Int].self, from: data) else { return [2,3,4,5,6] }
            return Set(arr)
        }
        set {
            if let data = try? JSONEncoder().encode(Array(newValue).sorted()),
               let str = String(data: data, encoding: .utf8) {
                operatingDaysRaw = str
            }
        }
    }

    /// Returns the next operating day from the given date.
    func nextOperatingDay(after date: Date = Date()) -> Date {
        let cal = Calendar.current
        let days = operatingDays
        guard !days.isEmpty else {
            // Fallback: tomorrow
            return cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: date)) ?? date
        }
        var candidate = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: date)) ?? date
        // Search up to 7 days
        for _ in 0..<7 {
            let weekday = cal.component(.weekday, from: candidate)
            if days.contains(weekday) { return candidate }
            candidate = cal.date(byAdding: .day, value: 1, to: candidate) ?? candidate
        }
        return candidate
    }

    static let weekdaySymbols: [(index: Int, short: String, full: String)] = {
        let formatter = DateFormatter()
        return (1...7).map { i in
            (index: i, short: formatter.shortWeekdaySymbols[i - 1], full: formatter.weekdaySymbols[i - 1])
        }
    }()
}

// MARK: - Daily Task (Whiteboard)
@Model
final class DailyTask {
    var id: UUID
    var title: String
    var isCompleted: Bool
    var targetDate: Date
    var createdAt: Date
    var completedBy: String?
    var completedAt: Date?
    var sortOrder: Int

    init(title: String, targetDate: Date, sortOrder: Int = 0) {
        self.id = UUID()
        self.title = title
        self.isCompleted = false
        self.targetDate = Calendar.current.startOfDay(for: targetDate)
        self.createdAt = Date()
        self.sortOrder = sortOrder
    }

    func markComplete(by employeeName: String) {
        isCompleted = true
        completedBy = employeeName
        completedAt = Date()
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

// MARK: - Pay Period (Preview)
@Model
final class PayPeriod {
    var id: UUID
    var startDate: Date
    var endDate: Date
    @Attribute(originalName: "isPaid")
    var isReviewed: Bool
    var includeTips: Bool
    var notes: String?
    @Attribute(originalName: "paidDate")
    var reviewedDate: Date?

    init(startDate: Date = Date(), endDate: Date = Date().addingTimeInterval(1209600), includeTips: Bool = true) {
        self.id = UUID()
        self.startDate = startDate
        self.endDate = endDate
        self.isReviewed = false
        self.includeTips = includeTips
    }
}
