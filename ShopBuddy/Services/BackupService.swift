import Foundation
import SwiftData
import SwiftUI

// MARK: - Backup Data Schema
struct BackupData: Codable {
    let metadata: BackupMetadata
    // Inventory
    let categories: [InventoryCategoryCodable]
    let locations: [InventoryLocationCodable]
    let items: [InventoryItemCodable]
    // Checklists
    let checklistTemplates: [ChecklistTemplateCodable]
    let checklistTasks: [ChecklistTaskCodable]
    // Operations
    let employees: [EmployeeCodable]
    let shifts: [ShiftCodable]
    let payPeriods: [PayPeriodCodable]
    let dailyTasks: [DailyTaskCodable]
    let dailyTips: [DailyTipsCodable]
    // Settings
    let settings: [AppSettingsCodable]
}

struct BackupMetadata: Codable {
    let version: String
    let exportDate: Date
    let schemaVersion: Int
}

// MARK: - Codable Mirrors of SwiftData Models
// We use separate structs to ensure stable serialization even if internal models change slightly,
// and to break circular references during encoding (though ID referencing handles that).

struct InventoryCategoryCodable: Codable {
    let id: UUID
    let name: String
    let emoji: String
}

struct InventoryLocationCodable: Codable {
    let id: UUID
    let name: String
    let emoji: String
    let categoryID: UUID?
}

struct InventoryItemCodable: Codable {
    let id: UUID
    let name: String
    let stockLevel: Decimal
    let parLevel: Decimal
    let amountOnHand: Decimal
    let unitType: String
    let vendor: String?
    let pricePerUnit: Decimal?
    let notes: String?
    let lastRestocked: Date?
    let locationID: UUID?
    let sortOrder: Int
}

struct ChecklistTemplateCodable: Codable {
    let id: UUID
    let title: String
}

struct ChecklistTaskCodable: Codable {
    let id: UUID
    let title: String
    let isCompleted: Bool
    let sortOrder: Int
    let templateID: UUID?
    let completedBy: String?
    let completedAt: Date?
}

struct EmployeeCodable: Codable {
    let id: UUID
    let name: String
    let pin: String
    let roleRaw: String
    let hourlyWage: Double?
    let birthday: Date?
    let createdAt: Date
    let isActive: Bool
}

struct ShiftCodable: Codable {
    let id: UUID
    let employeeID: UUID?
    let clockInTime: Date
    let clockOutTime: Date?
    let includeTips: Bool
}

struct PayPeriodCodable: Codable {
    let id: UUID
    let startDate: Date
    let endDate: Date
    let isReviewed: Bool
    let includeTips: Bool
    let notes: String?
    let reviewedDate: Date?
}

struct DailyTaskCodable: Codable {
    let id: UUID
    let title: String
    let isCompleted: Bool
    let targetDate: Date
    let completedBy: String?
    let completedAt: Date?
    let sortOrder: Int
}

struct DailyTipsCodable: Codable {
    let id: UUID
    let date: Date
    let totalAmount: Double
    let isDistributed: Bool
    let distributedDate: Date?
}

struct AppSettingsCodable: Codable {
    let id: UUID
    let allowEmployeeInventoryEdit: Bool
    let requireClockInForChecklists: Bool
    let enableDragAndDrop: Bool
    let operatingDaysRaw: String
    let openTime: Date
    let closeTime: Date
}

