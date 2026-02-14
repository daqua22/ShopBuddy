import SwiftUI
import SwiftData

struct PrepCategorySidebar: View {
    @Binding var selectedCategory: PrepCategory?
    @Query(sort: \PrepCategory.sortOrder) private var categories: [PrepCategory]
    @Environment(\.modelContext) private var modelContext

    @State private var showingRenameAlert = false
    @State private var categoryToRename: PrepCategory?
    @State private var renameText = ""

    @State private var showingDeleteConfirmation = false
    @State private var categoryToDelete: PrepCategory?
    @State private var showingAddCategorySheet = false
    @State private var newCategoryName = ""
    @State private var newCategoryEmoji = "🥣"

    var body: some View {
        List(selection: $selectedCategory) {
            NavigationLink(value: nil as PrepCategory?) {
                HStack(spacing: 12) {
                    Image(systemName: "book")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 20)
                    Text("All Recipes")
                        .font(DesignSystem.Typography.body)
                    Spacer()
                    Text("\(totalRecipeCount)")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .tag(nil as PrepCategory?)

            Section("Categories") {
                if categories.isEmpty {
                    ContentUnavailableView(
                        "No Categories",
                        systemImage: "folder.badge.plus",
                        description: Text("Create a recipe category to organize your recipes.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }

                ForEach(categories) { category in
                    NavigationLink(value: category) {
                        categoryRow(category)
                    }
                    .tag(category)
                    .contextMenu {
                        Button("Rename") {
                            categoryToRename = category
                            renameText = category.name
                            showingRenameAlert = true
                        }
                        Divider()
                        Button("Delete Category", role: .destructive) {
                            categoryToDelete = category
                            showingDeleteConfirmation = true
                        }
                    }
                }
                .onDelete { indexSet in
                    guard let index = indexSet.first else { return }
                    categoryToDelete = categories[index]
                    showingDeleteConfirmation = true
                }
            }
        }
        .listStyle(.sidebar)
        #if os(macOS)
        .liquidListChrome()
        .safeAreaPadding(.top, DesignSystem.Spacing.grid_1)
        .safeAreaPadding(.horizontal, DesignSystem.Spacing.grid_1)
        #endif
        .navigationTitle("Recipes")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Category", systemImage: "plus") {
                    presentAddCategorySheet()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }

            ToolbarItem(placement: .secondaryAction) {
                if selectedCategory != nil {
                    Button("Delete Category", systemImage: "trash", role: .destructive) {
                        categoryToDelete = selectedCategory
                        showingDeleteConfirmation = true
                    }
                }
            }
        }
        .alert("Rename Category", isPresented: $showingRenameAlert) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { }
            Button("Rename") {
                renameCategory()
            }
        } message: {
            Text("Enter a new name for this category.")
        }
        .alert("Delete Category?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                categoryToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let categoryToDelete {
                    deleteCategory(categoryToDelete)
                }
                categoryToDelete = nil
            }
        } message: {
            Text("Deleting a category also removes its recipes.")
        }
        .sheet(isPresented: $showingAddCategorySheet) {
            RecipeCategoryCreationSheet(
                categoryName: $newCategoryName,
                categoryEmoji: $newCategoryEmoji
            ) {
                addCategory(name: newCategoryName, emoji: newCategoryEmoji)
            }
            #if os(macOS)
            .frame(minWidth: 520, minHeight: 520)
            #endif
        }
    }

    private var totalRecipeCount: Int {
        categories.reduce(0) { $0 + $1.recipes.count }
    }

    @ViewBuilder
    private func categoryRow(_ category: PrepCategory) -> some View {
        HStack(spacing: 12) {
            Text(category.emoji)
                .font(.system(size: 16))
                .frame(width: 20)

            Text(category.name)
                .font(DesignSystem.Typography.body)

            Spacer()

            Text("\(category.recipes.count)")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func presentAddCategorySheet() {
        newCategoryName = ""
        newCategoryEmoji = "🥣"
        showingAddCategorySheet = true
    }

    private func addCategory(name: String, emoji: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let cat = PrepCategory(name: trimmedName, emoji: emoji, sortOrder: categories.count)
        modelContext.insert(cat)
        selectedCategory = cat

        do {
            try modelContext.save()
            showingAddCategorySheet = false
        } catch {
            print("Failed to add category: \(error)")
        }
    }

    private func renameCategory() {
        guard let category = categoryToRename else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        category.name = trimmed

        do {
            try modelContext.save()
        } catch {
            print("Failed to rename category: \(error)")
        }
    }

    private func deleteCategory(_ category: PrepCategory) {
        if selectedCategory?.id == category.id {
            selectedCategory = nil
        }

        modelContext.delete(category)
        do {
            try modelContext.save()
        } catch {
            print("Failed to delete category: \(error)")
        }
    }
}
