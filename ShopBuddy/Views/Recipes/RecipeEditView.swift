import SwiftUI
import SwiftData
import PhotosUI

struct RecipeEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Bindable var recipe: RecipeTemplate
    var isNew: Bool
    
    @Query(sort: \PrepCategory.name) private var categories: [PrepCategory]
    @Query(sort: \InventoryItem.name) private var inventoryItems: [InventoryItem]
    
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showingAddIngredient = false
    @State private var showingAddStep = false
    
    // Temporary states for new ingredient
    @State private var newIngredientName = ""
    @State private var newIngredientAmount: Decimal = 0
    @State private var newIngredientUnit: UnitType = .grams
    @State private var newIngredientInventoryItem: InventoryItem?
    
    // Temporary state for new step
    @State private var newStepInstruction = ""
    
    init(recipe: RecipeTemplate, isNew: Bool = false) {
        self.recipe = recipe
        self.isNew = isNew
    }
    
    var body: some View {
        Form {
            basicInfoSection
            dietaryInfoSection
            photoSection
            ingredientsSection
            stepsSection
        }
        .navigationTitle(isNew ? "New Recipe" : "Edit Recipe")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
            
            if isNew {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        modelContext.delete(recipe)
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .padding()
        .frame(minWidth: 500, minHeight: 600)
        #endif
        .onChange(of: selectedPhotoItem) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                    withAnimation {
                        recipe.photoData = data
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddIngredient) {
            NavigationStack {
                Form {
                    Section("Ingredient Details") {
                        TextField("Name (or select below)", text: $newIngredientName)
                        
                        HStack {
                            TextField("Amount", value: $newIngredientAmount, format: .number)
                                #if os(iOS)
                                .keyboardType(.decimalPad)
                                #endif
                            Picker("Unit", selection: $newIngredientUnit) {
                                ForEach(UnitType.allCases, id: \.self) { unit in
                                    Text(unit.rawValue).tag(unit)
                                }
                            }
                            .labelsHidden()
                        }
                    }
                    
                    Section("Link to Inventory (Optional)") {
                        if newIngredientInventoryItem != nil {
                            HStack {
                                Text("Linked: \(newIngredientInventoryItem!.name)")
                                    .foregroundColor(.accentColor)
                                Spacer()
                                Button("Clear") {
                                    newIngredientInventoryItem = nil
                                    if newIngredientName == newIngredientInventoryItem?.name {
                                         newIngredientName = ""
                                    }
                                }
                                .font(.caption)
                            }
                        }
                        
                        TextField("Search Inventory...", text: $ingredientSearchText)
                        
                        List {
                            ForEach(filteredInventoryItems) { item in
                                Button {
                                    newIngredientInventoryItem = item
                                    // Auto-fill name/unit if empty or default
                                    if newIngredientName.isEmpty {
                                        newIngredientName = item.name
                                    }
                                    if let unit = UnitType(rawValue: item.unitType) {
                                         newIngredientUnit = unit
                                    }
                                } label: {
                                    HStack {
                                        Text(item.name)
                                        Spacer()
                                        if let cat = item.location?.category {
                                            Text(cat.emoji).font(.caption)
                                        }
                                        if newIngredientInventoryItem?.id == item.id {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.accentColor)
                                        }
                                    }
                                }
                                .foregroundStyle(.primary)
                            }
                        }
                        .frame(minHeight: 200)
                    }
                }
                .navigationTitle("Add Ingredient")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingAddIngredient = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") {
                            addIngredient()
                            showingAddIngredient = false
                        }
                        .disabled(newIngredientName.isEmpty)
                    }
                }
            }
            .presentationDetents([.large])
        }
    }
    
    // Searchable Ingredient Picker
    @State private var ingredientSearchText = ""
    
    var filteredInventoryItems: [InventoryItem] {
        if ingredientSearchText.isEmpty {
            return inventoryItems
        } else {
            return inventoryItems.filter { $0.name.localizedCaseInsensitiveContains(ingredientSearchText) }
        }
    }
    
    var basicInfoSection: some View {
        Section("Basic Info") {
            TextField("Recipe Title", text: $recipe.title)
            
            Picker("Category", selection: $recipe.category) {
                Text("None").tag(nil as PrepCategory?)
                ForEach(categories) { category in
                    Text(category.name).tag(Optional(category))
                }
            }
            
            HStack {
                TextField("Yield", value: $recipe.defaultYieldAmount, format: .number)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                Picker("Unit", selection: $recipe.defaultYieldUnit) {
                    ForEach(UnitType.allCases, id: \.self) { unit in
                        Text(unit.rawValue).tag(unit)
                    }
                }
                .labelsHidden()
            }
        }
    }
    
    var dietaryInfoSection: some View {
        Section("Dietary Info") {
            MultiSelector(
                label: "Allergens",
                options: RecipeConstants.allAllergens,
                selection: $recipe.allergens
            )
            
            MultiSelector(
                label: "Restrictions",
                options: RecipeConstants.allRestrictions,
                selection: $recipe.restrictions
            )
        }
    }
    
    var photoSection: some View {
        Section("Photo") {
            if let data = recipe.photoData, let uiImage = UIImage(data: data) {
                #if os(macOS)
                Image(nsImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 200)
                    .cornerRadius(8)
                #else
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 200)
                    .cornerRadius(8)
                    .listRowInsets(EdgeInsets())
                #endif
                
                Button("Remove Photo", role: .destructive) {
                    withAnimation {
                        recipe.photoData = nil
                    }
                }
            }
            
            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                Label(recipe.photoData == nil ? "Select Photo" : "Change Photo", systemImage: "photo")
            }
        }
    }
    
    var ingredientsSection: some View {
        Section("Ingredients") {
            ForEach(recipe.ingredients) { ingredient in
                HStack {
                    VStack(alignment: .leading) {
                        Text(ingredient.displayName)
                            .font(.headline)
                        Text("\(formatted(ingredient.baseAmount)) \(ingredient.unit.rawValue)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if let item = ingredient.inventoryItem {
                        Label(item.name, systemImage: "shippingbox")
                            .font(.caption2)
                            .padding(4)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(4)
                    }
                }
            }
            .onDelete(perform: deleteIngredients)
            
            Button("Add Ingredient") {
                showingAddIngredient = true
            }
        }
    }
    
    var stepsSection: some View {
        Section("Steps") {
            ForEach(recipe.steps.sorted(by: { $0.sortOrder < $1.sortOrder })) { step in
                HStack(alignment: .top) {
                    Text("\(step.sortOrder + 1).")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .frame(width: 24, alignment: .leading)
                    
                    Text(step.text)
                        .padding(.vertical, 2)
                }
            }
            .onDelete(perform: deleteSteps)
            .onMove(perform: moveSteps)
            
            HStack {
                TextField("Next step...", text: $newStepInstruction)
                    .onSubmit {
                        addStep()
                    }
                Button {
                    addStep()
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .disabled(newStepInstruction.isEmpty)
            }
        }
    }
    
    private func addIngredient() {
        let ingredient = RecipeIngredient(
            displayName: newIngredientName,
            amount: newIngredientAmount,
            unit: newIngredientUnit
        )
        ingredient.inventoryItem = newIngredientInventoryItem
        recipe.ingredients.append(ingredient)
        
        // Reset form
        newIngredientName = ""
        newIngredientAmount = 0
        newIngredientInventoryItem = nil
    }
    
    private func deleteIngredients(at offsets: IndexSet) {
        withAnimation {
            recipe.ingredients.remove(atOffsets: offsets)
        }
    }
    
    private func addStep() {
        guard !newStepInstruction.isEmpty else { return }
        
        let newIndex = recipe.steps.count
        let step = RecipeStep(text: newStepInstruction, sortOrder: newIndex)
        withAnimation {
            recipe.steps.append(step)
        }
        newStepInstruction = ""
    }
    
    private func deleteSteps(at offsets: IndexSet) {
        withAnimation {
            recipe.steps.remove(atOffsets: offsets)
            reindexSteps()
        }
    }
    
    private func moveSteps(from source: IndexSet, to destination: Int) {
        withAnimation {
            recipe.steps.move(fromOffsets: source, toOffset: destination)
            reindexSteps()
        }
    }
    
    private func reindexSteps() {
        for (index, step) in recipe.steps.enumerated() {
            step.sortOrder = index
        }
    }
    
    private func formatted(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "\(value)"
    }
}

struct MultiSelector: View {
    let label: String
    let options: [String]
    @Binding var selection: Set<String>
    
    var body: some View {
        NavigationLink(destination: multiSelectionView) {
            HStack {
                Text(label)
                Spacer()
                if selection.isEmpty {
                    Text("None").foregroundColor(.secondary)
                } else {
                    Text(selection.joined(separator: ", "))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
    
    private var multiSelectionView: some View {
        List {
            ForEach(options, id: \.self) { option in
                Button(action: { toggle(option) }) {
                    HStack {
                        Text(option)
                        Spacer()
                        if selection.contains(option) {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                }
                .foregroundStyle(.primary)
            }
        }
        .navigationTitle(label)
    }
    
    private func toggle(_ option: String) {
        if selection.contains(option) {
            selection.remove(option)
        } else {
            selection.insert(option)
        }
    }
}

#if os(macOS)
import AppKit
#else
import UIKit
#endif
