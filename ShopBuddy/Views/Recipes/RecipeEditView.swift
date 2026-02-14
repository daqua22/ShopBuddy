import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

private struct RecipeIngredientDraft: Identifiable {
    let id: UUID
    var displayName: String
    var amountText: String
    var unit: UnitType
    var inventoryItem: InventoryItem?

    init(
        id: UUID = UUID(),
        displayName: String = "",
        amountText: String = "",
        unit: UnitType = .grams,
        inventoryItem: InventoryItem? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.amountText = amountText
        self.unit = unit
        self.inventoryItem = inventoryItem
    }

    var parsedAmount: Decimal? {
        parseDecimal(amountText)
    }

    var isValid: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (parsedAmount ?? 0) > 0
    }
}

private struct RecipeStepDraft: Identifiable {
    let id: UUID
    var text: String

    init(id: UUID = UUID(), text: String = "") {
        self.id = id
        self.text = text
    }
}

private struct IngredientEditorSession: Identifiable {
    let id = UUID()
    let index: Int?
    let draft: RecipeIngredientDraft
}

struct RecipeEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppCoordinator.self) private var coordinator

    @Bindable var recipe: RecipeTemplate
    let isNew: Bool

    @Query(sort: \PrepCategory.name) private var categories: [PrepCategory]
    @Query(sort: \InventoryItem.name) private var inventoryItems: [InventoryItem]

    @State private var titleText = ""
    @State private var selectedCategory: PrepCategory?
    @State private var baseYieldAmountText = ""
    @State private var baseYieldUnit: UnitType = .unit
    @State private var selectedAllergens: Set<String> = []
    @State private var selectedRestrictions: Set<String> = []
    @State private var ingredientDrafts: [RecipeIngredientDraft] = []
    @State private var stepDrafts: [RecipeStepDraft] = []
    @State private var photoData: Data?

    @State private var ingredientSession: IngredientEditorSession?
    @State private var showCategorySheet = false
    @State private var newCategoryName = ""
    @State private var newCategoryEmoji = "🥣"
    @State private var showingSaveError = false
    @State private var saveErrorMessage = ""
    @State private var hasLoadedDraft = false

    #if os(macOS)
    @State private var showingFileImporter = false
    #else
    @State private var selectedPhotoItem: PhotosPickerItem?
    #endif

    init(recipe: RecipeTemplate, isNew: Bool = false) {
        self.recipe = recipe
        self.isNew = isNew
    }

    var body: some View {
        Form {
            metadataSection
            dietarySection
            photoSection
            ingredientsSection
            stepsSection
            validationSection
        }
        .liquidFormChrome()
        .macPagePadding()
        .navigationTitle(isNew ? "Create Recipe" : "Edit Recipe")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", role: .cancel) {
                    cancelEditing()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveRecipe()
                }
                .disabled(!canSave)
                .keyboardShortcut("s", modifiers: [.command])
            }
        }
        .onAppear {
            guard !hasLoadedDraft else { return }
            loadDraft()
            hasLoadedDraft = true
        }
        #if !os(macOS)
        .onChange(of: selectedPhotoItem) { _, newValue in
            guard let newValue else { return }
            Task {
                if let data = try? await newValue.loadTransferable(type: Data.self) {
                    await MainActor.run {
                        photoData = data
                    }
                }
            }
        }
        #endif
        .sheet(item: $ingredientSession) { session in
            RecipeIngredientEditorSheet(
                title: session.index == nil ? "Add Ingredient" : "Edit Ingredient",
                draft: session.draft,
                inventoryItems: inventoryItems
            ) { updatedDraft in
                applyIngredient(updatedDraft, at: session.index)
            } onCancel: {
                ingredientSession = nil
            }
        }
        .sheet(isPresented: $showCategorySheet) {
            RecipeCategoryCreationSheet(
                categoryName: $newCategoryName,
                categoryEmoji: $newCategoryEmoji
            ) {
                createCategory()
            }
            #if os(macOS)
            .frame(minWidth: 520, minHeight: 520)
            #endif
        }
        .alert("Unable to Save", isPresented: $showingSaveError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(saveErrorMessage)
        }
    }

    private var metadataSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("Recipe Name")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(.secondary)
                TextField("e.g. Vanilla Syrup", text: $titleText)
                    #if !os(macOS)
                    .textInputAutocapitalization(.words)
                    #endif
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Category")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: DesignSystem.Spacing.grid_1) {
                    Picker("Category", selection: $selectedCategory) {
                        Text("None").tag(nil as PrepCategory?)
                        ForEach(categories) { category in
                            Text(category.name).tag(category as PrepCategory?)
                        }
                    }
                    if coordinator.isManager {
                        Button {
                            newCategoryName = ""
                            newCategoryEmoji = "🥣"
                            showCategorySheet = true
                        } label: {
                            Image(systemName: "plus.circle")
                        }
                        .buttonStyle(.plain)
                        .help("Add Category")
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Base Yield (Optional)")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: DesignSystem.Spacing.grid_1) {
                    TextField("Amount", text: $baseYieldAmountText)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    Picker("Unit", selection: $baseYieldUnit) {
                        ForEach(UnitType.selectableCases, id: \.self) { unit in
                            Text(unit.displaySymbol).tag(unit)
                        }
                    }
                    .frame(maxWidth: 160)
                }
            }
        } header: {
            Text("Recipe")
        }
    }

    private var dietarySection: some View {
        Section {
            TagChipSelector(
                title: "Allergens",
                options: RecipeConstants.allAllergens,
                selection: $selectedAllergens
            )

            Divider()

            TagChipSelector(
                title: "Restrictions",
                options: RecipeConstants.allRestrictions,
                selection: $selectedRestrictions
            )
        } header: {
            Text("Dietary")
        }
    }

    private var photoSection: some View {
        Section {
            if let photoData, let image = platformImage(from: photoData) {
                recipeImageView(image)

                Button("Remove Photo", role: .destructive) {
                    self.photoData = nil
                }
            }

            #if os(macOS)
            Button(photoData == nil ? "Choose Photo" : "Change Photo") {
                showingFileImporter = true
            }
            .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.image]) { result in
                guard case let .success(url) = result else { return }
                if let data = try? Data(contentsOf: url) {
                    photoData = data
                }
            }
            #else
            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                Label(photoData == nil ? "Select Photo" : "Change Photo", systemImage: "photo")
            }
            #endif
        } header: {
            Text("Photo")
        }
    }

    private var ingredientsSection: some View {
        Section("Ingredients") {
            if ingredientDrafts.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("No ingredients yet", systemImage: "shippingbox")
                        .font(.headline)
                    Text("Add at least one ingredient to enable saving.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else {
                ForEach(ingredientDrafts.indices, id: \.self) { index in
                    ingredientRowView(for: index)
                }
                .onDelete { offsets in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        ingredientDrafts.remove(atOffsets: offsets)
                    }
                }
            }

            Button {
                ingredientSession = IngredientEditorSession(index: nil, draft: RecipeIngredientDraft())
            } label: {
                Label("Add Ingredient", systemImage: "plus.circle.fill")
            }
            .keyboardShortcut("n", modifiers: [.command])
        }
    }

    private func ingredientRowView(for index: Int) -> some View {
        let draft = ingredientDrafts[index]

        return Button {
            ingredientSession = IngredientEditorSession(index: index, draft: draft)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(draft.displayName.isEmpty ? "Untitled Ingredient" : draft.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("\(formatDecimalForUI(draft.parsedAmount ?? 0)) \(draft.unit.displaySymbol)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Label(draft.inventoryItem?.name ?? "No inventory link", systemImage: "link")
                        .font(.caption)
                        .foregroundStyle(draft.inventoryItem == nil ? .secondary : .primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                if let warning = unitMismatchMessage(for: draft) {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Edit") {
                ingredientSession = IngredientEditorSession(index: index, draft: draft)
            }
            Button("Delete", role: .destructive) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    ingredientDrafts.remove(atOffsets: IndexSet(integer: index))
                }
            }
        }
    }

    private var stepsSection: some View {
        Section {
            if stepDrafts.isEmpty {
                Text("No preparation steps yet.")
                    .foregroundStyle(.secondary)
            }

            ForEach($stepDrafts) { $step in
                TextField("Step", text: $step.text)
            }
            .onDelete { offsets in
                stepDrafts.remove(atOffsets: offsets)
            }

            Button {
                stepDrafts.append(RecipeStepDraft(text: ""))
            } label: {
                Label("Add Step", systemImage: "text.badge.plus")
            }
        } header: {
            Text("Preparation")
        }
    }

    @ViewBuilder
    private var validationSection: some View {
        if !validationErrors.isEmpty {
            Section {
                ForEach(validationErrors, id: \.self) { message in
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Validation")
            }
        }
    }

    private var validationErrors: [String] {
        var errors: [String] = []

        if titleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Recipe name is required.")
        }

        if ingredientDrafts.isEmpty {
            errors.append("At least one ingredient is required.")
        }

        let invalidIngredients = ingredientDrafts.filter { !$0.isValid }
        if !invalidIngredients.isEmpty {
            errors.append("Each ingredient needs a name and amount greater than 0.")
        }

        if !baseYieldAmountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           (parseDecimal(baseYieldAmountText) ?? 0) <= 0 {
            errors.append("Base yield must be greater than 0 when provided.")
        }

        return errors
    }

    private var canSave: Bool {
        validationErrors.isEmpty
    }

    private func loadDraft() {
        titleText = recipe.title
        selectedCategory = recipe.category

        if recipe.baseYieldAmount > 0 {
            baseYieldAmountText = formatDecimalForUI(recipe.baseYieldAmount)
        } else {
            baseYieldAmountText = ""
        }
        baseYieldUnit = recipe.baseYieldUnit

        selectedAllergens = Set(recipe.allergens)
        selectedRestrictions = Set(recipe.restrictions)
        photoData = recipe.photoData

        ingredientDrafts = recipe.ingredients
            .sorted(by: { $0.sortOrder < $1.sortOrder })
            .map {
                RecipeIngredientDraft(
                    id: $0.id,
                    displayName: $0.displayName,
                    amountText: formatDecimalForUI($0.baseAmount),
                    unit: $0.unit,
                    inventoryItem: $0.inventoryItem
                )
            }

        stepDrafts = recipe.steps
            .sorted(by: { $0.sortOrder < $1.sortOrder })
            .map { RecipeStepDraft(id: $0.id, text: $0.text) }
    }

    private func applyIngredient(_ updated: RecipeIngredientDraft, at index: Int?) {
        if let index, ingredientDrafts.indices.contains(index) {
            ingredientDrafts[index] = updated
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                ingredientDrafts.append(updated)
            }
        }
        ingredientSession = nil
    }

    private func saveRecipe() {
        recipe.title = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        recipe.category = selectedCategory

        if let parsedYield = parseDecimal(baseYieldAmountText), parsedYield > 0 {
            recipe.baseYieldAmount = parsedYield
        } else {
            recipe.baseYieldAmount = 1
        }
        recipe.baseYieldUnit = baseYieldUnit

        recipe.allergens = Array(selectedAllergens).sorted()
        recipe.restrictions = Array(selectedRestrictions).sorted()
        recipe.photoData = photoData

        recipe.ingredients.removeAll()
        for (index, draft) in ingredientDrafts.enumerated() {
            let ingredient = RecipeIngredient(
                displayName: draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                amount: parseDecimalOrZero(draft.amountText),
                unit: draft.unit,
                sortOrder: index
            )
            ingredient.inventoryItemRef = draft.inventoryItem
            recipe.ingredients.append(ingredient)
        }

        recipe.steps.removeAll()
        for (index, draft) in stepDrafts.enumerated() {
            let text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            recipe.steps.append(RecipeStep(text: text, sortOrder: index))
        }

        recipe.updatedAt = Date()

        do {
            try modelContext.save()
            dismiss()
        } catch {
            saveErrorMessage = error.localizedDescription
            showingSaveError = true
        }
    }

    private func cancelEditing() {
        if isNew {
            modelContext.delete(recipe)
        }
        dismiss()
    }

    private func createCategory() {
        let trimmed = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let category = PrepCategory(name: trimmed, emoji: newCategoryEmoji, sortOrder: categories.count)
        modelContext.insert(category)
        selectedCategory = category
        do {
            try modelContext.save()
            showCategorySheet = false
        } catch {
            saveErrorMessage = error.localizedDescription
            showingSaveError = true
        }
    }

    private func unitMismatchMessage(for draft: RecipeIngredientDraft) -> String? {
        guard let inventoryItem = draft.inventoryItem else { return nil }

        let inventoryUnit = inventoryItem.baseUnit
        if draft.unit.family != inventoryUnit.family {
            return "\(draft.unit.displaySymbol) cannot convert to \(inventoryUnit.displaySymbol)."
        }

        if draft.unit.family == .other && draft.unit != inventoryUnit {
            return "Other units must match exactly for deductions."
        }

        return nil
    }

    @ViewBuilder
    private func recipeImageView(_ image: PlatformImage) -> some View {
        #if os(macOS)
        Image(nsImage: image)
            .resizable()
            .scaledToFill()
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        #else
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        #endif
    }

    private func platformImage(from data: Data) -> PlatformImage? {
        #if os(macOS)
        return NSImage(data: data)
        #else
        return UIImage(data: data)
        #endif
    }
}

