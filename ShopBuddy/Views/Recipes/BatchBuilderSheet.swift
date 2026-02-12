import SwiftUI
import SwiftData

struct BatchBuilderSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let recipe: RecipeTemplate
    @State private var viewModel: RecipeViewModel?
    
    // Form State
    @State private var multiplier: Decimal = 1.0
    @State private var selectedEmployee: Employee?
    @State private var deductInventory: Bool = false
    @State private var notes: String = ""
    @State private var anchorValue: Decimal? // For anchor scaling
    @State private var errorMessage: String?
    @State private var showingError = false
    
    // Anchor Scaling State
    @State private var scalingIngredient: RecipeIngredient?
    @State private var tempTargetAmount: Decimal = 0.0
    
    // Dependencies
    @Query(sort: \Employee.name) private var employees: [Employee]
    @Query private var appSettings: [AppSettings]
    
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
                ToolbarItem(placement: .confirmationAction) {
                    Button("Complete Batch") {
                        completeBatch()
                    }
                    .disabled(selectedEmployee == nil && requireEmployee)
                }
            }
            .onAppear {
                if viewModel == nil {
                    viewModel = RecipeViewModel(modelContext: modelContext)
                }
                // Default deduction based on user role? For now rely on AppSettings
                if let settings = appSettings.first {
                    deductInventory = settings.allowEmployeeInventoryEdit // Default to setting
                }
            }
            .alert("Scale by Ingredient", isPresented: Binding(
                get: { scalingIngredient != nil },
                set: { if !$0 { scalingIngredient = nil } }
            )) {
                TextField("Target Amount", value: $tempTargetAmount, format: .number)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                Button("Cancel", role: .cancel) { }
                Button("Scale") {
                    if let ingredient = scalingIngredient, ingredient.baseAmount > 0 {
                        multiplier = tempTargetAmount / ingredient.baseAmount
                    }
                }
            } message: {
                if let ingredient = scalingIngredient, let vm = viewModel {
                    Text("Enter target amount for \(ingredient.displayName) (\(ingredient.unit.rawValue)). Base amount: \(vm.formattedAmount(ingredient.baseAmount)).")
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
    }
    
    var batchDetailsSection: some View {
        Section("Batch Details") {
            // Employee Picker
            Picker("Made By", selection: $selectedEmployee) {
                Text("Select Employee").tag(nil as Employee?)
                ForEach(employees.filter { $0.isActive }) { employee in
                    Text(employee.name).tag(employee as Employee?)
                }
            }
            
            // Toggle Deduction
            Toggle("Deduct Inventory", isOn: $deductInventory)
                .disabled(!canDeduct)
        }
    }
    
    var scalingSection: some View {
        Section("Yield & Scaling") {
            HStack {
                Text("Multiplier")
                Spacer()
                Stepper("\(multiplier, format: .number.precision(.fractionLength(2)))x", value: $multiplier, in: 0.1...100, step: 0.25)
                    .fixedSize()
            }
            
            LabeledContent("Final Yield") {
                let amount = recipe.defaultYieldAmount * multiplier
                if let vm = viewModel {
                    Text("\(vm.formattedAmount(amount)) \(recipe.defaultYieldUnit.rawValue)")
                        .bold()
                }
            }
        }
    }
    
    var ingredientsSection: some View {
        Section("Ingredients Required") {
            if recipe.ingredients.isEmpty {
                Text("No ingredients found.")
                    .foregroundStyle(.secondary)
            } else {
                let sortedIngredients = recipe.ingredients.sorted { $0.sortOrder < $1.sortOrder }
                ForEach(0..<sortedIngredients.count, id: \.self) { index in
                    BatchIngredientRow(
                        ingredient: sortedIngredients[index],
                        multiplier: multiplier,
                        viewModel: viewModel,
                        onScale: { ingredient, amount in
                            scalingIngredient = ingredient
                            tempTargetAmount = amount
                        }
                    )
                }
            }
        }
    }
    
    var notesSection: some View {
        Section("Notes") {
            TextField("Batch notes...", text: $notes)
        }
    }
    
    // Logic Helpers
    var requireEmployee: Bool {
        appSettings.first?.requireClockInForChecklists ?? false // Reuse this or add new setting?
    }
    
    var canDeduct: Bool {
        // Simple check for now. Later: Check if user is Manager.
        appSettings.first?.allowEmployeeInventoryEdit ?? true
    }
    
    func completeBatch() {
        guard let vm = viewModel else { return }
        
        let result = vm.makeBatch(
            recipe: recipe,
            multiplier: multiplier,
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

struct BatchIngredientRow: View {
    let ingredient: RecipeIngredient
    let multiplier: Decimal
    var viewModel: RecipeViewModel?
    let onScale: (RecipeIngredient, Decimal) -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(ingredient.displayName)
                    .font(.headline)
                if multiplier != 1.0, let vm = viewModel {
                    Text("Base: \(vm.formattedAmount(ingredient.baseAmount)) \(ingredient.unit.rawValue)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            let amount = ingredient.baseAmount * multiplier
            Text("\(viewModel?.formattedAmount(amount) ?? "\(amount)") \(ingredient.unit.rawValue)")
                .foregroundStyle(.secondary)
            
            Button(action: {
                onScale(ingredient, amount)
            }) {
                Image(systemName: "arrow.left.arrow.right")
                    .foregroundStyle(Color.accentColor)
                    .padding(8)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.borderless)
            .padding(.leading, 8)
        }
        .padding(.vertical, 4)
    }
}
