import SwiftUI
import SwiftData

struct BatchBuilderSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let recipe: RecipeTemplate
    let initialMultiplier: Decimal

    @State private var recipeViewModel: RecipeViewModel?
    @State private var scaleViewModel: RecipeScaleViewModel

    @State private var selectedEmployee: Employee?
    @State private var deductInventory: Bool = false
    @State private var notes: String = ""
    @State private var errorMessage: String?
    @State private var showingError = false

    @Query(sort: \Employee.name) private var employees: [Employee]
    @Query private var appSettings: [AppSettings]

    init(recipe: RecipeTemplate, initialMultiplier: Decimal = 1.0) {
        self.recipe = recipe
        self.initialMultiplier = initialMultiplier
        _scaleViewModel = State(
            initialValue: RecipeScaleViewModel(
                ingredients: recipe.ingredients,
                multiplier: initialMultiplier
            )
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                batchDetailsSection
                scalingSection
                ingredientsSection
                notesSection
            }
            .navigationTitle("Make Batch")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    restoreButton
                }
                #else
                ToolbarItem(placement: .automatic) {
                    restoreButton
                }
                #endif

                ToolbarItem(placement: .confirmationAction) {
                    Button("Complete Batch") {
                        completeBatch()
                    }
                    .disabled(selectedEmployee == nil && requireEmployee)
                }
            }
            .onAppear {
                if recipeViewModel == nil {
                    recipeViewModel = RecipeViewModel(modelContext: modelContext)
                }
                if let settings = appSettings.first {
                    deductInventory = settings.allowEmployeeInventoryEdit
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
    }

    private var restoreButton: some View {
        Button("Restore") {
            scaleViewModel.restoreToTemplate()
        }
        .disabled(!canRestore)
    }

    private var canRestore: Bool {
        scaleViewModel.anchorIngredientID != nil || scaleViewModel.multiplier != 1.0 || !scaleViewModel.editedAmounts.isEmpty
    }

    private var batchDetailsSection: some View {
        Section("Batch Details") {
            Picker("Made By", selection: $selectedEmployee) {
                Text("Select Employee").tag(nil as Employee?)
                ForEach(employees.filter { $0.isActive }) { employee in
                    Text(employee.name).tag(employee as Employee?)
                }
            }

            Toggle("Deduct Inventory", isOn: $deductInventory)
                .disabled(!canDeduct)
        }
    }

    private var scalingSection: some View {
        Section("Yield & Scaling") {
            HStack {
                Text("Multiplier")
                Spacer()

                Stepper(value: multiplierStepperBinding, in: 0.1...100, step: 0.1) {
                    Text("\(formatDecimalForUI(scaleViewModel.multiplier))x")
                        .monospacedDigit()
                }
                .fixedSize()
            }

            if let anchorName = scaleViewModel.anchorIngredientName() {
                Label("Scaling from: \(anchorName)", systemImage: "arrow.left.arrow.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LabeledContent("Final Yield") {
                let amount = recipe.defaultYieldAmount * scaleViewModel.multiplier
                Text("\(formatDecimalForUI(amount)) \(recipe.defaultYieldUnit.displaySymbol)")
                    .bold()
                    .monospacedDigit()
            }
        }
    }

    private var multiplierStepperBinding: Binding<Double> {
        Binding<Double>(
            get: {
                NSDecimalNumber(decimal: scaleViewModel.multiplier).doubleValue
            },
            set: { newValue in
                let normalized = Decimal(
                    string: String(format: "%.2f", newValue),
                    locale: Locale(identifier: "en_US_POSIX")
                ) ?? 1.0
                scaleViewModel.setMultiplierManually(normalized)
            }
        )
    }

    private var ingredientsSection: some View {
        Section("Ingredients Required") {
            if scaleViewModel.ingredients.isEmpty {
                Text("No ingredients found.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(scaleViewModel.ingredients, id: \.id) { ingredient in
                    BatchIngredientEditableRow(
                        ingredient: ingredient,
                        amountText: bindingForAmount(of: ingredient),
                        isAnchor: scaleViewModel.anchorIngredientID == ingredient.id,
                        errorMessage: scaleViewModel.errorMessage(for: ingredient)
                    )
                }
            }
        }
    }

    private func bindingForAmount(of ingredient: RecipeIngredient) -> Binding<String> {
        Binding(
            get: {
                scaleViewModel.displayedText(for: ingredient)
            },
            set: { newText in
                scaleViewModel.setAnchorAmount(
                    ingredientID: ingredient.id,
                    newText: newText,
                    editedDisplayUnit: ingredient.unit
                )
            }
        )
    }

    private var notesSection: some View {
        Section("Notes") {
            TextField("Batch notes...", text: $notes)
        }
    }

    private var requireEmployee: Bool {
        appSettings.first?.requireClockInForChecklists ?? false
    }

    private var canDeduct: Bool {
        appSettings.first?.allowEmployeeInventoryEdit ?? true
    }

    private func completeBatch() {
        guard let recipeViewModel else { return }

        let result = recipeViewModel.makeBatch(
            recipe: recipe,
            multiplier: scaleViewModel.multiplier,
            employee: selectedEmployee,
            deductInventory: deductInventory,
            notes: notes
        )

        if result.success {
            dismiss()
        } else {
            errorMessage = result.error
            showingError = true
        }
    }
}

struct BatchIngredientEditableRow: View {
    let ingredient: RecipeIngredient
    @Binding var amountText: String
    let isAnchor: Bool
    let errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ingredient.displayName)
                        .font(.headline)

                    Text("Base: \(formatDecimalForUI(ingredient.baseAmount)) \(ingredient.unit.displaySymbol)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 8) {
                    TextField("0", text: $amountText)
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif

                    Text(ingredient.unit.displaySymbol)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 34, alignment: .leading)
                }
            }

            if isAnchor {
                Text("Anchor")
                    .font(.caption2)
                    .foregroundStyle(Color.accentColor)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }
}
