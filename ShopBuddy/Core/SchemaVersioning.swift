import Foundation
import SwiftData

// MARK: - Schema V1 (Original)
// Snapshot of models BEFORE the payroll audit + drag-and-drop changes.
enum SchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Employee.self,
            Shift.self,
            InventoryCategory.self,
            InventoryLocation.self,
            InventoryItem.self,
            ChecklistTemplate.self,
            ChecklistTask.self,
            DailyTips.self,
            DailyTask.self,
            PayrollPeriod.self,
            AppSettings.self
        ]
    }

    @Model
    final class InventoryCategory {
        var id: UUID
        var name: String
        var emoji: String
        @Relationship(deleteRule: .cascade) var locations: [InventoryLocation] = []
        
        init(name: String, emoji: String = "📦") {
            self.id = UUID()
            self.name = name
            self.emoji = emoji
        }
    }

    @Model
    final class InventoryLocation {
        var id: UUID
        var name: String
        var emoji: String
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
        var amountOnHand: Double
        var unitType: String
        var vendor: String?
        var notes: String?
        var lastRestocked: Date?
        var location: InventoryLocation?
        
        init(name: String, stockLevel: Double, parLevel: Double, unitType: String) {
            self.id = UUID()
            self.name = name
            self.stockLevel = stockLevel
            self.parLevel = parLevel
            self.amountOnHand = 0
            self.unitType = unitType
        }
    }

    @Model
    final class DailyTips {
        var id: UUID
        var date: Date
        var totalAmount: Double
        var isPaid: Bool           // V1: "isPaid"
        var paidDate: Date?        // V1: "paidDate"

        init(date: Date, totalAmount: Double) {
            self.id = UUID()
            self.date = date
            self.totalAmount = totalAmount
            self.isPaid = false
        }
    }

    @Model
    final class PayrollPeriod {
        var id: UUID
        var startDate: Date
        var endDate: Date
        var isPaid: Bool           // V1: "isPaid"
        var includeTips: Bool
        var notes: String?
        var paidDate: Date?        // V1: "paidDate"

        init(startDate: Date, endDate: Date) {
            self.id = UUID()
            self.startDate = startDate
            self.endDate = endDate
            self.isPaid = false
            self.includeTips = true
        }
    }

    @Model
    final class AppSettings {
        var id: UUID
        var allowEmployeeInventoryEdit: Bool
        var requireClockInForChecklists: Bool
        var operatingDaysRaw: String
        var openTime: Date
        var closeTime: Date

        init() {
            self.id = UUID()
            self.allowEmployeeInventoryEdit = false
            self.requireClockInForChecklists = false
            self.operatingDaysRaw = "[2,3,4,5,6]"
            let cal = Calendar.current
            self.openTime = cal.date(from: DateComponents(hour: 9, minute: 0)) ?? Date()
            self.closeTime = cal.date(from: DateComponents(hour: 17, minute: 0)) ?? Date()
        }
    }
}

// MARK: - Schema V2 (Current)
// After payroll audit (renames) + drag-and-drop (new fields) + pricePerUnit.
enum SchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Employee.self,
            Shift.self,
            InventoryCategory.self,
            InventoryLocation.self,
            InventoryItem.self,
            ChecklistTemplate.self,
            ChecklistTask.self,
            DailyTips.self,
            DailyTask.self,
            PayPeriod.self,
            AppSettings.self,
            
            // Recipes
            PrepCategory.self,
            RecipeTemplate.self,
            RecipeIngredient.self,
            RecipeStep.self,
            RecipeBatch.self,
            InventoryDeduction.self
        ]
    }
}

// MARK: - Schema V3 (Scheduling + Availability)
enum SchemaV3: VersionedSchema {
    static var versionIdentifier = Schema.Version(3, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Employee.self,
            Shift.self,
            InventoryCategory.self,
            InventoryLocation.self,
            InventoryItem.self,
            ChecklistTemplate.self,
            ChecklistTask.self,
            DailyTips.self,
            DailyTask.self,
            PayPeriod.self,
            AppSettings.self,

            PrepCategory.self,
            RecipeTemplate.self,
            RecipeIngredient.self,
            RecipeStep.self,
            RecipeBatch.self,
            InventoryDeduction.self,

            CoverageRequirement.self,
            EmployeeAvailabilityWindow.self,
            EmployeeAvailabilityOverride.self,
            EmployeeUnavailableDate.self,
            PlannedShift.self
        ]
    }
}

enum PrepItMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self, SchemaV3.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self),
            .lightweight(fromVersion: SchemaV2.self, toVersion: SchemaV3.self)
        ]
    }
}
