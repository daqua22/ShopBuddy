import Foundation
import SwiftData
import SwiftUI

import Observation

@Observable
class RecipeViewModel {
    private var modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Scaling & Calculations

    /// Returns the scaled amount for an ingredient based on the multiplier.
    func scaledAmount(for ingredient: RecipeIngredient, multiplier: Decimal) -> Decimal {
        return ingredient.baseAmount * multiplier
    }

    /// specific helper to format decimal amount for UI
    func formattedAmount(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        
        let number = NSDecimalNumber(decimal: amount)
        return formatter.string(from: number) ?? "\(amount)"
    }

    // MARK: - Batch Logic

    /// Result type for batch operations
    struct BatchResult {
        let success: Bool
        let error: String?
        let batch: RecipeBatch?
    }

    /// Creates a batch and optionally deducts inventory.
    /// Returns a result indicating success or failure (e.g. insufficient stock).
    func makeBatch(
        recipe: RecipeTemplate,
        multiplier: Decimal,
        employee: Employee?,
        deductInventory: Bool,
        notes: String?
    ) -> BatchResult {
        
        // 1. Validate Stock if deduction is requested
        if deductInventory {
            if let error = checkStockAvailability(recipe: recipe, multiplier: multiplier) {
                return BatchResult(success: false, error: error, batch: nil)
            }
        }

        // 2. Create Batch Record
        let batch = RecipeBatch(template: recipe, multiplier: multiplier, employee: employee)
        if let notes = notes, !notes.isEmpty {
            batch.notes = notes
        }
        batch.didDeductInventory = deductInventory
        modelContext.insert(batch)

        // 3. Perform atomic deduction
        if deductInventory {
            do {
                try performDeductions(for: batch, recipe: recipe, multiplier: multiplier)
            } catch {
                // If checking passed but deduction fails (e.g. unexpected error), rollback.
                modelContext.delete(batch)
                return BatchResult(success: false, error: "Failed to deduct inventory.", batch: nil)
            }
        }

        // 4. Save
        do {
            try modelContext.save()
            return BatchResult(success: true, error: nil, batch: batch)
        } catch {
            return BatchResult(success: false, error: "Failed to save: \(error.localizedDescription)", batch: nil)
        }
    }

    // MARK: - Filtering

    /// Filters recipes based on search text, allergens, and restrictions.
    func filterRecipes(
        _ recipes: [RecipeTemplate],
        searchText: String,
        category: PrepCategory?,
        allergens: Set<String>,
        restrictions: Set<String>
    ) -> [RecipeTemplate] {
        var result = recipes
        
        // Category Filter (if not handled by Query)
        if let category = category {
            result = result.filter { $0.category?.id == category.id }
        }
        
        // Search Filter
        if !searchText.isEmpty {
            result = result.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
        }
        
        // Allergen Filter (Exclude recipes containing ANY of the selected allergens)
        if !allergens.isEmpty {
            result = result.filter { recipe in
                return recipe.allergens.isDisjoint(with: allergens)
            }
        }
        
        // Restriction Filter (Include ONLY recipes that have ALL selected restrictions)
        if !restrictions.isEmpty {
            result = result.filter { recipe in
                return restrictions.isSubset(of: recipe.restrictions)
            }
        }
        
        return result
    }

    // MARK: - Private Helpers

    private func checkStockAvailability(recipe: RecipeTemplate, multiplier: Decimal) -> String? {
        for ingredient in recipe.ingredients {
            guard let item = ingredient.inventoryItem else { continue }
            
            // Needed amount in ingredient's unit
            let neededAmount = ingredient.baseAmount * multiplier
            
            // Check unit compatibility with item's BASE unit
            guard let itemBaseUnit = UnitType(rawValue: item.baseUnit) else {
                return "Unknown base unit for inventory item: \(item.name)"
            }
            
            // Convert needed amount to inventory item's base unit
            guard let convertedNeed = ingredient.unit.convert(neededAmount, to: itemBaseUnit) else {
                return "Cannot convert \(ingredient.unit.rawValue) to \(itemBaseUnit.rawValue) for \(item.name)"
            }
            
            // Check if enough stock
            if item.amountOnHand < convertedNeed {
                let missing = convertedNeed - item.amountOnHand
                return "Insufficient stock for \(item.name). Short by \(formattedAmount(missing)) \(itemBaseUnit.rawValue)."
            }
        }
        return nil
    }

    private func performDeductions(for batch: RecipeBatch, recipe: RecipeTemplate, multiplier: Decimal) throws {
        for ingredient in recipe.ingredients {
            guard let item = ingredient.inventoryItem else { continue }
            
            let neededAmount = ingredient.baseAmount * multiplier
            
            // We already validated unit compatibility in checkStockAvailability
            guard let itemBaseUnit = UnitType(rawValue: item.baseUnit),
                  let convertedAmount = ingredient.unit.convert(neededAmount, to: itemBaseUnit) else {
                continue 
            }
            
            // Deduct
            item.amountOnHand -= convertedAmount
            // Also update stockLevel as it tracks logical stock (ensure stockLevel is also considered in base units or handled separately)
            // For now, assuming stockLevel is also in baseUnit as per new model definition.
            item.stockLevel -= convertedAmount
            
            // Create Audit Record
            let deduction = InventoryDeduction(amount: convertedAmount, unit: itemBaseUnit, item: item)
            deduction.batch = batch
            modelContext.insert(deduction)
        }
    }
}
