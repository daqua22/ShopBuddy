//
//  InventoryView.swift
//  ShopBuddy
//
//  Created by Dan on 1/29/26.
//

import SwiftUI
import SwiftData

struct InventoryView: View {
    
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var modelContext
    
    @Query(sort: \InventoryItem.name) private var allItems: [InventoryItem]
    @Query private var settings: [AppSettings]
    
    @State private var selectedCategory: InventoryCategoryType? = nil
    @State private var searchText = ""
    @State private var showingAddItem = false
    @State private var editingItem: InventoryItem?
    
    private var canEdit: Bool {
        coordinator.isManager || (settings.first?.allowEmployeeInventoryEdit ?? false)
    }
    
    private var filteredItems: [InventoryItem] {
        var items = allItems
        
        // Filter by category
        if let category = selectedCategory {
            items = items.filter { $0.category == category }
        }
        
        // Filter by search text
        if !searchText.isEmpty {
            items = items.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.subcategory.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return items
    }
    
    private var groupedItems: [(category: InventoryCategoryType, items: [InventoryItem])] {
        let grouped = Dictionary(grouping: filteredItems, by: { $0.category })
        return grouped
            .sorted { $0.key.sortOrder < $1.key.sortOrder }
            .map { (category: $0.key, items: $0.value.sorted { $0.name < $1.name }) }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.grid_3) {
                    // Search bar
                    searchBar
                    
                    // Category filter
                    categoryFilter
                    
                    // Inventory items
                    if filteredItems.isEmpty {
                        EmptyStateView(
                            icon: "shippingbox",
                            title: "No Inventory Items",
                            message: searchText.isEmpty ? "Add your first inventory item to get started" : "No items match your search",
                            actionTitle: canEdit && searchText.isEmpty ? "Add Item" : nil,
                            action: canEdit && searchText.isEmpty ? { showingAddItem = true } : nil
                        )
                    } else {
                        inventoryList
                    }
                }
                .padding(DesignSystem.Spacing.grid_2)
            }
            .background(DesignSystem.Colors.background.ignoresSafeArea())
            .navigationTitle("Inventory")
            .toolbar {
                if canEdit {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showingAddItem = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingAddItem) {
                AddEditInventoryItemView()
            }
            .sheet(item: $editingItem) { item in
                AddEditInventoryItemView(item: item)
            }
        }
    }
    
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(DesignSystem.Colors.secondary)
            
            TextField("Search inventory...", text: $searchText)
                .foregroundColor(DesignSystem.Colors.primary)
            
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(DesignSystem.Colors.secondary)
                }
            }
        }
        .padding(DesignSystem.Spacing.grid_2)
        .glassCard()
    }
    
    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignSystem.Spacing.grid_1) {
                // All button
                CategoryFilterButton(
                    title: "All",
                    isSelected: selectedCategory == nil
                ) {
                    selectedCategory = nil
                }
                
                // Category buttons
                ForEach(InventoryCategoryType.allCases, id: \.self) { category in
                    CategoryFilterButton(
                        title: category.rawValue,
                        isSelected: selectedCategory == category
                    ) {
                        selectedCategory = category
                    }
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.grid_2)
        }
    }
    
    private var inventoryList: some View {
        VStack(spacing: DesignSystem.Spacing.grid_3) {
            ForEach(groupedItems, id: \.category) { group in
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.grid_2) {
                    if selectedCategory == nil {
                        Text(group.category.rawValue)
                            .font(DesignSystem.Typography.title3)
                            .foregroundColor(DesignSystem.Colors.primary)
                            .padding(.horizontal, DesignSystem.Spacing.grid_2)
                    }
                    
                    // Group by subcategory
                    let subcategoryGroups = Dictionary(grouping: group.items, by: { $0.subcategory })
                        .sorted { $0.key < $1.key }
                    
                    ForEach(subcategoryGroups, id: \.key) { subcategory, items in
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.grid_1) {
                            Text(subcategory)
                                .font(DesignSystem.Typography.headline)
                                .foregroundColor(DesignSystem.Colors.secondary)
                                .padding(.horizontal, DesignSystem.Spacing.grid_2)
                            
                            ForEach(items) { item in
                                InventoryItemRow(item: item, canEdit: canEdit) {
                                    editingItem = item
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Category Filter Button
struct CategoryFilterButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(DesignSystem.Typography.callout)
                .foregroundColor(isSelected ? .white : DesignSystem.Colors.primary)
                .padding(.horizontal, DesignSystem.Spacing.grid_2)
                .padding(.vertical, DesignSystem.Spacing.grid_1)
                .background(isSelected ? DesignSystem.Colors.accent : DesignSystem.Colors.surface)
                .cornerRadius(DesignSystem.CornerRadius.medium)
        }
    }
}

// MARK: - Inventory Item Row
struct InventoryItemRow: View {
    let item: InventoryItem
    let canEdit: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button {
            if canEdit {
                onTap()
            }
        } label: {
            HStack(spacing: DesignSystem.Spacing.grid_2) {
                // Stock indicator
                Circle()
                    .fill(Color.stockColor(percentage: item.stockPercentage))
                    .frame(width: 12, height: 12)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(DesignSystem.Typography.body)
                        .foregroundColor(DesignSystem.Colors.primary)
                    
                    HStack(spacing: DesignSystem.Spacing.grid_1) {
                        Text("\(item.stockLevel, specifier: "%.1f") \(item.unitType)")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondary)
                        
                        if item.isBelowPar {
                            Text("• Below PAR")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.warning)
                        }
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("PAR: \(item.parLevel, specifier: "%.1f")")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondary)
                    
                    if let lastRestocked = item.lastRestocked {
                        Text("Restocked \(lastRestocked.shortDateString())")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.tertiary)
                    }
                }
                
                if canEdit {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(DesignSystem.Colors.tertiary)
                }
            }
            .padding(DesignSystem.Spacing.grid_2)
        }
        .glassCard()
    }
}

