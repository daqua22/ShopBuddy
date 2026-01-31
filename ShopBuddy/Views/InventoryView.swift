import SwiftUI
import SwiftData

struct InventoryView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \InventoryCategory.name) private var categories: [InventoryCategory]
    
    @State private var showingAddCategory = false
    @State private var newCategoryName = ""

    var body: some View {
        NavigationStack {
            List {
                if categories.isEmpty {
                    ContentUnavailableView("No Categories", systemImage: "folder.badge.plus", description: Text("Managers can add categories like 'Weekly' or 'Monthly'"))
                }
                
                ForEach(categories) { category in
                    NavigationLink(destination: LocationListView(category: category)) {
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundColor(.accentColor)
                            Text(category.name)
                                .font(.headline)
                        }
                        .padding(.vertical, 8)
                    }
                }
                .onDelete(perform: deleteCategory)
            }
            .navigationTitle("Inventory")
            .toolbar {
                if coordinator.isManager {
                    ToolbarItem(placement: .primaryAction) {
                        Button { showingAddCategory = true } label: { Image(systemName: "plus") }
                    }
                    ToolbarItem(placement: .topBarLeading) { EditButton() }
                }
            }
            .alert("New Category", isPresented: $showingAddCategory) {
                TextField("Category Name (e.g. Weekly)", text: $newCategoryName)
                Button("Cancel", role: .cancel) { newCategoryName = "" }
                Button("Create") {
                    let cat = InventoryCategory(name: newCategoryName)
                    modelContext.insert(cat)
                    newCategoryName = ""
                }
            }
        }
    }
    
    private func deleteCategory(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(categories[index])
        }
    }
}

// MARK: - Location List
struct LocationListView: View {
    var category: InventoryCategory
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var modelContext
    @State private var showingAddLocation = false
    @State private var newLocationName = ""

    var body: some View {
        List {
            if category.locations.isEmpty {
                ContentUnavailableView("No Locations", systemImage: "mappin.and.ellipse", description: Text("Add locations like 'Bar Fridge' to this category"))
            }
            
            ForEach(category.locations.sorted(by: { $0.name < $1.name })) { location in
                NavigationLink(destination: ItemListView(location: location)) {
                    HStack {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundColor(.secondary)
                        Text(location.name)
                    }
                }
            }
            .onDelete(perform: deleteLocation)
        }
        .navigationTitle(category.name)
        .toolbar {
            if coordinator.isManager {
                Button { showingAddLocation = true } label: { Image(systemName: "plus") }
            }
        }
        .alert("New Location", isPresented: $showingAddLocation) {
            TextField("Location Name", text: $newLocationName)
            Button("Cancel", role: .cancel) { newLocationName = "" }
            Button("Add") {
                let loc = InventoryLocation(name: newLocationName)
                loc.category = category
                category.locations.append(loc)
                newLocationName = ""
            }
        }
    }
    
    private func deleteLocation(at offsets: IndexSet) {
        for index in offsets {
            let sorted = category.locations.sorted(by: { $0.name < $1.name })
            modelContext.delete(sorted[index])
        }
    }
}

// MARK: - Item List
struct ItemListView: View {
    var location: InventoryLocation
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var modelContext
    @State private var showingAddItem = false

    var body: some View {
        List {
            ForEach(location.items.sorted(by: { $0.name < $1.name })) { item in
                InventoryItemRow(item: item)
            }
            .onDelete(perform: deleteItem)
        }
        .navigationTitle(location.name)
        .toolbar {
            if coordinator.isManager {
                Button { showingAddItem = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showingAddItem) {
            AddInventoryItemView(location: location)
        }
    }
    
    private func deleteItem(at offsets: IndexSet) {
        for index in offsets {
            let sorted = location.items.sorted(by: { $0.name < $1.name })
            modelContext.delete(sorted[index])
        }
    }
}

// MARK: - Inventory Item Row (With Smart Steppers)
struct InventoryItemRow: View {
    @Bindable var item: InventoryItem
    @Environment(AppCoordinator.self) private var coordinator
    @Query private var settings: [AppSettings]
    
    private var canEdit: Bool {
        coordinator.isManager || (settings.first?.allowEmployeeInventoryEdit ?? false)
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.headline)
                Text(item.unitType)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if canEdit {
                HStack(spacing: 12) {
                    Button { updateLevel(by: -1) } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.title2)
                            .foregroundColor(.red)
                    }
                    
                    Text(formatValue(item.stockLevel))
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 40)
                    
                    Button { updateLevel(by: 1) } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundColor(.green)
                    }
                }
                .buttonStyle(.borderless)
            } else {
                Text(formatValue(item.stockLevel))
                    .font(.headline)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func updateLevel(by direction: Double) {
        // Step check: if stock or par has decimals, step by 0.1
        let isDecimal = item.parLevel.truncatingRemainder(dividingBy: 1) != 0 ||
                        item.stockLevel.truncatingRemainder(dividingBy: 1) != 0
        
        let step = isDecimal ? 0.1 : 1.0
        item.stockLevel = max(0, item.stockLevel + (direction * step))
    }
    
    private func formatValue(_ val: Double) -> String {
        val.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", val) : String(format: "%.1f", val)
    }
}

// MARK: - Add Item View
struct AddInventoryItemView: View {
    var location: InventoryLocation
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var name = ""
    @State private var par = ""
    @State private var unit = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Item Name", text: $name)
                TextField("PAR Level", text: $par).keyboardType(.decimalPad)
                TextField("Unit (e.g. Bottles, kg)", text: $unit)
            }
            .navigationTitle("Add Item")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let newItem = InventoryItem(name: name, stockLevel: Double(par) ?? 0, parLevel: Double(par) ?? 0, unitType: unit)
                        newItem.location = location
                        location.items.append(newItem)
                        dismiss()
                    }
                    .disabled(name.isEmpty || par.isEmpty)
                }
            }
        }
    }
}
