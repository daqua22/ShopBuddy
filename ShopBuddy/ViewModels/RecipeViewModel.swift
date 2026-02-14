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
        BatchCalculationService.scaledAmount(baseAmount: ingredient.baseAmount, multiplier: multiplier)
    }

    /// specific helper to format decimal amount for UI
    func formattedAmount(_ amount: Decimal) -> String {
        formatDecimalForUI(amount)
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
        do {
            let deductionService = BatchDeductionService(modelContext: modelContext)
            let batch = try deductionService.makeBatch(
                recipe: recipe,
                multiplier: multiplier,
                madeBy: employee,
                deductInventory: deductInventory,
                notes: notes
            )
            return BatchResult(success: true, error: nil, batch: batch)
        } catch {
            return BatchResult(success: false, error: error.localizedDescription, batch: nil)
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
                return recipe.allergensSet.isDisjoint(with: allergens)
            }
        }
        
        // Restriction Filter (Include ONLY recipes that have ALL selected restrictions)
        if !restrictions.isEmpty {
            result = result.filter { recipe in
                return restrictions.isSubset(of: recipe.restrictionsSet)
            }
        }
        
        return result
    }
}
