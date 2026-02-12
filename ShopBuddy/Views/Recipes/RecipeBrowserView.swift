import SwiftUI
import SwiftData

struct RecipeBrowserView: View {
    var selectedCategory: PrepCategory?
    @Environment(\.modelContext) private var modelContext
    @Query private var recipes: [RecipeTemplate]
    
    @State private var viewModel: RecipeViewModel?
    @State private var searchText = ""
    @AppStorage("recipeViewMode") private var viewMode: ViewMode = .grid
    
    @State private var showingAddRecipe = false
    @State private var newRecipe: RecipeTemplate?
    @State private var editingRecipe: RecipeTemplate?
    
    // Filter State
    @State private var selectedAllergens: Set<String> = []
    @State private var selectedRestrictions: Set<String> = []
    @State private var showFilters = false
    
    enum ViewMode: String {
        case grid, list
    }
    
    init(selectedCategory: PrepCategory?) {
        self.selectedCategory = selectedCategory
        let categoryId = selectedCategory?.id
        
        if let id = categoryId {
            _recipes = Query(filter: #Predicate<RecipeTemplate> { $0.category?.id == id }, sort: \.title)
        } else {
            _recipes = Query(sort: \.title)
        }
    }
    
    var filteredRecipes: [RecipeTemplate] {
        guard let vm = viewModel else { return recipes }
        
        // Note: Query already handles Category if passed in init.
        // But if filtering logic in VM expects to filter by category, we should be careful avoiding double filtering 
        // or just pass nil for category if we trust Query.
        // However, standardizing on VM filtering is good for "Code Quality".
        // But Query is more efficient for initial fetch.
        // Let's rely on Query for initial fetch (category) and VM for memory filtering.
        
        return vm.filterRecipes(
            recipes,
            searchText: searchText,
            category: nil, // Query handles this
            allergens: selectedAllergens,
            restrictions: selectedRestrictions
        )
    }
    
    var body: some View {
        ZStack {
            if filteredRecipes.isEmpty {
                ContentUnavailableView("No Recipes", systemImage: "fork.knife", description: Text("Add a recipe to get started."))
            } else {
                if viewMode == .list {
                    List(filteredRecipes) { recipe in
                        NavigationLink(value: recipe) {
                            RecipeRow(recipe: recipe)
                                #if os(macOS)
                                .onTapGesture(count: 2) {
                                    editRecipe(recipe)
                                }
                                #endif
                                .contextMenu {
                                    Button("Edit Recipe") { editRecipe(recipe) }
                                    Button("Make Batch") { /* TODO: Trigger Make Batch */ }
                                }
                        }
                    }
                    .listStyle(.plain)
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16)], spacing: 16) {
                            ForEach(filteredRecipes) { recipe in
                                NavigationLink(value: recipe) {
                                    RecipeCard(recipe: recipe)
                                        #if os(macOS)
                                        .onTapGesture(count: 2) {
                                            editRecipe(recipe)
                                        }
                                        #endif
                                        .contextMenu {
                                            Button("Edit Recipe") { editRecipe(recipe) }
                                            Button("Make Batch") { /* TODO: Trigger Make Batch */ }
                                        }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                    }
                }
            }
        }
        .searchable(text: $searchText, placement: .automatic, prompt: "Search recipes...")
        .navigationTitle(selectedCategory?.name ?? "All Recipes")
        .toolbar {
            toolbarItems
        }
        .onAppear {
            if viewModel == nil {
                viewModel = RecipeViewModel(modelContext: modelContext)
            }
        }
        .sheet(isPresented: $showFilters) {
            filterSheetContent
        }
            }
        }
        .sheet(item: $editingRecipe) { recipe in
            NavigationStack {
                RecipeEditView(recipe: recipe, isNew: false)
            }
            .presentationDetents([.large])
        }
    }

    @ToolbarContentBuilder
    var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button(action: { showFilters = true }) {
                Label("Filter", systemImage: lineIconName)
            }
        }
        
        ToolbarItem(placement: .primaryAction) {
            Button("Add Recipe", systemImage: "plus") {
                let new = RecipeTemplate(title: "")
                if let selectedCategory {
                    new.category = selectedCategory
                }
                modelContext.insert(new)
                newRecipe = new
                showingAddRecipe = true
            }
        }
        
        ToolbarItem(placement: .secondaryAction) {
            Picker("View Mode", selection: $viewMode) {
                Label("Grid", systemImage: "square.grid.2x2").tag(ViewMode.grid)
                Label("List", systemImage: "list.bullet").tag(ViewMode.list)
            }
            .pickerStyle(.inline)
        }
    }
    
    var filterSheetContent: some View {
        NavigationStack {
            Form {
                Section(header: Text("Dietary Restrictions (Must Have)")) {
                    MultiSelector(label: "Restrictions", options: RecipeConstants.allRestrictions, selection: $selectedRestrictions)
                }
                
                Section(header: Text("Allergens (Exclude)")) {
                    MultiSelector(label: "Allergens", options: RecipeConstants.allAllergens, selection: $selectedAllergens)
                }
                
                if !selectedAllergens.isEmpty || !selectedRestrictions.isEmpty {
                    Section {
                        Button("Clear All Filters") {
                            selectedAllergens.removeAll()
                            selectedRestrictions.removeAll()
                        }
                        .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Filter Recipes")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showFilters = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    var lineIconName: String {
        return (!selectedAllergens.isEmpty || !selectedRestrictions.isEmpty) ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle"
    }

    private func editRecipe(_ recipe: RecipeTemplate) {
        editingRecipe = recipe
    }
}

// MARK: - Components
struct RecipeCard: View {
    let recipe: RecipeTemplate
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Photo Placeholder
            Rectangle()
                .fill(Color.secondary.opacity(0.1))
                .aspectRatio(4/3, contentMode: .fit)
                .overlay {
                    if let data = recipe.photoData, let uiImage = UIImage(data: data) {
                        #if os(macOS)
                        Image(nsImage: uiImage)
                            .resizable()
                            .scaledToFill()
                        #else
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                        #endif
                    } else {
                        Image(systemName: "fork.knife")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
                }
                .clipped()
            
            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.title)
                    .font(.headline)
                    .lineLimit(2)
                
                if let cat = recipe.category {
                    Text(cat.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
        }
        .background(Color(NSColor.controlBackgroundColor)) // Adaptive background
        .cornerRadius(12)
        .shadow(radius: 2, y: 1)
    }
}

struct RecipeRow: View {
    let recipe: RecipeTemplate
    
    var body: some View {
        HStack {
            if let data = recipe.photoData, let uiImage = UIImage(data: data) {
                #if os(macOS)
                Image(nsImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .cornerRadius(6)
                #else
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .cornerRadius(6)
                #endif
            } else {
                Image(systemName: "fork.knife")
                    .frame(width: 40, height: 40)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(6)
            }
            
            VStack(alignment: .leading) {
                Text(recipe.title)
                    .font(.body)
                if let cat = recipe.category {
                    Text(cat.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

#if os(macOS)
typealias UIImage = NSImage
#endif
