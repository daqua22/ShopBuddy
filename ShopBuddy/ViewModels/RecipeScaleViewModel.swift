import Foundation
import Observation

@Observable
final class RecipeScaleViewModel {
    let ingredients: [RecipeIngredient]

    var multiplier: Decimal
    var anchorIngredientID: UUID?
    var editedAmounts: [UUID: String]
    var ingredientErrors: [UUID: String]

    init(ingredients: [RecipeIngredient], multiplier: Decimal = 1.0) {
        self.ingredients = ingredients.sorted { $0.sortOrder < $1.sortOrder }
        self.multiplier = multiplier > 0 ? multiplier : 1.0
        self.anchorIngredientID = nil
        self.editedAmounts = [:]
        self.ingredientErrors = [:]
    }

    func displayedAmount(for ingredient: RecipeIngredient) -> Decimal {
        ingredient.baseAmount * multiplier
    }

    func displayedText(for ingredient: RecipeIngredient) -> String {
        if let edited = editedAmounts[ingredient.id] {
            return edited
        }
        return formatDecimalForUI(displayedAmount(for: ingredient))
    }

    func errorMessage(for ingredient: RecipeIngredient) -> String? {
        ingredientErrors[ingredient.id]
    }

    func anchorIngredientName() -> String? {
        guard let anchorIngredientID,
              let ingredient = ingredient(with: anchorIngredientID) else {
            return nil
        }
        return ingredient.displayName
    }

    func setAnchorAmount(
        ingredientID: UUID,
        newText: String,
        editedDisplayUnit: UnitType? = nil
    ) {
        editedAmounts[ingredientID] = newText
        ingredientErrors[ingredientID] = nil

        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            ingredientErrors[ingredientID] = "Enter an amount"
            return
        }

        guard let ingredient = ingredient(with: ingredientID) else {
            return
        }

        guard ingredient.baseAmount > 0 else {
            ingredientErrors[ingredientID] = "Base amount is 0"
            return
        }

        guard let parsedAmount = parseDecimal(trimmed) else {
            ingredientErrors[ingredientID] = "Invalid number"
            return
        }

        guard parsedAmount > 0 else {
            ingredientErrors[ingredientID] = "Amount must be greater than 0"
            return
        }

        let sourceUnit = editedDisplayUnit ?? ingredient.unit
        let amountInIngredientUnit: Decimal

        if sourceUnit == ingredient.unit {
            amountInIngredientUnit = parsedAmount
        } else {
            guard let converted = convert(amount: parsedAmount, from: sourceUnit, to: ingredient.unit) else {
                ingredientErrors[ingredientID] = "Unit mismatch"
                return
            }
            amountInIngredientUnit = converted
        }

        let newMultiplier = amountInIngredientUnit / ingredient.baseAmount
        guard newMultiplier > 0 else {
            ingredientErrors[ingredientID] = "Amount must be greater than 0"
            return
        }

        multiplier = newMultiplier
        anchorIngredientID = ingredientID

        ingredientErrors.removeAll()
        synchronizeEditedAmounts(excluding: ingredientID)
    }

    func setMultiplierManually(_ newValue: Decimal) {
        guard newValue > 0 else { return }
        multiplier = newValue
        anchorIngredientID = nil
        ingredientErrors.removeAll()
        synchronizeEditedAmounts(excluding: nil)
    }

    func restoreToTemplate() {
        multiplier = 1.0
        anchorIngredientID = nil
        ingredientErrors.removeAll()
        editedAmounts.removeAll()
    }

    private func ingredient(with id: UUID) -> RecipeIngredient? {
        ingredients.first { $0.id == id }
    }

    private func synchronizeEditedAmounts(excluding ingredientID: UUID?) {
        for ingredient in ingredients {
            if ingredient.id == ingredientID {
                continue
            }
            editedAmounts[ingredient.id] = formatDecimalForUI(displayedAmount(for: ingredient))
        }
    }
}