private struct TagChipSelector: View {
    let title: String
    let options: [String]
    @Binding var selection: Set<String>

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 130), spacing: 8)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(options, id: \.self) { option in
                    let isSelected = selection.contains(option)
                    Button {
                        toggle(option)
                    } label: {
                        Text(option)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity)
                            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func toggle(_ option: String) {
        if selection.contains(option) {
            selection.remove(option)
        } else {
            selection.insert(option)
        }
    }
}

private struct RecipeIngredientEditorSheet: View {
    let title: String
    let draft: RecipeIngredientDraft
    let inventoryItems: [InventoryItem]
    let onSave: (RecipeIngredientDraft) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var amountText: String
    @State private var unit: UnitType
    @State private var selectedItem: InventoryItem?
    @State private var searchText = ""

    init(
        title: String,
        draft: RecipeIngredientDraft,
        inventoryItems: [InventoryItem],
        onSave: @escaping (RecipeIngredientDraft) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.title = title
        self.draft = draft
        self.inventoryItems = inventoryItems
        self.onSave = onSave
        self.onCancel = onCancel

        _name = State(initialValue: draft.displayName)
        _amountText = State(initialValue: draft.amountText)
        _unit = State(initialValue: draft.unit)
        _selectedItem = State(initialValue: draft.inventoryItem)
    }

