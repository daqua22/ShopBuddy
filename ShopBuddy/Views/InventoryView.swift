import SwiftUI
import SwiftData

struct InventoryView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \InventoryCategory.name) private var categories: [InventoryCategory]
    
    @State private var showingAddCategory = false
    @State private var newCategoryName = ""
    @State private var newCategoryEmoji = "📦"
    @State private var editingCategory: InventoryCategory?

    var body: some View {
        NavigationStack {
            List {
                if categories.isEmpty {
                    ContentUnavailableView("No Categories", systemImage: "folder.badge.plus", description: Text("Managers can add categories like 'Weekly' or 'Monthly'"))
                }
                
                ForEach(categories) { category in
                    NavigationLink(destination: LocationListView(category: category)) {
                        HStack(spacing: 12) {
                            // Emoji with long press to edit
                            Text(category.emoji)
                                .font(.system(size: 32))
                                .onLongPressGesture {
                                    if coordinator.isManager {
                                        editingCategory = category
                                    }
                                }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(category.name)
                                    .font(.headline)
                                    .foregroundColor(DesignSystem.Colors.primary)
                                
                                Text("\(category.locationCount) locations • \(category.totalItemCount) items")
                                    .font(.caption)
                                    .foregroundColor(DesignSystem.Colors.secondary.opacity(0.7))
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
                .onDelete(perform: deleteCategory)
            }
            .navigationTitle("Inventory")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if coordinator.isManager {
                        EditButton()
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    if coordinator.isManager {
                        Button { showingAddCategory = true } label: { Image(systemName: "plus") }
                    }
                }
            }
            .sheet(isPresented: $showingAddCategory) {
                AddCategorySheet(categoryName: $newCategoryName, categoryEmoji: $newCategoryEmoji) {
                    let cat = InventoryCategory(name: newCategoryName, emoji: newCategoryEmoji)
                    modelContext.insert(cat)
                    newCategoryName = ""
                    newCategoryEmoji = "📦"
                }
            }
            .sheet(item: $editingCategory) { category in
                EmojiPickerSheet(currentEmoji: category.emoji) { newEmoji in
                    category.emoji = newEmoji
                    try? modelContext.save()
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
    @State private var newLocationEmoji = "📍"
    @State private var editingLocation: InventoryLocation?

    var body: some View {
        List {
            if category.locations.isEmpty {
                ContentUnavailableView("No Locations", systemImage: "mappin.and.ellipse", description: Text("Add locations like 'Bar Fridge' to this category"))
            }
            
            ForEach(category.locations.sorted(by: { $0.name < $1.name })) { location in
                NavigationLink(destination: ItemListView(location: location)) {
                    HStack(spacing: 12) {
                        Text(location.emoji)
                            .font(.system(size: 28))
                            .onLongPressGesture {
                                if coordinator.isManager {
                                    editingLocation = location
                                }
                            }
                        
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
        .sheet(isPresented: $showingAddLocation) {
            AddLocationSheet(locationName: $newLocationName, locationEmoji: $newLocationEmoji) {
                let loc = InventoryLocation(name: newLocationName, emoji: newLocationEmoji)
                loc.category = category
                category.locations.append(loc)
                newLocationName = ""
                newLocationEmoji = "📍"
            }
        }
        .sheet(item: $editingLocation) { location in
            EmojiPickerSheet(currentEmoji: location.emoji) { newEmoji in
                location.emoji = newEmoji
                try? modelContext.save()
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
    @State private var editingItem: InventoryItem?
    @Query(sort: \InventoryCategory.name) private var allCategories: [InventoryCategory]

    var body: some View {
        List {
            ForEach(location.items.sorted(by: { $0.name < $1.name })) { item in
                InventoryItemRow(item: item) {
                    editingItem = item
                }
            }
            .onDelete(perform: deleteItem)
        }
        .navigationTitle(location.name)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if coordinator.isManager {
                    EditButton()
                }
            }
            ToolbarItem(placement: .primaryAction) {
                if coordinator.isManager {
                    Button { showingAddItem = true } label: { Image(systemName: "plus") }
                }
            }
        }
        .sheet(isPresented: $showingAddItem) {
            AddInventoryItemView(location: location)
        }
        .sheet(item: $editingItem) { item in
            ItemSettingsSheet(item: item, allCategories: allCategories)
        }
    }
    
    private func deleteItem(at offsets: IndexSet) {
        for index in offsets {
            let sorted = location.items.sorted(by: { $0.name < $1.name })
            modelContext.delete(sorted[index])
        }
    }
}

// MARK: - Inventory Item Row
struct InventoryItemRow: View {
    @Bindable var item: InventoryItem
    @Environment(AppCoordinator.self) private var coordinator
    @Query private var settings: [AppSettings]
    let onTapName: () -> Void
    
    private var canEdit: Bool {
        coordinator.isManager || (settings.first?.allowEmployeeInventoryEdit ?? false)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Tappable name section with settings indicator
            Button {
                onTapName()
            } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name)
                            .font(.headline)
                            .foregroundColor(DesignSystem.Colors.primary)
                        
                        HStack(spacing: 4) {
                            Text(item.unitType)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            if let vendor = item.vendor, !vendor.isEmpty {
                                Text("•")
                                    .foregroundColor(.secondary)
                                Text(vendor)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    if coordinator.isManager {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(DesignSystem.Colors.tertiary)
                    }
                }
            }
            .buttonStyle(.plain)
            
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
        .padding(.vertical, 6)
    }
    
    private func updateLevel(by direction: Double) {
        let isDecimal = item.parLevel.truncatingRemainder(dividingBy: 1) != 0 ||
                        item.stockLevel.truncatingRemainder(dividingBy: 1) != 0
        
        let step = isDecimal ? 0.1 : 1.0
        item.stockLevel = max(0, item.stockLevel + (direction * step))
    }
    
    private func formatValue(_ val: Double) -> String {
        val.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", val) : String(format: "%.1f", val)
    }
}

// MARK: - Add Item View with Unit Picker
struct AddInventoryItemView: View {
    var location: InventoryLocation
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var name = ""
    @State private var par = ""
    @State private var amountOnHand = ""
    @State private var selectedUnit: UnitType = .bottles
    @State private var vendor = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Item Details") {
                    TextField("Item Name", text: $name)
                    TextField("Vendor (optional)", text: $vendor)
                }
                
                Section("Quantities") {
                    TextField("PAR Level", text: $par)
                        .keyboardType(.decimalPad)
                    
                    TextField("Amount on Hand", text: $amountOnHand)
                        .keyboardType(.decimalPad)
                    
                    Picker("Unit", selection: $selectedUnit) {
                        ForEach(UnitType.allCases, id: \.self) { unit in
                            Text(unit.rawValue).tag(unit)
                        }
                    }
                }
            }
            .navigationTitle("Add Item")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let parValue = Double(par) ?? 0
                        let onHandValue = Double(amountOnHand) ?? 0
                        let newItem = InventoryItem(
                            name: name,
                            stockLevel: parValue,
                            parLevel: parValue,
                            unitType: selectedUnit.rawValue,
                            amountOnHand: onHandValue,
                            vendor: vendor.isEmpty ? nil : vendor
                        )
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

// MARK: - Add Category Sheet
struct AddCategorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var categoryName: String
    @Binding var categoryEmoji: String
    let onSave: () -> Void
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // Preview header
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {
                            Text(categoryEmoji)
                                .font(.system(size: 60))
                            Text(categoryName.isEmpty ? "Category Name" : categoryName)
                                .font(DesignSystem.Typography.title3)
                                .foregroundColor(categoryName.isEmpty ? DesignSystem.Colors.secondary : DesignSystem.Colors.primary)
                        }
                        .padding(.vertical, DesignSystem.Spacing.grid_2)
                        Spacer()
                    }
                }
                .listRowBackground(Color.clear)
                
                Section("Category Details") {
                    TextField("Category Name", text: $categoryName)
                        .padding(.vertical, 4)
                }
                
                Section("Choose Icon") {
                    EmojiPicker(selectedEmoji: $categoryEmoji)
                        .padding(.vertical, 8)
                }
            }
            .navigationTitle("New Category")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        onSave()
                        dismiss()
                    }
                    .disabled(categoryName.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Add Location Sheet
struct AddLocationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var locationName: String
    @Binding var locationEmoji: String
    let onSave: () -> Void
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // Preview header
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {
                            Text(locationEmoji)
                                .font(.system(size: 60))
                            Text(locationName.isEmpty ? "Location Name" : locationName)
                                .font(DesignSystem.Typography.title3)
                                .foregroundColor(locationName.isEmpty ? DesignSystem.Colors.secondary : DesignSystem.Colors.primary)
                        }
                        .padding(.vertical, DesignSystem.Spacing.grid_2)
                        Spacer()
                    }
                }
                .listRowBackground(Color.clear)
                
                Section("Location Details") {
                    TextField("Location Name", text: $locationName)
                        .padding(.vertical, 4)
                }
                
                Section("Choose Icon") {
                    EmojiPicker(selectedEmoji: $locationEmoji)
                        .padding(.vertical, 8)
                }
            }
            .navigationTitle("New Location")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onSave()
                        dismiss()
                    }
                    .disabled(locationName.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Emoji Picker
struct EmojiPicker: View {
    @Binding var selectedEmoji: String
    
    let emojis = ["📦", "📅", "📋", "❄️", "🔥", "📍", "🏪", "🍽️", "☕️", "🥤", "🍰", "🥗", "🥖", "🧃", "🍷", "🍺", "🥛", "🧊", "🧺", "📦", "🗃️", "🏷️"]
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(emojis, id: \.self) { emoji in
                    Button {
                        selectedEmoji = emoji
                        DesignSystem.HapticFeedback.trigger(.selection)
                    } label: {
                        Text(emoji)
                            .font(.system(size: 32))
                            .padding(8)
                            .background(selectedEmoji == emoji ? Color.blue.opacity(0.2) : Color.clear)
                            .clipShape(Circle())
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}

// MARK: - Emoji Picker Sheet
struct EmojiPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let currentEmoji: String
    let onSelect: (String) -> Void
    
    @State private var selectedEmoji: String
    
    init(currentEmoji: String, onSelect: @escaping (String) -> Void) {
        self.currentEmoji = currentEmoji
        self.onSelect = onSelect
        _selectedEmoji = State(initialValue: currentEmoji)
    }
    
    var body: some View {
        NavigationStack {
            VStack {
                Text(selectedEmoji)
                    .font(.system(size: 80))
                    .padding()
                
                EmojiPicker(selectedEmoji: $selectedEmoji)
                    .padding()
                
                Spacer()
            }
            .navigationTitle("Choose Icon")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSelect(selectedEmoji)
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Item Settings Sheet
struct ItemSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @Bindable var item: InventoryItem
    let allCategories: [InventoryCategory]
    
    @State private var name: String
    @State private var stockLevel: String
    @State private var parLevel: String
    @State private var selectedUnit: UnitType
    @State private var vendor: String
    @State private var notes: String
    @State private var selectedCategory: InventoryCategory?
    @State private var selectedLocation: InventoryLocation?
    @State private var showingDeleteConfirmation = false
    
    init(item: InventoryItem, allCategories: [InventoryCategory]) {
        self.item = item
        self.allCategories = allCategories
        _name = State(initialValue: item.name)
        _stockLevel = State(initialValue: String(format: item.stockLevel.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.1f", item.stockLevel))
        _parLevel = State(initialValue: String(format: item.parLevel.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.1f", item.parLevel))
        _selectedUnit = State(initialValue: UnitType(rawValue: item.unitType) ?? .units)
        _vendor = State(initialValue: item.vendor ?? "")
        _notes = State(initialValue: item.notes ?? "")
        _selectedCategory = State(initialValue: item.location?.category)
        _selectedLocation = State(initialValue: item.location)
    }
    
    private var availableLocations: [InventoryLocation] {
        selectedCategory?.locations.sorted(by: { $0.name < $1.name }) ?? []
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Item Details") {
                    TextField("Name", text: $name)
                    TextField("Vendor (optional)", text: $vendor)
                }
                
                Section("Quantities") {
                    HStack {
                        Text("Stock Level")
                        Spacer()
                        TextField("0", text: $stockLevel)
                            .multilineTextAlignment(.trailing)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .frame(width: 80)
                    }
                    
                    HStack {
                        Text("PAR Level")
                        Spacer()
                        TextField("0", text: $parLevel)
                            .multilineTextAlignment(.trailing)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .frame(width: 80)
                    }
                    
                    Picker("Unit", selection: $selectedUnit) {
                        ForEach(UnitType.allCases, id: \.self) { unit in
                            Text(unit.rawValue).tag(unit)
                        }
                    }
                }
                
                Section("Location") {
                    Picker("Category", selection: $selectedCategory) {
                        Text("Select Category").tag(nil as InventoryCategory?)
                        ForEach(allCategories) { category in
                            Text("\(category.emoji) \(category.name)").tag(category as InventoryCategory?)
                        }
                    }
                    .onChange(of: selectedCategory) { _, newValue in
                        // Reset location when category changes
                        if newValue != item.location?.category {
                            selectedLocation = newValue?.locations.first
                        }
                    }
                    
                    if !availableLocations.isEmpty {
                        Picker("Subcategory (Location)", selection: $selectedLocation) {
                            ForEach(availableLocations) { location in
                                Text("\(location.emoji) \(location.name)").tag(location as InventoryLocation?)
                            }
                        }
                    }
                }
                
                Section("Notes") {
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
                
                Section {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete Item", systemImage: "trash")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(DesignSystem.Colors.background)
            .navigationTitle("Item Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                    }
                    .disabled(name.isEmpty)
                }
            }
            .alert("Delete Item", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    deleteItem()
                }
            } message: {
                Text("Are you sure you want to delete \"\(item.name)\"? This action cannot be undone.")
            }
        }
        .presentationDetents([.large])
    }
    
    private func saveChanges() {
        item.name = name
        item.stockLevel = Double(stockLevel) ?? 0
        item.parLevel = Double(parLevel) ?? 0
        item.unitType = selectedUnit.rawValue
        item.vendor = vendor.isEmpty ? nil : vendor
        item.notes = notes.isEmpty ? nil : notes
        
        // Handle location change
        if let newLocation = selectedLocation, newLocation.id != item.location?.id {
            // Remove from old location
            if let oldLocation = item.location {
                oldLocation.items.removeAll { $0.id == item.id }
            }
            // Add to new location
            item.location = newLocation
            newLocation.items.append(item)
        }
        
        do {
            try modelContext.save()
            DesignSystem.HapticFeedback.trigger(.success)
            dismiss()
        } catch {
            print("Failed to save item: \(error)")
            DesignSystem.HapticFeedback.trigger(.error)
        }
    }
    
    private func deleteItem() {
        if let location = item.location {
            location.items.removeAll { $0.id == item.id }
        }
        modelContext.delete(item)
        
        do {
            try modelContext.save()
            DesignSystem.HapticFeedback.trigger(.success)
            dismiss()
        } catch {
            print("Failed to delete item: \(error)")
            DesignSystem.HapticFeedback.trigger(.error)
        }
    }
}
