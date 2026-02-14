import SwiftUI
import SwiftData

struct RecipeDetailView: View {
    let recipe: RecipeTemplate
    var immersiveMode: Bool = false
    var onClose: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var scaleViewModel: RecipeScaleViewModel
    @State private var multiplierText: String
    @State private var isAnchorEditMode: Bool = false

    @State private var completedStepIDs: Set<UUID> = []
    @State private var linkedInventoryItem: InventoryItem?

    @State private var showingBatchBuilder = false
    @State private var showingEditSheet = false
    @State private var showingDeleteConfirmation = false

    private var sortedSteps: [RecipeStep] {
        recipe.steps.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var recentBatches: [RecipeBatch] {
        Array(recipe.batches.sorted { $0.madeAt > $1.madeAt }.prefix(5))
    }

    private var finalYieldAmount: Decimal {
        recipe.defaultYieldAmount * scaleViewModel.multiplier
    }

    init(recipe: RecipeTemplate, immersiveMode: Bool = false, onClose: (() -> Void)? = nil) {
        self.recipe = recipe
        self.immersiveMode = immersiveMode
        self.onClose = onClose
        _scaleViewModel = State(initialValue: RecipeScaleViewModel(ingredients: recipe.ingredients))
        _multiplierText = State(initialValue: "1")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: DesignSystem.Spacing.grid_2) {
                headerCard
                ingredientsCard
                stepsCard
                notesCard

                if !recentBatches.isEmpty {
                    recentBatchesCard
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.grid_2)
            .padding(.bottom, DesignSystem.Spacing.grid_3)
            .padding(.top, DesignSystem.Spacing.grid_1)
            .readableContent(maxWidth: 920)
        }
        .liquidBackground()
        .safeAreaInset(edge: .top) {
            batchControlsBar
                .padding(.horizontal, DesignSystem.Spacing.grid_2)
                .padding(.top, DesignSystem.Spacing.grid_1)
        }
        .navigationTitle(recipe.title.isEmpty ? "Recipe" : recipe.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            toolbarItems
        }
        .sheet(isPresented: $showingBatchBuilder) {
            BatchBuilderSheet(recipe: recipe, initialMultiplier: scaleViewModel.multiplier)
                #if os(macOS)
                .frame(minWidth: 680, minHeight: 620)
                #else
                .presentationDetents([.large])
                #endif
        }
        .sheet(isPresented: $showingEditSheet) {
            NavigationStack {
                RecipeEditView(recipe: recipe, isNew: false)
            }
            #if os(macOS)
            .frame(minWidth: 860, minHeight: 720)
            #else
            .presentationDetents([.large])
            #endif
        }
        .sheet(item: $linkedInventoryItem) { item in
            NavigationStack {
                Form {
                    Section("Item") {
                        Text(item.name)
                        Text("On hand: \(formatDecimalForUI(item.onHandBase)) \(item.baseUnit.displaySymbol)")
                        Text("Par: \(formatDecimalForUI(item.parLevel)) \(item.baseUnit.displaySymbol)")
                    }

                    if let vendor = item.vendor, !vendor.isEmpty {
                        Section("Vendor") {
                            Text(vendor)
                        }
                    }

                    if let notes = item.notes, !notes.isEmpty {
                        Section("Notes") {
                            Text(notes)
                        }
                    }
                }
                .navigationTitle("Inventory Item")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") {
                            linkedInventoryItem = nil
                        }
                    }
                }
            }
            #if os(macOS)
            .frame(minWidth: 440, minHeight: 420)
            #endif
        }
        .alert("Delete Recipe?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteRecipe()
            }
        } message: {
            Text("This recipe and its batch history will be removed.")
        }
        .onAppear {
            multiplierText = formatDecimalForUI(scaleViewModel.multiplier)
        }
        .onChange(of: scaleViewModel.multiplier) { _, newValue in
            multiplierText = formatDecimalForUI(newValue)
        }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        if immersiveMode {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    closeDetail()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                showingEditSheet = true
            } label: {
                Label("Edit", systemImage: "pencil")
            }

            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.grid_2) {
            if let data = recipe.photoData,
               let image = RecipeDetailPlatformImage(data: data) {
                recipeImage(image)
                    .frame(maxWidth: .infinity)
                    .frame(height: 240)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(recipe.title.isEmpty ? "Untitled Recipe" : recipe.title)
                    .font(DesignSystem.Typography.title)

                if let category = recipe.category {
                    Label(category.name, systemImage: "folder")
                        .font(DesignSystem.Typography.callout)
                        .foregroundStyle(.secondary)
                }

                if !recipe.allergens.isEmpty || !recipe.restrictions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(recipe.allergens.sorted(), id: \.self) { allergen in
                                tagPill(label: allergen, color: .red)
                            }

                            ForEach(recipe.restrictions.sorted(), id: \.self) { restriction in
                                tagPill(label: restriction, color: .green)
                            }
                        }
                    }
                }
            }
        }
        .padding(DesignSystem.Spacing.grid_2)
        .glassCard()
    }

    private var batchControlsBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    presetMultiplierButton(0.5)
                    presetMultiplierButton(1)
                    presetMultiplierButton(2)
                    presetMultiplierButton(3)
                    anchorModeButton
                }
            }

            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    TextField("Multiplier", text: $multiplierText)
                        .frame(width: 72)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .onSubmit {
                            applyMultiplierText()
                        }

                    Stepper("", value: multiplierStepperBinding, in: 0.1...100, step: 0.1)
                        .labelsHidden()
                        .frame(width: 42)
                }

                Divider()
                    .frame(height: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Final Yield")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(.secondary)
                    Text("\(formatDecimalForUI(finalYieldAmount)) \(recipe.defaultYieldUnit.displaySymbol)")
                        .font(DesignSystem.Typography.headline)
                        .monospacedDigit()
                }

                if isAnchorEditMode, let anchorName = scaleViewModel.anchorIngredientName() {
                    Divider()
                        .frame(height: 24)

                    Text("Scaling from: \(anchorName)")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button("Restore") {
                    scaleViewModel.restoreToTemplate()
                }
                .buttonStyle(.bordered)
                .disabled(!canRestore)

                Button {
                    showingBatchBuilder = true
                } label: {
                    Label("Make Batch", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(DesignSystem.Spacing.grid_2)
        .glassCard()
    }

    private var ingredientsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ingredients")
                .font(DesignSystem.Typography.title3)

            if scaleViewModel.ingredients.isEmpty {
                Text("No ingredients in this recipe.")
                    .font(DesignSystem.Typography.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(scaleViewModel.ingredients) { ingredient in
                        IngredientRowView(
                            ingredient: ingredient,
                            scaledAmount: scaleViewModel.displayedAmount(for: ingredient),
                            amountText: bindingForAmount(of: ingredient),
                            isAnchorEditingEnabled: isAnchorEditMode,
                            isAnchor: scaleViewModel.anchorIngredientID == ingredient.id,
                            errorMessage: scaleViewModel.errorMessage(for: ingredient),
                            onTapLinkedItem: { item in
                                linkedInventoryItem = item
                            }
                        )
                        if ingredient.id != scaleViewModel.ingredients.last?.id {
                            Divider()
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium, style: .continuous))
            }
        }
        .padding(DesignSystem.Spacing.grid_2)
        .glassCard()
    }

    private var canRestore: Bool {
        scaleViewModel.anchorIngredientID != nil || scaleViewModel.multiplier != 1.0 || !scaleViewModel.editedAmounts.isEmpty
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

    private var stepsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Steps")
                .font(DesignSystem.Typography.title3)

            if sortedSteps.isEmpty {
                Text("No preparation steps yet.")
                    .font(DesignSystem.Typography.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(sortedSteps) { step in
                        StepRowView(
                            step: step,
                            isCompleted: completedStepIDs.contains(step.id),
                            onToggle: {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    toggleStep(step.id)
                                }
                            }
                        )
                    }
                }
            }
        }
        .padding(DesignSystem.Spacing.grid_2)
        .glassCard()
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Notes")
                .font(DesignSystem.Typography.title3)

            if let notes = recipe.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(notes)
                    .font(DesignSystem.Typography.body)
            } else {
                Text("No notes for this recipe.")
                    .font(DesignSystem.Typography.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(DesignSystem.Spacing.grid_2)
        .glassCard()
    }

    private var recentBatchesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent Batches")
                .font(DesignSystem.Typography.title3)

            ForEach(recentBatches, id: \.id) { batch in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(batch.madeAt.formatted(date: .abbreviated, time: .shortened))
                            .font(DesignSystem.Typography.callout)
                        Text("\(formatDecimalForUI(batch.finalYieldAmount)) \(batch.finalYieldUnit.displaySymbol)")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(formatDecimalForUI(batch.scaleMultiplier))x")
                        .font(DesignSystem.Typography.callout)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                if batch.id != recentBatches.last?.id {
                    Divider()
                }
            }
        }
        .padding(DesignSystem.Spacing.grid_2)
        .glassCard()
    }

    private func presetMultiplierButton(_ value: Decimal) -> some View {
        Button("\(formatDecimalForUI(value))x") {
            setMultiplier(value)
        }
        .buttonStyle(.bordered)
        .tint(scaleViewModel.multiplier == value ? .accentColor : .secondary)
    }

    private var anchorModeButton: some View {
        Button(isAnchorEditMode ? "Anchor On" : "Anchor") {
            setAnchorEditMode(!isAnchorEditMode)
        }
        .buttonStyle(.bordered)
        .tint(isAnchorEditMode ? .accentColor : .secondary)
    }

    private var multiplierStepperBinding: Binding<Double> {
        Binding<Double>(
            get: { NSDecimalNumber(decimal: scaleViewModel.multiplier).doubleValue },
            set: { newValue in
                setMultiplier(Decimal(string: String(format: "%.2f", newValue), locale: Locale(identifier: "en_US_POSIX")) ?? 1)
            }
        )
    }

    private func setMultiplier(_ value: Decimal) {
        let clamped = min(max(value, Decimal(string: "0.1", locale: Locale(identifier: "en_US_POSIX")) ?? 0.1), 100)
        scaleViewModel.setMultiplierManually(clamped)
    }

    private func setAnchorEditMode(_ enabled: Bool) {
        isAnchorEditMode = enabled
        if !enabled {
            scaleViewModel.setMultiplierManually(scaleViewModel.multiplier)
        }
    }

    private func applyMultiplierText() {
        guard let parsed = parseDecimal(multiplierText), parsed > 0 else {
            multiplierText = formatDecimalForUI(scaleViewModel.multiplier)
            return
        }
        setMultiplier(parsed)
    }

    private func toggleStep(_ id: UUID) {
        if completedStepIDs.contains(id) {
            completedStepIDs.remove(id)
        } else {
            completedStepIDs.insert(id)
        }
    }

    private func closeDetail() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    private func deleteRecipe() {
        withAnimation(.easeInOut(duration: 0.2)) {
            modelContext.delete(recipe)
        }
        do {
            try modelContext.save()
            closeDetail()
        } catch {
            print("Failed to delete recipe: \(error)")
        }
    }

    @ViewBuilder
    private func recipeImage(_ image: RecipeDetailPlatformImage) -> some View {
        #if os(macOS)
        Image(nsImage: image)
            .resizable()
            .scaledToFill()
        #else
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
        #endif
    }

    private func tagPill(label: String, color: Color) -> some View {
        Text(label)
            .font(DesignSystem.Typography.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.14))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

