import SwiftUI
import SwiftData

private struct RecipeEditorPresentation: Identifiable {
    let id = UUID()
    let recipe: RecipeTemplate
    let isNew: Bool
}

struct RecipeBrowserView: View {
    let selectedCategory: PrepCategory?
    var onOpenRecipe: (RecipeTemplate) -> Void = { _ in }

    @Environment(\.modelContext) private var modelContext
    @Query private var recipes: [RecipeTemplate]

    @State private var viewModel: RecipeViewModel?
    @State private var searchText = ""
    @AppStorage("recipeViewMode") private var viewMode: ViewMode = .grid

    @State private var editorPresentation: RecipeEditorPresentation?
    @State private var batchPresentation: RecipeTemplate?
    @State private var recipePendingDelete: RecipeTemplate?

    @State private var selectedAllergens: Set<String> = []
    @State private var selectedRestrictions: Set<String> = []
    @State private var showFilters = false

    enum ViewMode: String {
        case grid
        case list
    }

    init(selectedCategory: PrepCategory?, onOpenRecipe: @escaping (RecipeTemplate) -> Void = { _ in }) {
        self.selectedCategory = selectedCategory
        self.onOpenRecipe = onOpenRecipe

        if let categoryID = selectedCategory?.id {
            _recipes = Query(filter: #Predicate<RecipeTemplate> { $0.category?.id == categoryID }, sort: \.title)
        } else {
            _recipes = Query(sort: \.title)
        }
    }

    private var filteredRecipes: [RecipeTemplate] {
        guard let viewModel else { return recipes }

        return viewModel.filterRecipes(
            recipes,
            searchText: searchText,
            category: nil,
            allergens: selectedAllergens,
            restrictions: selectedRestrictions
        )
    }

    var body: some View {
        Group {
            if filteredRecipes.isEmpty {
                ContentUnavailableView(
                    "No Recipes",
                    systemImage: "fork.knife",
                    description: Text("Add a recipe to get started.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(DesignSystem.Spacing.grid_2)
            } else {
                contentByMode
            }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search recipes")
        .navigationTitle(selectedCategory?.name ?? "All Recipes")
        .toolbar { toolbarItems }
        .onAppear {
            if viewModel == nil {
                viewModel = RecipeViewModel(modelContext: modelContext)
            }
        }
        .sheet(item: $editorPresentation) { presentation in
            NavigationStack {
                RecipeEditView(recipe: presentation.recipe, isNew: presentation.isNew)
            }
            #if os(macOS)
            .frame(minWidth: 860, minHeight: 720)
            #else
            .presentationDetents([.large])
            #endif
        }
        .sheet(item: $batchPresentation) { recipe in
            BatchBuilderSheet(recipe: recipe)
            #if os(macOS)
            .frame(minWidth: 680, minHeight: 620)
            #else
            .presentationDetents([.large])
            #endif
        }
        .sheet(isPresented: $showFilters) {
            filterSheetContent
        }
        .alert("Delete Recipe?", isPresented: Binding(
            get: { recipePendingDelete != nil },
            set: { if !$0 { recipePendingDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let recipePendingDelete {
                    deleteRecipe(recipePendingDelete)
                }
                recipePendingDelete = nil
            }
        } message: {
            Text("This recipe and its batch history will be removed.")
        }
    }

    private var contentByMode: some View {
        Group {
            if viewMode == .list {
                List(filteredRecipes) { recipe in
                    recipeNavigationRow(for: recipe)
                }
                #if os(macOS)
                .onDeleteCommand {
                    if let first = filteredRecipes.first {
                        recipePendingDelete = first
                    }
                }
                .liquidListChrome()
                .safeAreaPadding(.top, DesignSystem.Spacing.grid_1)
                .safeAreaPadding(.horizontal, DesignSystem.Spacing.grid_1)
                #endif
                .listStyle(.plain)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 16)], spacing: 16) {
                        ForEach(filteredRecipes) { recipe in
                            recipeGridCell(for: recipe)
                        }
                    }
                    .padding(DesignSystem.Spacing.grid_2)
                }
                #if os(macOS)
                .safeAreaPadding(.top, DesignSystem.Spacing.grid_1)
                .safeAreaPadding(.horizontal, DesignSystem.Spacing.grid_1)
                #endif
            }
        }
    }

    @ViewBuilder
    private func recipeNavigationRow(for recipe: RecipeTemplate) -> some View {
        Button {
            onOpenRecipe(recipe)
        } label: {
            RecipeRow(recipe: recipe)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Edit Recipe") {
                openEditor(for: recipe, isNew: false)
            }
            Button("Make Batch") {
                batchPresentation = recipe
            }
            Divider()
            Button("Delete Recipe", role: .destructive) {
                recipePendingDelete = recipe
            }
        }
        .swipeActions {
            Button(role: .destructive) {
                recipePendingDelete = recipe
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        #if os(macOS)
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded { openEditor(for: recipe, isNew: false) }
        )
        #endif
    }

    @ViewBuilder
    private func recipeGridCell(for recipe: RecipeTemplate) -> some View {
        Button {
            onOpenRecipe(recipe)
        } label: {
            RecipeCard(recipe: recipe)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Edit Recipe") {
                openEditor(for: recipe, isNew: false)
            }
            Button("Make Batch") {
                batchPresentation = recipe
            }
            Divider()
            Button("Delete Recipe", role: .destructive) {
                recipePendingDelete = recipe
            }
        }
        #if os(macOS)
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded { openEditor(for: recipe, isNew: false) }
        )
        #endif
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                showFilters = true
            } label: {
                Label("Filter", systemImage: lineIconName)
            }
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                createRecipe()
            } label: {
                Label("Add Recipe", systemImage: "plus")
            }
            .keyboardShortcut("n", modifiers: [.command])
        }

        ToolbarItem(placement: .secondaryAction) {
            Picker("View Mode", selection: $viewMode) {
                Label("Grid", systemImage: "square.grid.2x2").tag(ViewMode.grid)
                Label("List", systemImage: "list.bullet").tag(ViewMode.list)
            }
            .pickerStyle(.menu)
        }
    }

    private var filterSheetContent: some View {
        NavigationStack {
            Form {
                Section("Dietary Restrictions (Must Have)") {
                    MultiSelector(label: "Restrictions", options: RecipeConstants.allRestrictions, selection: $selectedRestrictions)
                }

                Section("Allergens (Exclude)") {
                    MultiSelector(label: "Allergens", options: RecipeConstants.allAllergens, selection: $selectedAllergens)
                }

                if !selectedAllergens.isEmpty || !selectedRestrictions.isEmpty {
                    Section {
                        Button("Clear All Filters", role: .destructive) {
                            selectedAllergens.removeAll()
                            selectedRestrictions.removeAll()
                        }
                    }
                }
            }
            .navigationTitle("Filter Recipes")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showFilters = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var lineIconName: String {
        (!selectedAllergens.isEmpty || !selectedRestrictions.isEmpty)
            ? "line.3.horizontal.decrease.circle.fill"
            : "line.3.horizontal.decrease.circle"
    }

    private func createRecipe() {
        let draft = RecipeTemplate(title: "", category: selectedCategory)
        modelContext.insert(draft)
        openEditor(for: draft, isNew: true)
    }

    private func openEditor(for recipe: RecipeTemplate, isNew: Bool) {
        editorPresentation = RecipeEditorPresentation(recipe: recipe, isNew: isNew)
    }

    private func deleteRecipe(_ recipe: RecipeTemplate) {
        withAnimation(.easeInOut(duration: 0.2)) {
            modelContext.delete(recipe)
        }
        do {
            try modelContext.save()
        } catch {
            print("Failed to delete recipe: \(error)")
        }
    }
}

struct RecipeCard: View {
    let recipe: RecipeTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Color.secondary.opacity(0.1))
                .aspectRatio(4 / 3, contentMode: .fit)
                .overlay {
                    recipeImage
                }
                .clipped()

            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.title.isEmpty ? "Untitled Recipe" : recipe.title)
                    .font(.headline)
                    .lineLimit(2)

                if let category = recipe.category {
                    Text(category.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var recipeImage: some View {
        if let data = recipe.photoData, let image = RecipePlatformImage(data: data) {
            #if os(macOS)
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
            #else
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
            #endif
        } else {
            Image(systemName: "fork.knife")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var cardBackground: some View {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(uiColor: .secondarySystemBackground)
        #endif
    }
}

struct RecipeRow: View {
    let recipe: RecipeTemplate

    var body: some View {
        HStack(spacing: 12) {
            recipeThumbnail

            VStack(alignment: .leading, spacing: 2) {
                Text(recipe.title.isEmpty ? "Untitled Recipe" : recipe.title)
                    .font(.body)
                if let category = recipe.category {
                    Text(category.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var recipeThumbnail: some View {
        if let data = recipe.photoData, let image = RecipePlatformImage(data: data) {
            #if os(macOS)
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            #else
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            #endif
        } else {
            Image(systemName: "fork.knife")
                .frame(width: 42, height: 42)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

#if os(macOS)
import AppKit
typealias RecipePlatformImage = NSImage
#else
import UIKit
typealias RecipePlatformImage = UIImage
#endif