    private var filteredItems: [InventoryItem] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return inventoryItems
        }
        return inventoryItems.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (parseDecimal(amountText) ?? 0) > 0
    }

    private var warningMessage: String? {
        guard let selectedItem else { return nil }

        if unit.family != selectedItem.baseUnit.family {
            return "\(unit.displaySymbol) cannot convert to inventory base unit \(selectedItem.baseUnit.displaySymbol)."
        }

        if unit.family == .other && unit != selectedItem.baseUnit {
            return "Other units must match exactly for deductions."
        }

        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Ingredient") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Name")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(.secondary)
                        TextField("Ingredient name", text: $name)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Base Amount")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            TextField("0", text: $amountText)
                                #if os(iOS)
                                .keyboardType(.decimalPad)
                                #endif
                            Picker("Unit", selection: $unit) {
                                ForEach(UnitType.selectableCases, id: \.self) { unit in
                                    Text(unit.displaySymbol).tag(unit)
                                }
                            }
                            .frame(maxWidth: 150)
                        }
                    }
                }

                Section("Inventory Link (Optional)") {
                    TextField("Search inventory", text: $searchText)

                    if let selectedItem {
                        HStack {
                            Label(selectedItem.name, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
                            Spacer()
                            Button("Clear") {
                                self.selectedItem = nil
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    List(filteredItems) { item in
                        Button {
                            selectedItem = item
                            if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                name = item.name
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                    Text("Base: \(item.baseUnit.displaySymbol)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selectedItem?.id == item.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(minHeight: 180)

                    if let warningMessage {
                        Label(warningMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .liquidFormChrome()
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(
                            RecipeIngredientDraft(
                                id: draft.id,
                                displayName: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                amountText: amountText,
                                unit: unit,
                                inventoryItem: selectedItem
                            )
                        )
                    }
                    .disabled(!isValid)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 620)
        #endif
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
typealias PlatformImage = NSImage
#else
import UIKit
typealias PlatformImage = UIImage
#endif