struct IngredientRowView: View {
    let ingredient: RecipeIngredient
    let scaledAmount: Decimal
    @Binding var amountText: String
    let isAnchorEditingEnabled: Bool
    let isAnchor: Bool
    let errorMessage: String?
    var onTapLinkedItem: (InventoryItem) -> Void

    private enum StockState {
        case ok
        case lowStock(String)
        case insufficient(String)
        case unitMismatch(String)

        var color: Color {
            switch self {
            case .ok:
                return .secondary
            case .lowStock:
                return .orange
            case .insufficient, .unitMismatch:
                return .red
            }
        }

        var icon: String {
            switch self {
            case .ok:
                return "checkmark.circle"
            case .lowStock:
                return "exclamationmark.triangle"
            case .insufficient:
                return "xmark.octagon"
            case .unitMismatch:
                return "arrow.triangle.2.circlepath"
            }
        }

        var message: String {
            switch self {
            case .ok:
                return ""
            case let .lowStock(message), let .insufficient(message), let .unitMismatch(message):
                return message
            }
        }
    }

    private var rowState: StockState {
        guard let linkedItem = ingredient.inventoryItemRef else {
            return .ok
        }

        guard let requiredInBase = convert(amount: scaledAmount, from: ingredient.unit, to: linkedItem.baseUnit) else {
            return .unitMismatch("Cannot convert \(ingredient.unit.displaySymbol) to \(linkedItem.baseUnit.displaySymbol).")
        }

        if linkedItem.onHandBase < requiredInBase {
            return .insufficient(
                "Need \(formatDecimalForUI(requiredInBase)) \(linkedItem.baseUnit.displaySymbol), have \(formatDecimalForUI(linkedItem.onHandBase)) \(linkedItem.baseUnit.displaySymbol)."
            )
        }

        if linkedItem.onHandBase <= linkedItem.parLevel {
            return .lowStock(
                "Low stock: \(formatDecimalForUI(linkedItem.onHandBase)) \(linkedItem.baseUnit.displaySymbol) on hand."
            )
        }

        return .ok
    }

