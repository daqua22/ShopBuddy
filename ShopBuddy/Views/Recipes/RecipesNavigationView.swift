import SwiftUI
import SwiftData

struct RecipesNavigationView: View {
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var selectedCategory: PrepCategory?
    @State private var immersiveRecipe: RecipeTemplate?

    var body: some View {
        #if os(macOS)
        macContainer
        #else
        if UIDevice.current.userInterfaceIdiom == .pad {
            splitView
                .fullScreenCover(item: $immersiveRecipe) { recipe in
                    immersiveDetail(for: recipe)
                }
        } else {
            stackView
                .fullScreenCover(item: $immersiveRecipe) { recipe in
                    immersiveDetail(for: recipe)
                }
        }
        #endif
    }

    #if os(macOS)
    private var macContainer: some View {
        ZStack {
            splitView

            if let immersiveRecipe {
                immersiveDetail(for: immersiveRecipe)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(2)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: immersiveRecipe?.id)
    }
    #endif

    private var splitView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            PrepCategorySidebar(selectedCategory: $selectedCategory)
                #if os(macOS)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
                #endif
        } detail: {
            RecipeBrowserView(selectedCategory: selectedCategory, onOpenRecipe: openRecipe)
        }
        #if os(macOS)
        .safeAreaPadding(.top, DesignSystem.Spacing.grid_1)
        #else
        .navigationTitle("Recipes")
        #endif
    }

    private var stackView: some View {
        NavigationStack {
            RecipeBrowserView(selectedCategory: nil, onOpenRecipe: openRecipe)
        }
    }

    private func openRecipe(_ recipe: RecipeTemplate) {
        immersiveRecipe = recipe
    }

    private func closeRecipeDetail() {
        immersiveRecipe = nil
    }

    @ViewBuilder
    private func immersiveDetail(for recipe: RecipeTemplate) -> some View {
        NavigationStack {
            RecipeDetailView(
                recipe: recipe,
                immersiveMode: true,
                onClose: closeRecipeDetail
            )
        }
        .background(DesignSystem.LiquidBackdrop().ignoresSafeArea())
    }
}
