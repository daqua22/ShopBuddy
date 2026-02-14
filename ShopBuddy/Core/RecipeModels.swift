import Foundation
import SwiftData

// MARK: - Prep Category
@Model
final class PrepCategory {
    var id: UUID
    var name: String
    var emoji: String
    var sortOrder: Int
    var isArchived: Bool
    @Relationship(deleteRule: .nullify) var recipes: [RecipeTemplate] = []
    
    init(name: String, emoji: String = "🥣", sortOrder: Int = 0) {
        self.id = UUID()
        self.name = name
        self.emoji = emoji
        self.sortOrder = sortOrder
        self.isArchived = false
    }
}

// MARK: - Recipe Template
@Model
final class RecipeTemplate {
    var id: UUID
    var title: String
    var notes: String?
    var category: PrepCategory?
    
    // Photo support (storing as Data for simplicity in this phase, URL support can be added if needed)
    @Attribute(.externalStorage) var photoData: Data?
    
    @Attribute(originalName: "defaultYieldAmount")
    var baseYieldAmount: Decimal
    @Attribute(originalName: "defaultYieldUnit")
    private var storedBaseYieldUnit: UnitType?
    
    var tagsRaw: String = "" // "vegan,gluten-free"
    var allergensRaw: String = "" // "dairy,peanuts"
    var restrictionsRaw: String = "" // "vegan,halal"
    
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date
    
    @Relationship(deleteRule: .cascade) var ingredients: [RecipeIngredient] = []
    @Relationship(deleteRule: .cascade) var steps: [RecipeStep] = []
    @Relationship(deleteRule: .cascade) var batches: [RecipeBatch] = []
    
    init(title: String, 
         category: PrepCategory? = nil, 
         yieldAmount: Decimal = 1.0, 
         yieldUnit: UnitType = .unit) {
        self.id = UUID()
        self.title = title
        self.category = category
        self.baseYieldAmount = yieldAmount
        self.storedBaseYieldUnit = yieldUnit
        self.isArchived = false
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    var tags: [String] {
        get { tagsRaw.split(separator: ",").map { String($0) } }
        set { tagsRaw = newValue.joined(separator: ",") }
    }
    
    var allergens: [String] {
        get {
            allergensRaw
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        set {
            allergensRaw = normalizedCSV(from: newValue)
        }
    }
    
    var restrictions: [String] {
        get {
            restrictionsRaw
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        set {
            restrictionsRaw = normalizedCSV(from: newValue)
        }
    }

    var allergensSet: Set<String> {
        Set(allergens)
    }

    var restrictionsSet: Set<String> {
        Set(restrictions)
    }

    var defaultYieldAmount: Decimal {
        get { baseYieldAmount }
        set { baseYieldAmount = newValue }
    }

    var defaultYieldUnit: UnitType {
        get { baseYieldUnit }
        set { baseYieldUnit = newValue }
    }

    var baseYieldUnit: UnitType {
        get { storedBaseYieldUnit ?? .unit }
        set { storedBaseYieldUnit = newValue }
    }

    private func normalizedCSV(from values: [String]) -> String {
        let unique = Set(values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        return unique.sorted().joined(separator: ",")
    }
}

// MARK: - Constants
struct RecipeConstants {
    static let allAllergens = [
        "Dairy", "Eggs", "Peanuts", "Tree Nuts", "Soy", "Wheat/Gluten", 
        "Fish", "Shellfish", "Sesame", "Mustard"
    ]
    
    static let allRestrictions = [
        "Vegan", "Vegetarian", "Gluten-Free", "Dairy-Free", "Nut-Free", 
        "Halal", "Kosher", "Pescatarian"
    ]
}

// MARK: - Recipe Ingredient
@Model
final class RecipeIngredient {
    var id: UUID
    var displayName: String // e.g. "Diced Onions"
    var baseAmount: Decimal
    var unit: UnitType
    var sortOrder: Int
    
    // Optional link to inventory for auto-deduction
    var inventoryItem: InventoryItem?
    
    @Relationship(inverse: \RecipeTemplate.ingredients)
    var recipe: RecipeTemplate?
    
    init(displayName: String, amount: Decimal, unit: UnitType, sortOrder: Int = 0) {
        self.id = UUID()
        self.displayName = displayName
        self.baseAmount = amount
        self.unit = unit
        self.sortOrder = sortOrder
    }

    var inventoryItemRef: InventoryItem? {
        get { inventoryItem }
        set { inventoryItem = newValue }
    }
}

// MARK: - Recipe Step
@Model
final class RecipeStep {
    var id: UUID
    var text: String
    var sortOrder: Int
    var timerSeconds: Int? // Optional timer duration
    
    @Relationship(inverse: \RecipeTemplate.steps)
    var recipe: RecipeTemplate?
    
    init(text: String, sortOrder: Int = 0, timerSeconds: Int? = nil) {
        self.id = UUID()
        self.text = text
        self.sortOrder = sortOrder
        self.timerSeconds = timerSeconds
    }
}

// MARK: - Recipe Batch (History)
@Model
final class RecipeBatch {
    var id: UUID
    var madeAt: Date
    var madeByEmployeeName: String? // Snapshot name in case employee deleted
    var scaleMultiplier: Decimal
    
    // Calculated yield based on multiplier
    var finalYieldAmount: Decimal
    var finalYieldUnit: UnitType
    
    var notes: String?
    var didDeductInventory: Bool
    
    @Relationship(inverse: \RecipeTemplate.batches)
    var template: RecipeTemplate?
    
    @Relationship(deleteRule: .cascade) var deductions: [InventoryDeduction] = []
    
    init(template: RecipeTemplate, multiplier: Decimal, employee: Employee? = nil) {
        self.id = UUID()
        self.template = template
        self.madeAt = Date()
        self.madeByEmployeeName = employee?.name
        self.scaleMultiplier = multiplier
        self.finalYieldAmount = template.baseYieldAmount * multiplier
        self.finalYieldUnit = template.baseYieldUnit
        self.didDeductInventory = false
    }
}

// MARK: - Inventory Deduction (Audit)
@Model
final class InventoryDeduction {
    var id: UUID
    var deductedAmount: Decimal
    var unit: UnitType
    var inventoryItemName: String // Snapshot name
    var timestamp: Date
    
    @Relationship(inverse: \RecipeBatch.deductions)
    var batch: RecipeBatch?
    
    // Link back to item if it still exists
    var inventoryItem: InventoryItem?
    
    init(amount: Decimal, unit: UnitType, item: InventoryItem) {
        self.id = UUID()
        self.deductedAmount = amount
        self.unit = unit
        self.inventoryItem = item
        self.inventoryItemName = item.name
        self.timestamp = Date()
    }
}
