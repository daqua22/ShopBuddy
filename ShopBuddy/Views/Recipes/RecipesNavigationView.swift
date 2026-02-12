import SwiftUI
import SwiftData

struct RecipesNavigationView: View {
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var selectedCategory: PrepCategory?
    
    // For iPhone stack navigation
    @State private var navigationPath = NavigationPath()
    
    var body: some View {
        #if os(macOS)
        splitView
        #else
        if UIDevice.current.userInterfaceIdiom == .pad {
            splitView
        } else {
            stackView
        }
        #endif
    }
    
    var splitView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            PrepCategorySidebar(selectedCategory: $selectedCategory)
        } detail: {
            // If no category selected, show "All" or empty state?
            // For now, Browser handles filtering internally or via binding
            RecipeBrowserView(selectedCategory: selectedCategory)
        }
        .navigationTitle("Recipes")
    }
    
    var stackView: some View {
        NavigationStack(path: $navigationPath) {
            RecipeBrowserView(selectedCategory: nil)
            .navigationDestination(for: RecipeTemplate.self) { recipe in
                RecipeDetailView(recipe: recipe)
            }
        }
    }
}