// MARK: - Backup Service
@MainActor
final class BackupService {
    let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: Export
    func exportData() throws -> Data {
        let metadata = BackupMetadata(
            version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            exportDate: Date(),
            schemaVersion: 2
        )
        
        // Fetch All Data
        let categories = try modelContext.fetch(FetchDescriptor<InventoryCategory>())
        let locations = try modelContext.fetch(FetchDescriptor<InventoryLocation>())
        let items = try modelContext.fetch(FetchDescriptor<InventoryItem>())
        
        let templates = try modelContext.fetch(FetchDescriptor<ChecklistTemplate>())
        let tasks = try modelContext.fetch(FetchDescriptor<ChecklistTask>())
        
        let employees = try modelContext.fetch(FetchDescriptor<Employee>())
        let shifts = try modelContext.fetch(FetchDescriptor<Shift>())
        let payPeriods = try modelContext.fetch(FetchDescriptor<PayPeriod>())
        
        let dailyTasks = try modelContext.fetch(FetchDescriptor<DailyTask>())
        let dailyTips = try modelContext.fetch(FetchDescriptor<DailyTips>())
        
        let settings = try modelContext.fetch(FetchDescriptor<AppSettings>())
        
        // Map to Codable
        let backup = BackupData(
            metadata: metadata,
            categories: categories.map { InventoryCategoryCodable(id: $0.id, name: $0.name, emoji: $0.emoji) },
            locations: locations.map { InventoryLocationCodable(id: $0.id, name: $0.name, emoji: $0.emoji, categoryID: $0.category?.id) },
            items: items.map { InventoryItemCodable(id: $0.id, name: $0.name, stockLevel: $0.stockLevel, parLevel: $0.parLevel, amountOnHand: $0.amountOnHand, unitType: $0.unitType, vendor: $0.vendor, pricePerUnit: $0.pricePerUnit, notes: $0.notes, lastRestocked: $0.lastRestocked, locationID: $0.location?.id, sortOrder: $0.sortOrder) },
            checklistTemplates: templates.map { ChecklistTemplateCodable(id: $0.id, title: $0.title) },
            checklistTasks: tasks.map { ChecklistTaskCodable(id: $0.id, title: $0.title, isCompleted: $0.isCompleted, sortOrder: $0.sortOrder, templateID: $0.template?.id, completedBy: $0.completedBy, completedAt: $0.completedAt) },
            employees: employees.map { EmployeeCodable(id: $0.id, name: $0.name, pin: $0.pin, roleRaw: $0.roleRaw, hourlyWage: $0.hourlyWage, birthday: $0.birthday, createdAt: $0.createdAt, isActive: $0.isActive) },
            shifts: shifts.map { ShiftCodable(id: $0.id, employeeID: $0.employee?.id, clockInTime: $0.clockInTime, clockOutTime: $0.clockOutTime, includeTips: $0.includeTips) },
            payPeriods: payPeriods.map { PayPeriodCodable(id: $0.id, startDate: $0.startDate, endDate: $0.endDate, isReviewed: $0.isReviewed, includeTips: $0.includeTips, notes: $0.notes, reviewedDate: $0.reviewedDate) },
            dailyTasks: dailyTasks.map { DailyTaskCodable(id: $0.id, title: $0.title, isCompleted: $0.isCompleted, targetDate: $0.targetDate, completedBy: $0.completedBy, completedAt: $0.completedAt, sortOrder: $0.sortOrder) },
            dailyTips: dailyTips.map { DailyTipsCodable(id: $0.id, date: $0.date, totalAmount: $0.totalAmount, isDistributed: $0.isDistributed, distributedDate: $0.distributedDate) },
            settings: settings.map { AppSettingsCodable(id: $0.id, allowEmployeeInventoryEdit: $0.allowEmployeeInventoryEdit, requireClockInForChecklists: $0.requireClockInForChecklists, enableDragAndDrop: $0.enableDragAndDrop, operatingDaysRaw: $0.operatingDaysRaw, openTime: $0.openTime, closeTime: $0.closeTime) }
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        return try encoder.encode(backup)
    }
    
    // MARK: Restore
    func restoreData(from json: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(BackupData.self, from: json)
        
        // 1. Clear existing data
        try clearAllData()
        
        // 2. Insert new data (Lookup dictionaries for relationships)
        
        // --- Inventory ---
        var categoryMap: [UUID: InventoryCategory] = [:]
        for c in backup.categories {
            let category = InventoryCategory(name: c.name, emoji: c.emoji)
            category.id = c.id
            modelContext.insert(category)
            categoryMap[c.id] = category
        }
        
        var locationMap: [UUID: InventoryLocation] = [:]
        for l in backup.locations {
            let location = InventoryLocation(name: l.name, emoji: l.emoji)
            location.id = l.id
            if let catID = l.categoryID, let cat = categoryMap[catID] {
                location.category = cat
            }
            modelContext.insert(location)
            locationMap[l.id] = location
        }
        
        for i in backup.items {
            let item = InventoryItem(name: i.name, stockLevel: i.stockLevel, parLevel: i.parLevel, unitType: i.unitType, amountOnHand: i.amountOnHand, vendor: i.vendor, pricePerUnit: i.pricePerUnit, notes: i.notes, sortOrder: i.sortOrder)
            item.id = i.id
            item.lastRestocked = i.lastRestocked
            if let locID = i.locationID, let loc = locationMap[locID] {
                item.location = loc
            }
            modelContext.insert(item)
        }
        
        // --- Checklists ---
        var templateMap: [UUID: ChecklistTemplate] = [:]
        for t in backup.checklistTemplates {
            let template = ChecklistTemplate(title: t.title)
            template.id = t.id
            modelContext.insert(template)
            templateMap[t.id] = template
        }
        
        for t in backup.checklistTasks {
            let task = ChecklistTask(title: t.title, sortOrder: t.sortOrder)
            task.id = t.id
            task.isCompleted = t.isCompleted
            task.completedBy = t.completedBy
            task.completedAt = t.completedAt
            if let tmplID = t.templateID, let tmpl = templateMap[tmplID] {
                task.template = tmpl
            }
            modelContext.insert(task)
        }
        
        // --- Operations ---
        var employeeMap: [UUID: Employee] = [:]
        for e in backup.employees {
            // Reconstruct logic for role enum
            let role = EmployeeRole(rawValue: e.roleRaw) ?? .employee
            let employee = Employee(name: e.name, pin: e.pin, role: role, hourlyWage: e.hourlyWage, birthday: e.birthday)
            employee.id = e.id
            employee.createdAt = e.createdAt
            employee.isActive = e.isActive
            modelContext.insert(employee)
            employeeMap[e.id] = employee
        }
        
        for s in backup.shifts {
            guard let empID = s.employeeID, let emp = employeeMap[empID] else { continue }
            let shift = Shift(employee: emp)
            shift.id = s.id
            shift.clockInTime = s.clockInTime
            shift.clockOutTime = s.clockOutTime
            shift.includeTips = s.includeTips
            modelContext.insert(shift)
        }
        
        for p in backup.payPeriods {
            let period = PayPeriod(startDate: p.startDate, endDate: p.endDate, includeTips: p.includeTips)
            period.id = p.id
            period.isReviewed = p.isReviewed
            period.notes = p.notes
            period.reviewedDate = p.reviewedDate
            modelContext.insert(period)
        }
        
        for t in backup.dailyTasks {
            let task = DailyTask(title: t.title, targetDate: t.targetDate, sortOrder: t.sortOrder)
            task.id = t.id
            task.isCompleted = t.isCompleted
            task.completedBy = t.completedBy
            task.completedAt = t.completedAt
            modelContext.insert(task)
        }
        
        for t in backup.dailyTips {
            let tip = DailyTips(date: t.date, totalAmount: t.totalAmount)
            tip.id = t.id
            tip.isDistributed = t.isDistributed
            tip.distributedDate = t.distributedDate
            modelContext.insert(tip)
        }
        
        // --- Settings ---
        for s in backup.settings {
            let setting = AppSettings()
            setting.id = s.id
            setting.allowEmployeeInventoryEdit = s.allowEmployeeInventoryEdit
            setting.requireClockInForChecklists = s.requireClockInForChecklists
            setting.enableDragAndDrop = s.enableDragAndDrop
            setting.operatingDaysRaw = s.operatingDaysRaw
            setting.openTime = s.openTime
            setting.closeTime = s.closeTime
            modelContext.insert(setting)
        }
        
        try modelContext.save()
    }
    
    private func clearAllData() throws {
        try modelContext.fetch(FetchDescriptor<InventoryItem>()).forEach { modelContext.delete($0) }
        try modelContext.fetch(FetchDescriptor<InventoryLocation>()).forEach { modelContext.delete($0) }
        try modelContext.fetch(FetchDescriptor<InventoryCategory>()).forEach { modelContext.delete($0) }
        try modelContext.fetch(FetchDescriptor<ChecklistTask>()).forEach { modelContext.delete($0) }
        try modelContext.fetch(FetchDescriptor<ChecklistTemplate>()).forEach { modelContext.delete($0) }
        try modelContext.fetch(FetchDescriptor<DailyTask>()).forEach { modelContext.delete($0) }
        try modelContext.fetch(FetchDescriptor<DailyTips>()).forEach { modelContext.delete($0) }
        try modelContext.fetch(FetchDescriptor<PayPeriod>()).forEach { modelContext.delete($0) }
        try modelContext.fetch(FetchDescriptor<Shift>()).forEach { modelContext.delete($0) }
        try modelContext.fetch(FetchDescriptor<Employee>()).forEach { modelContext.delete($0) }
        try modelContext.fetch(FetchDescriptor<AppSettings>()).forEach { modelContext.delete($0) }
        try modelContext.save()
    }
}
