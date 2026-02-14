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
    @Relationship(deleteRule: .cascade, inverse: \InventoryLocation.category) var locations: [InventoryLocation] = []
    
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
    var stockLevel: Decimal { // Legacy compatibility field; mirrors onHandBase.
        didSet {
            syncQuantities(preferredOnHand: stockLevel)
        }
    }
    var parLevel: Decimal // Stored in baseUnit

    /// Canonical on-hand amount stored in base units.
    @Attribute(originalName: "amountOnHand")
    var onHandBase: Decimal {
        didSet {
            syncQuantities(preferredOnHand: onHandBase)
        }
    }

    var unitType: String // This is now the "Display Unit" (e.g. "Bottles")
    @Attribute(originalName: "baseUnit")
    private var baseUnitRaw: String // Persisted raw value for migration-safe enum storage.
    
    // Packaging Metadata
    @Attribute(originalName: "packSize")
    var packSizeBase: Decimal? // e.g. 483 (grams per bottle)
    @Attribute(originalName: "packUnit")
    private var packUnitRaw: String? // e.g. "g" (must match baseUnit family)
    @Attribute(originalName: "packDisplayName")
    var packName: String? // e.g. "Bottle"
    
    var vendor: String?
    var pricePerUnit: Decimal? // Price per DISPLAY unit
    var notes: String?
    var lastRestocked: Date?
    var location: InventoryLocation?
    var sortOrder: Int
    
    init(name: String, 
         stockLevel: Decimal, 
         parLevel: Decimal, 
         unitType: String,
         baseUnit: UnitType,
         packSizeBase: Decimal? = nil,
         packUnit: UnitType? = nil,
         packName: String? = nil,
         onHandBase: Decimal = 0, 
         vendor: String? = nil, 
         pricePerUnit: Decimal? = nil, 
         notes: String? = nil, 
         sortOrder: Int = 0) {
        self.id = UUID()
        self.name = name
        self.stockLevel = max(0, stockLevel)
        self.parLevel = parLevel
        self.onHandBase = max(0, onHandBase)
        self.unitType = unitType
        self.baseUnitRaw = baseUnit.rawValue
        self.packSizeBase = packSizeBase
        self.packUnitRaw = packUnit?.rawValue
        self.packName = packName
        self.vendor = vendor
        self.pricePerUnit = pricePerUnit
        self.notes = notes
        self.lastRestocked = Date()
        self.sortOrder = sortOrder

        syncQuantities(preferredOnHand: self.onHandBase)
    }

    // Backward-compatible initializer for existing callsites/data import paths.
    convenience init(name: String,
                     stockLevel: Decimal,
                     parLevel: Decimal,
                     unitType: String,
                     baseUnit: UnitType,
                     packSize: Decimal? = nil,
                     packUnit: UnitType? = nil,
                     packDisplayName: String? = nil,
                     amountOnHand: Decimal = 0,
                     vendor: String? = nil,
                     pricePerUnit: Decimal? = nil,
                     notes: String? = nil,
                     sortOrder: Int = 0) {
        self.init(
            name: name,
            stockLevel: stockLevel,
            parLevel: parLevel,
            unitType: unitType,
            baseUnit: baseUnit,
            packSizeBase: packSize,
            packUnit: packUnit,
            packName: packDisplayName,
            onHandBase: amountOnHand,
            vendor: vendor,
            pricePerUnit: pricePerUnit,
            notes: notes,
            sortOrder: sortOrder
        )
    }

    // Backward-compatible initializer for existing callsites/data import paths.
    convenience init(name: String,
                     stockLevel: Decimal,
                     parLevel: Decimal,
                     unitType: String,
                     baseUnit: String,
                     packSize: Decimal? = nil,
                     packUnit: String? = nil,
                     packDisplayName: String? = nil,
                     amountOnHand: Decimal = 0,
                     vendor: String? = nil,
                     pricePerUnit: Decimal? = nil,
                     notes: String? = nil,
                     sortOrder: Int = 0) {
        self.init(
            name: name,
            stockLevel: stockLevel,
            parLevel: parLevel,
            unitType: unitType,
            baseUnit: UnitType(rawValue: baseUnit) ?? .other,
            packSizeBase: packSize,
            packUnit: packUnit.flatMap(UnitType.init(rawValue:)),
            packName: packDisplayName,
            onHandBase: amountOnHand,
            vendor: vendor,
            pricePerUnit: pricePerUnit,
            notes: notes,
            sortOrder: sortOrder
        )
    }

    @Transient
    private var isSyncingQuantities: Bool = false

    var amountOnHand: Decimal {
        get { onHandBase }
        set { syncQuantities(preferredOnHand: newValue) }
    }

    var baseUnit: UnitType {
        get { UnitType(rawValue: baseUnitRaw) ?? .other }
        set { baseUnitRaw = newValue.rawValue }
    }

    var packUnit: UnitType? {
        get { packUnitRaw.flatMap(UnitType.init(rawValue:)) }
        set { packUnitRaw = newValue?.rawValue }
    }

    @available(*, deprecated, message: "Use packName")
    var packDisplayName: String? {
        get { packName }
        set { packName = newValue }
    }

    @available(*, deprecated, message: "Use packSizeBase")
    var packSize: Decimal? {
        get { packSizeBase }
        set { packSizeBase = newValue }
    }

    func syncQuantities(preferredOnHand: Decimal? = nil) {
        guard !isSyncingQuantities else { return }
        isSyncingQuantities = true
        defer { isSyncingQuantities = false }

        let resolvedOnHand = max(0, preferredOnHand ?? onHandBase)
        onHandBase = resolvedOnHand
        stockLevel = resolvedOnHand
    }

    func validatePackagingFamily() -> Bool {
        guard let packUnit else { return true }
        return packUnit.family == baseUnit.family || baseUnit.family == .other
    }
    
    var stockPercentage: Double {
        guard parLevel > 0 else { return 0 }
        return NSDecimalNumber(decimal: min(stockLevel / parLevel, 1.0)).doubleValue
    }
    
    var isBelowPar: Bool {
        stockLevel < parLevel
    }
    
    var totalValue: Decimal {
        (pricePerUnit ?? 0) * stockLevel // Simplification: assuming price is per stored unit for now, or need conversion if price is per pack
    }
}

