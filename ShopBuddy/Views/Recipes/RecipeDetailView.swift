import SwiftUI
import SwiftData

struct RecipeDetailView: View {
    let recipe: RecipeTemplate
    
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: RecipeViewModel?
    @State private var multiplier: Decimal = 1.0
    @State private var showingBatchBuilder = false
    @State private var showingEditSheet = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Photo
                if let data = recipe.photoData, let uiImage = UIImage(data: data) {
                    #if os(macOS)
                    Image(nsImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 300)
                        .clipped()
                    #else
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 300)
                        .clipped()
                    #endif
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(recipe.title)
                        .font(.largeTitle.bold())
                    
                    if let cat = recipe.category {
                        Label(cat.name, systemImage: "folder")
                            .foregroundStyle(.secondary)
                    }
                    
                    // Tags
                    if !recipe.allergens.isEmpty || !recipe.restrictions.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Array(recipe.allergens.sorted()), id: \.self) { allergen in
                                    Text(allergen)
                                        .font(.caption.bold())
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.red.opacity(0.1))
                                        .foregroundColor(.red)
                                        .cornerRadius(4)
                                }
                                
                                ForEach(Array(recipe.restrictions.sorted()), id: \.self) { restriction in
                                    Text(restriction)
                                        .font(.caption.bold())
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.green.opacity(0.1))
                                        .foregroundColor(.green)
                                        .cornerRadius(4)
                                }
                            }
                        }
                    }
                    
                    Divider()
                    
                    // Yield
                    HStack {
                        Label("Yields", systemImage: "scalemass")
                        Spacer()
                        Text(yieldString)
                            .bold()
                    }
                    .font(.headline)
                    .padding(.vertical, 4)
                    
                    Divider()
                    
                    // Ingredients
                    Text("Ingredients")
                        .font(.title2.bold())
                        .padding(.top, 4)
                    
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(recipe.ingredients.sorted(by: { $0.sortOrder < $1.sortOrder })) { ingredient in
                            IngredientRow(ingredient: ingredient, multiplier: multiplier, viewModel: viewModel)
                            Divider()
                        }
                    }
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(8)
                    
                    // Steps
                    Text("Instructions")
                        .font(.title2.bold())
                        .padding(.top, 10)
                    
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(recipe.steps.sorted(by: { $0.sortOrder < $1.sortOrder })) { step in
                            HStack(alignment: .top) {
                                Text("\(step.sortOrder + 1)")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(width: 24, height: 24)
                                    .background(Circle().fill(Color.accentColor))
                                
                                Text(step.text)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle(recipe.title)
        .onAppear {
            if viewModel == nil {
                viewModel = RecipeViewModel(modelContext: modelContext)
            }
        }
        #if os(macOS)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                scalingControls
                
                Button(action: { showingEditSheet = true }) {
                    Label("Edit", systemImage: "pencil")
                }
                
                Button(action: { showingBatchBuilder = true }) {
                    Label("Make Batch", systemImage: "play.fill")
                }
                .keyboardShortcut("b", modifiers: .command)
            }
        }
        #else
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack {
                    Button("Edit") { showingEditSheet = true }
                    Button("Make Batch") { showingBatchBuilder = true }
                }
            }
            ToolbarItem(placement: .bottomBar) {
                scalingControls
            }
        }
        #endif
        .sheet(isPresented: $showingBatchBuilder) {
            BatchBuilderSheet(recipe: recipe)
        }
        .sheet(isPresented: $showingEditSheet) {
            NavigationStack {
                RecipeEditView(recipe: recipe, isNew: false)
            }
        }
    }
    
    // MARK: - Subviews
    
    var scalingControls: some View {
        HStack(spacing: 12) {
            Button(action: { if multiplier > 0.25 { multiplier -= 0.25 } }) {
                Image(systemName: "minus")
            }
            
            Text("\(multiplier, format: .number.precision(.fractionLength(2)))x")
                .font(.headline)
                .monospacedDigit()
                .frame(minWidth: 50)
            
            Button(action: { multiplier += 0.25 }) {
                Image(systemName: "plus")
            }
            
            // Preset Pucks
            HStack(spacing: 4) {
               presetButton(1.0)
               presetButton(2.0)
               presetButton(4.0)
            }
        }
    }
    
    func presetButton(_ value: Decimal) -> some View {
        Button("\(NSDecimalNumber(decimal: value).intValue)x") {
            withAnimation { multiplier = value }
        }
        .font(.caption.bold())
        .buttonStyle(.bordered)
        .tint(multiplier == value ? .accentColor : .secondary)
    }
    
    var yieldString: String {
        let amount = recipe.defaultYieldAmount * multiplier
        return "\(viewModel?.formattedAmount(amount) ?? "\(amount)") \(recipe.defaultYieldUnit.rawValue)"
    }
}

struct IngredientRow: View {
    let ingredient: RecipeIngredient
    let multiplier: Decimal
    var viewModel: RecipeViewModel?
    
    var body: some View {
        HStack {
            Text(ingredient.displayName)
                .font(.body)
            Spacer()
            
            let amount = ingredient.baseAmount * multiplier
            let formatted = viewModel?.formattedAmount(amount) ?? "\(amount)"
            
            Text("\(formatted) \(ingredient.unit.rawValue)")
                .font(.body.bold())
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