    var body: some View {
        rowContent
        .padding(.vertical, 10)
        .padding(.horizontal, 2)
    }

    private var rowContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ingredient.displayName)
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(.primary)

                    if let linkedItem = ingredient.inventoryItemRef {
                        Text("Linked: \(linkedItem.name)")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                HStack(spacing: 8) {
                    if isAnchorEditingEnabled {
                        TextField("0", text: $amountText)
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(.roundedBorder)
                            .font(DesignSystem.Typography.headline)
                            .monospacedDigit()
                            .frame(width: 100)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                    } else {
                        Text(formatDecimalForUI(scaledAmount))
                            .font(DesignSystem.Typography.headline)
                            .monospacedDigit()
                            .frame(width: 100, alignment: .trailing)
                            .foregroundStyle(.primary)
                    }

                    Text(ingredient.unit.displaySymbol)
                        .font(DesignSystem.Typography.callout)
                        .foregroundStyle(.secondary)

                    if let linkedItem = ingredient.inventoryItemRef {
                        Button {
                            onTapLinkedItem(linkedItem)
                        } label: {
                            Image(systemName: "arrow.up.right.square")
                                .font(.callout)
                        }
                        .buttonStyle(.plain)
                        .help("Open linked inventory item")
                    }
                }
            }

            if isAnchorEditingEnabled && isAnchor {
                Text("Anchor")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(Color.accentColor)
            }

            if isAnchorEditingEnabled, let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(.orange)
            }

            if case .ok = rowState {
                EmptyView()
            } else {
                HStack(spacing: 6) {
                    Image(systemName: rowState.icon)
                    Text(rowState.message)
                        .lineLimit(2)
                }
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(rowState.color)
            }
        }
    }
}

struct StepRowView: View {
    let step: RecipeStep
    let isCompleted: Bool
    var onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isCompleted ? Color.accentColor : Color.secondary)
                    .padding(.top, 1)

                Text(step.text)
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(isCompleted ? .secondary : .primary)
                    .strikethrough(isCompleted)
                    .multilineTextAlignment(.leading)

                Spacer()
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#if os(macOS)
import AppKit
typealias RecipeDetailPlatformImage = NSImage
#else
import UIKit
typealias RecipeDetailPlatformImage = UIImage
#endif