// MARK: - Add/Edit Inventory Item View
struct AddEditInventoryItemView: View {
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    let item: InventoryItem?
    
    @State private var name = ""
    @State private var category: InventoryCategoryType = .weekly
    @State private var subcategory = ""
    @State private var stockLevel = ""
    @State private var parLevel = ""
    @State private var unitType = ""
    @State private var notes = ""
    
    init(item: InventoryItem? = nil) {
        self.item = item
        if let item = item {
            _name = State(initialValue: item.name)
            _category = State(initialValue: item.category)
            _subcategory = State(initialValue: item.subcategory)
            _stockLevel = State(initialValue: String(format: "%.1f", item.stockLevel))
            _parLevel = State(initialValue: String(format: "%.1f", item.parLevel))
            _unitType = State(initialValue: item.unitType)
            _notes = State(initialValue: item.notes ?? "")
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Basic Information") {
                    TextField("Item Name", text: $name)
                    
                    Picker("Category", selection: $category) {
                        ForEach(InventoryCategoryType.allCases, id: \.self) { cat in
                            Text(cat.rawValue).tag(cat)
                        }
                    }
                    
                    TextField("Location (e.g., Bar fridge)", text: $subcategory)
                }
                
                Section("Stock Levels") {
                    TextField("Current Stock", text: $stockLevel)
                        .keyboardType(.decimalPad)
                    
                    TextField("PAR Level", text: $parLevel)
                        .keyboardType(.decimalPad)
                    
                    TextField("Unit Type (e.g., kg, L, units)", text: $unitType)
                }
                
                Section("Notes") {
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
                
                if item != nil {
                    Section {
                        Button(role: .destructive) {
                            deleteItem()
                        } label: {
                            Label("Delete Item", systemImage: "trash")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(DesignSystem.Colors.background)
            .navigationTitle(item == nil ? "Add Item" : "Edit Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveItem()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }
    
    private var isValid: Bool {
        !name.isEmpty &&
        !subcategory.isEmpty &&
        !unitType.isEmpty &&
        Double(stockLevel) != nil &&
        Double(parLevel) != nil
    }
    
    private func saveItem() {
        guard let stock = Double(stockLevel),
              let par = Double(parLevel) else { return }
        
        if let item = item {
            // Update existing item
            item.name = name
            item.category = category
            item.subcategory = subcategory
            item.stockLevel = stock
            item.parLevel = par
            item.unitType = unitType
            item.notes = notes.isEmpty ? nil : notes
            item.lastRestocked = Date()
        } else {
            // Create new item
            let newItem = InventoryItem(
                name: name,
                category: category,
                subcategory: subcategory,
                stockLevel: stock,
                parLevel: par,
                unitType: unitType,
                notes: notes.isEmpty ? nil : notes
            )
            modelContext.insert(newItem)
        }
        
        do {
            try modelContext.save()
            DesignSystem.HapticFeedbackDesignSystem.HapticFeedback.trigger(.success)
            dismiss()
        } catch {
            DesignSystem.HapticFeedbackDesignSystem.HapticFeedback.trigger(.error)
            print("Failed to save item: \(error)")
        }
    }
    
    private func deleteItem() {
        guard let item = item else { return }
        
        modelContext.delete(item)
        
        do {
            try modelContext.save()
            DesignSystem.HapticFeedbackDesignSystem.HapticFeedback.trigger(.success)
            dismiss()
        } catch {
            DesignSystem.HapticFeedbackDesignSystem.HapticFeedback.trigger(.error)
            print("Failed to delete item: \(error)")
        }
    }
}
