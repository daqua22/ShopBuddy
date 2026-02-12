import SwiftUI
import SwiftData

struct PrepCategorySidebar: View {
    @Binding var selectedCategory: PrepCategory?
    @Query(sort: \PrepCategory.sortOrder) private var categories: [PrepCategory]
    @Environment(\.modelContext) private var modelContext
    
    @State private var showingRenameAlert = false
    @State private var categoryToRename: PrepCategory?
    @State private var renameText = ""
    
    var body: some View {
        List(selection: $selectedCategory) {
            NavigationLink(value: nil as PrepCategory?) {
               Label("All Recipes", systemImage: "book")
            }
            .tag(nil as PrepCategory?)
            
            Section("Categories") {
                ForEach(categories) { category in
                    NavigationLink(value: category) {
                        Label {
                            Text(category.name)
                        } icon: {
                            Text(category.emoji)
                        }
                    }
                    .tag(category)
                    .contextMenu {
                        Button("Rename") {
                            categoryToRename = category
                            renameText = category.name
                            showingRenameAlert = true
                        }
                        Button("Delete", role: .destructive) {
                            modelContext.delete(category)
                        }
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        modelContext.delete(categories[index])
                    }
                }
            }
        }
        .navigationTitle("Recipes")
        .toolbar {
            Button("Add Category", systemImage: "plus") {
                let cat = PrepCategory(name: "New Category")
                modelContext.insert(cat)
            }
        }
        .alert("Rename Category", isPresented: $showingRenameAlert) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { }
            Button("Rename") {
                if let category = categoryToRename {
                    category.name = renameText
                }
            }
        } message: {
            Text("Enter a new name for this category.")
        }
    }
}
