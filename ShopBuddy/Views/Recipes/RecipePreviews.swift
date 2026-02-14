import SwiftUI
import SwiftData

@MainActor
private enum RecipePreviewFactory {
    static func makeContainer() -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(
            for:
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
            configurations: config
        )

        seedIfNeeded(in: container.mainContext)
        return container
    }

    static func makeCoordinator() -> AppCoordinator {
        let coordinator = AppCoordinator()
        let manager = Employee(name: "Preview Manager", pin: "1111", role: .manager)
        coordinator.currentEmployee = manager
        coordinator.currentViewState = .managerView(manager)
        coordinator.isAuthenticated = true
        return coordinator
    }

    private static func seedIfNeeded(in context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<RecipeTemplate>())) ?? []
        guard existing.isEmpty else { return }

        let dryStorage = InventoryCategory(name: "Dry Storage", emoji: "📦")
        let backBar = InventoryLocation(name: "Back Bar", emoji: "🍶")
        backBar.category = dryStorage

        let vanilla = InventoryItem(
            name: "Vanilla Extract",
            stockLevel: 483,
            parLevel: 200,
            unitType: "bottle",
            baseUnit: .grams,
            packSizeBase: 483,
            packUnit: .grams,
            packName: "Bottle",
            onHandBase: 483,
            vendor: "Blue Bird"
        )
        vanilla.location = backBar

        let water = InventoryItem(
            name: "Filtered Water",
            stockLevel: 5000,
            parLevel: 1000,
            unitType: "mL",
            baseUnit: .milliliters,
            onHandBase: 5000
        )
        water.location = backBar

        let syrups = PrepCategory(name: "Syrups", emoji: "🧴")
        let recipe = RecipeTemplate(title: "Vanilla Syrup", category: syrups, yieldAmount: 1, yieldUnit: .liters)
        recipe.allergens = ["None"]
        recipe.restrictions = ["Vegetarian"]

        let vanillaIngredient = RecipeIngredient(displayName: "Vanilla Extract", amount: 300, unit: .grams, sortOrder: 0)
        vanillaIngredient.inventoryItemRef = vanilla

        let waterIngredient = RecipeIngredient(displayName: "Water", amount: 700, unit: .milliliters, sortOrder: 1)
        waterIngredient.inventoryItemRef = water

        recipe.ingredients = [vanillaIngredient, waterIngredient]
        recipe.steps = [
            RecipeStep(text: "Combine ingredients and whisk.", sortOrder: 0),
            RecipeStep(text: "Bottle and label.", sortOrder: 1)
        ]

        let mismatchRecipe = RecipeTemplate(title: "Conversion Failure Example", category: syrups)
        let mismatchIngredient = RecipeIngredient(displayName: "Water As Grams", amount: 300, unit: .grams, sortOrder: 0)
        mismatchIngredient.inventoryItemRef = water
        mismatchRecipe.ingredients = [mismatchIngredient]

        context.insert(dryStorage)
        context.insert(backBar)
        context.insert(vanilla)
        context.insert(water)
        context.insert(syrups)
        context.insert(recipe)
        context.insert(mismatchRecipe)

        try? context.save()
    }
}

struct RecipeBatchPreviewHarness: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RecipeTemplate.title) private var recipes: [RecipeTemplate]
    @Query(sort: \InventoryItem.name) private var items: [InventoryItem]

    @State private var output: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Batch Logic Harness")
                .font(.title3.bold())

            Button("Run 1.0x then 2.0x checks") {
                runChecks()
            }

            ForEach(output, id: \.self) { line in
                Text(line)
                    .font(.caption.monospaced())
            }

            Spacer()
        }
        .padding()
    }

    private func runChecks() {
        output.removeAll()

        guard let vanillaItem = items.first(where: { $0.name == "Vanilla Extract" }),
              let vanillaRecipe = recipes.first(where: { $0.title == "Vanilla Syrup" }),
              let mismatchRecipe = recipes.first(where: { $0.title == "Conversion Failure Example" })
        else {
            output.append("Missing seeded preview data")
            return
        }

        vanillaItem.syncQuantities(preferredOnHand: 483)
        try? modelContext.save()

        let service = BatchDeductionService(modelContext: modelContext)

        do {
            _ = try service.makeBatch(recipe: vanillaRecipe, multiplier: 1.0, madeBy: nil)
            output.append("1) Pass: remaining = \(formatDecimalForUI(vanillaItem.onHandBase)) g (expected 183 g)")
        } catch {
            output.append("1) Failed unexpectedly: \(error.localizedDescription)")
        }

        vanillaItem.syncQuantities(preferredOnHand: 483)
        try? modelContext.save()

        do {
            _ = try service.makeBatch(recipe: vanillaRecipe, multiplier: 2.0, madeBy: nil)
            output.append("2) Failed: expected insufficient stock")
        } catch {
            output.append("2) Pass: \(error.localizedDescription)")
            output.append("2) Stock unchanged = \(formatDecimalForUI(vanillaItem.onHandBase)) g")
        }

        do {
            _ = try service.makeBatch(recipe: mismatchRecipe, multiplier: 1.0, madeBy: nil)
            output.append("3) Failed: expected unit conversion error")
        } catch {
            output.append("3) Pass: \(error.localizedDescription)")
        }
    }
}

#Preview("Recipe Editor") {
    @MainActor in
    let container = RecipePreviewFactory.makeContainer()
    let coordinator = RecipePreviewFactory.makeCoordinator()
    let recipe = (try? container.mainContext.fetch(FetchDescriptor<RecipeTemplate>()).first) ?? RecipeTemplate(title: "Preview")

    NavigationStack {
        RecipeEditView(recipe: recipe)
    }
    .environment(coordinator)
    .modelContainer(container)
}

#Preview("Batch Harness") {
    @MainActor in
    let container = RecipePreviewFactory.makeContainer()
    RecipeBatchPreviewHarness()
        .modelContainer(container)
}
