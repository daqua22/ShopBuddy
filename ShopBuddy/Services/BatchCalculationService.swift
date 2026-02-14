import Foundation

struct PlannedIngredientDeduction {
    let ingredient: RecipeIngredient
    let inventoryItem: InventoryItem
    let scaledAmount: Decimal
    let requiredInBase: Decimal
    let inventoryBaseUnit: UnitType
}

enum BatchDeductionError: LocalizedError {
    case invalidMultiplier
    case conversionFailed(itemName: String, requiredAmount: Decimal, from: UnitType, to: UnitType)
    case insufficientStock(itemName: String, required: Decimal, available: Decimal, unit: UnitType)
    case persistenceFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidMultiplier:
            return "Batch multiplier must be greater than 0."
        case let .conversionFailed(itemName, requiredAmount, from, to):
            return "Cannot convert \(formatDecimalForUI(requiredAmount)) \(from.displaySymbol) of \(itemName) to inventory unit \(to.displaySymbol)."
        case let .insufficientStock(itemName, required, available, unit):
            return "Insufficient stock: \(itemName) needs \(formatDecimalForUI(required)) \(unit.displaySymbol), available \(formatDecimalForUI(available)) \(unit.displaySymbol)."
        case let .persistenceFailed(message):
            return "Failed to save batch: \(message)"
        }
    }
}

struct BatchCalculationService {
    static func scaledAmount(baseAmount: Decimal, multiplier: Decimal) -> Decimal {
        baseAmount * multiplier
    }

    static func plannedDeductions(for recipe: RecipeTemplate, multiplier: Decimal) throws -> [PlannedIngredientDeduction] {
        guard multiplier > 0 else {
            throw BatchDeductionError.invalidMultiplier
        }

        var planned: [PlannedIngredientDeduction] = []
        var runningRequiredByItem: [UUID: Decimal] = [:]

        for ingredient in recipe.ingredients.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            guard let inventoryItem = ingredient.inventoryItem else {
                continue
            }

            let scaled = scaledAmount(baseAmount: ingredient.baseAmount, multiplier: multiplier)
            guard scaled > 0 else {
                continue
            }

            let inventoryBaseUnit = inventoryItem.baseUnit
            guard let requiredInBase = convert(amount: scaled, from: ingredient.unit, to: inventoryBaseUnit) else {
                throw BatchDeductionError.conversionFailed(
                    itemName: inventoryItem.name,
                    requiredAmount: scaled,
                    from: ingredient.unit,
                    to: inventoryBaseUnit
                )
            }

            let cumulativeNeed = (runningRequiredByItem[inventoryItem.id] ?? 0) + requiredInBase
            let available = inventoryItem.onHandBase
            if available < cumulativeNeed {
                throw BatchDeductionError.insufficientStock(
                    itemName: inventoryItem.name,
                    required: cumulativeNeed,
                    available: available,
                    unit: inventoryBaseUnit
                )
            }
            runningRequiredByItem[inventoryItem.id] = cumulativeNeed

            planned.append(
                PlannedIngredientDeduction(
                    ingredient: ingredient,
                    inventoryItem: inventoryItem,
                    scaledAmount: scaled,
                    requiredInBase: requiredInBase,
                    inventoryBaseUnit: inventoryBaseUnit
                )
            )
        }

        return planned
    }
}
