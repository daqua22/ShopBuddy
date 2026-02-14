import Foundation
import SwiftData

@MainActor
final class BatchDeductionService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func makeBatch(recipe: RecipeTemplate, multiplier: Decimal, madeBy: Employee?) throws -> RecipeBatch {
        try makeBatch(recipe: recipe, multiplier: multiplier, madeBy: madeBy, deductInventory: true, notes: nil)
    }

    func makeBatch(
        recipe: RecipeTemplate,
        multiplier: Decimal,
        madeBy: Employee?,
        deductInventory: Bool,
        notes: String?
    ) throws -> RecipeBatch {
        guard multiplier > 0 else {
            throw BatchDeductionError.invalidMultiplier
        }

        let planned = deductInventory
            ? try BatchCalculationService.plannedDeductions(for: recipe, multiplier: multiplier)
            : []

        let previousOnHand = Dictionary(uniqueKeysWithValues: planned.map { ($0.inventoryItem.id, $0.inventoryItem.onHandBase) })

        let batch = RecipeBatch(template: recipe, multiplier: multiplier, employee: madeBy)
        batch.didDeductInventory = deductInventory
        if let notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            batch.notes = notes
        }
        modelContext.insert(batch)

        do {
            for deduction in planned {
                let remaining = deduction.inventoryItem.onHandBase - deduction.requiredInBase
                deduction.inventoryItem.syncQuantities(preferredOnHand: remaining)

                let audit = InventoryDeduction(
                    amount: deduction.requiredInBase,
                    unit: deduction.inventoryBaseUnit,
                    item: deduction.inventoryItem
                )
                audit.batch = batch
                modelContext.insert(audit)
            }

            try modelContext.save()
            return batch
        } catch {
            for deduction in planned {
                if let original = previousOnHand[deduction.inventoryItem.id] {
                    deduction.inventoryItem.syncQuantities(preferredOnHand: original)
                }
            }
            modelContext.delete(batch)
            throw BatchDeductionError.persistenceFailed(error.localizedDescription)
        }
    }
}