// MARK: - Unit Types
enum UnitFamily: String, Codable, CaseIterable {
    case mass
    case volume
    case count
    case other
}

enum UnitType: String, CaseIterable, Codable {
    // Mass
    case grams = "g"
    case kilograms = "kg"
    case ounces = "oz"
    case pounds = "lb"
    case poundsLegacy = "lbs" // Backward compatibility for existing data

    // Volume
    case milliliters = "mL"
    case liters = "L"
    case teaspoons = "tsp"
    case tablespoons = "tbsp"
    case cup = "cup"
    case cups = "cups" // Backward compatibility for existing data
    case fluidOunces = "fl oz"
    case gallons = "gal"

    // Count
    case piece = "piece"
    case pieces = "Pieces" // Backward compatibility for existing data
    case unit = "unit"
    case units = "Units" // Backward compatibility for existing data
    case pack = "pack"
    case packs = "Packs" // Backward compatibility for existing data
    case caseCount = "case"
    case cases = "Cases" // Backward compatibility for existing data
    case bottles = "Bottles"
    case cans = "Cans"
    case boxes = "Boxes"
    case bags = "Bags"

    // Other
    case other = "Other"

    var family: UnitFamily {
        switch self {
        case .grams, .kilograms, .ounces, .pounds, .poundsLegacy:
            return .mass
        case .milliliters, .liters, .teaspoons, .tablespoons, .cup, .cups, .fluidOunces, .gallons:
            return .volume
        case .piece, .pieces, .unit, .units, .pack, .packs, .caseCount, .cases, .bottles, .cans, .boxes, .bags:
            return .count
        case .other:
            return .other
        }
    }

    /// Preferred compact label to keep UI display consistent.
    var displaySymbol: String {
        switch self {
        case .poundsLegacy:
            return UnitType.pounds.rawValue
        case .cups:
            return UnitType.cup.rawValue
        case .pieces:
            return UnitType.piece.rawValue
        case .units:
            return UnitType.unit.rawValue
        case .packs:
            return UnitType.pack.rawValue
        case .cases:
            return UnitType.caseCount.rawValue
        default:
            return rawValue
        }
    }

    var isLegacyAlias: Bool {
        switch self {
        case .poundsLegacy, .cups, .pieces, .units, .packs, .cases:
            return true
        default:
            return false
        }
    }

    static var selectableCases: [UnitType] {
        allCases.filter { !$0.isLegacyAlias }
    }

    private static func decimal(_ string: String) -> Decimal {
        Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }

    /// Multiplier to convert this unit into its family base unit.
    /// Base units used for storage/logic: grams (mass), milliliters (volume), unit-count (count).
    private var factorToBase: Decimal? {
        switch self {
        case .grams:
            return 1
        case .kilograms:
            return 1000
        case .ounces:
            return Self.decimal("28.349523125")
        case .pounds, .poundsLegacy:
            return Self.decimal("453.59237")

        case .milliliters:
            return 1
        case .liters:
            return 1000
        case .teaspoons:
            return Self.decimal("4.92892159375")
        case .tablespoons:
            return Self.decimal("14.78676478125")
        case .cup, .cups:
            return Self.decimal("236.5882365")
        case .fluidOunces:
            return Self.decimal("29.5735295625")
        case .gallons:
            return Self.decimal("3785.411784")

        case .piece, .pieces, .unit, .units, .pack, .packs, .caseCount, .cases, .bottles, .cans, .boxes, .bags:
            return 1
        case .other:
            return nil
        }
    }

    /// Attempts to convert an amount from this unit to a target unit.
    /// - Returns: Converted amount, or `nil` if conversion is invalid.
    /// Rules:
    /// - Only same-family conversions are allowed.
    /// - `other` converts only to exact same unit.
    /// - Mass <-> volume conversions are intentionally unsupported in v1 (density not provided).
    func convert(_ amount: Decimal, to target: UnitType) -> Decimal? {
        if self == target { return amount }

        guard family == target.family else {
            return nil
        }

        guard family != .other else {
            return nil
        }

        guard let fromFactor = factorToBase, let toFactor = target.factorToBase, toFactor != 0 else {
            return nil
        }

        let amountInBase = amount * fromFactor
        return amountInBase / toFactor
    }
}

func convert(amount: Decimal, from: UnitType, to: UnitType) -> Decimal? {
    from.convert(amount, to: to)
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
