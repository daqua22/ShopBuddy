import SwiftUI
import SwiftData

private enum InventoryItemFilter: String, CaseIterable, Identifiable {
    case visible = "Visible"
    case lowStock = "Low Stock"
    case hidden = "Hidden"
    case all = "All"

    var id: String { rawValue }
}

private enum InventoryHiddenItemStore {
    static let storageKey = "inventory.hiddenItemIDs"

    static func idSet(from raw: String) -> Set<String> {
        Set(raw.split(separator: ",").map(String.init))
    }

    static func serialized(from idSet: Set<String>) -> String {
        idSet.sorted().joined(separator: ",")
    }

    static func contains(itemID: UUID, raw: String) -> Bool {
        idSet(from: raw).contains(itemID.uuidString)
    }

    static func updated(raw: String, itemID: UUID, hidden: Bool) -> String {
        var ids = idSet(from: raw)
        let itemIDString = itemID.uuidString
        if hidden {
            ids.insert(itemIDString)
        } else {
            ids.remove(itemIDString)
        }
        return serialized(from: ids)
    }
}

private enum InventorySearchMatcher {
    static func matches(query: String, fields: [String]) -> Bool {
        let queryTokens = tokenize(query)
        guard !queryTokens.isEmpty else { return true }

        let fieldTokens = fields.flatMap { tokenize($0) }
        let combined = normalize(fields.joined(separator: " "))

        return queryTokens.allSatisfy { queryToken in
            if combined.contains(queryToken) {
                return true
            }

            return fieldTokens.contains { fieldToken in
                tokenMatches(queryToken: queryToken, fieldToken: fieldToken)
            }
        }
    }

    private static func tokenMatches(queryToken: String, fieldToken: String) -> Bool {
        if fieldToken.contains(queryToken) {
            return true
        }

        if isSubsequence(queryToken, of: fieldToken) {
            return true
        }

        guard queryToken.count >= 3 else { return false }
        let maxDistance: Int
        switch queryToken.count {
        case 0...4:
            maxDistance = 1
        case 5...8:
            maxDistance = 2
        default:
            maxDistance = 3
        }

        guard abs(queryToken.count - fieldToken.count) <= maxDistance else {
            return false
        }

        return boundedLevenshtein(queryToken, fieldToken, maxDistance: maxDistance) != nil
    }

    private static func normalize(_ value: String) -> String {
        value
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func tokenize(_ value: String) -> [String] {
        normalize(value).split(separator: " ").map(String.init)
    }

    private static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        guard !needle.isEmpty else { return true }
        var needleIndex = needle.startIndex

        for character in haystack where needleIndex < needle.endIndex {
            if character == needle[needleIndex] {
                needle.formIndex(after: &needleIndex)
            }
        }

        return needleIndex == needle.endIndex
    }

    private static func boundedLevenshtein(_ lhs: String, _ rhs: String, maxDistance: Int) -> Int? {
        let left = Array(lhs)
        let right = Array(rhs)

        guard !left.isEmpty else {
            return right.count <= maxDistance ? right.count : nil
        }
        guard !right.isEmpty else {
            return left.count <= maxDistance ? left.count : nil
        }

        var previous = Array(0...right.count)
        var current = Array(repeating: 0, count: right.count + 1)

        for i in 1...left.count {
            current[0] = i
            var minimumInRow = current[0]

            for j in 1...right.count {
                let cost = left[i - 1] == right[j - 1] ? 0 : 1
                let deletion = previous[j] + 1
                let insertion = current[j - 1] + 1
                let substitution = previous[j - 1] + cost
                let distance = min(deletion, insertion, substitution)
                current[j] = distance
                minimumInRow = min(minimumInRow, distance)
            }

            if minimumInRow > maxDistance {
                return nil
            }

            swap(&previous, &current)
        }

        return previous[right.count] <= maxDistance ? previous[right.count] : nil
    }
}

private struct InventoryItemSearchResult: Identifiable, Hashable {
    let itemID: UUID
    let itemName: String
    let categoryName: String
    let categoryEmoji: String
    let locationID: UUID
    let locationName: String
    let locationEmoji: String

    var id: UUID { itemID }
}

struct InventoryView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \InventoryCategory.name) private var categories: [InventoryCategory]
    
    @State private var showingAddCategory = false
    @State private var newCategoryName = ""
    @State private var newCategoryEmoji = "📦"
    @State private var editingCategory: InventoryCategory?
    @State private var searchText = ""
    @State private var selectedItemDestination: InventoryItemSearchResult?
    @SceneStorage("inventory.selectedCategoryID") private var selectedCategoryID: String?
    @FocusState private var isSearchFieldFocused: Bool

    private var totalCategoryItemCount: Int {
        categories.reduce(into: 0) { partialResult, category in
            partialResult += category.totalItemCount
        }
    }

    private var filteredCategories: [InventoryCategory] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return categories }

        return categories.filter { category in
            var fields: [String] = [category.name]
            for location in category.locations {
                fields.append(location.name)
                for item in location.items {
                    fields.append(item.name)
                    if let vendor = item.vendor, !vendor.isEmpty {
                        fields.append(vendor)
                    }
                }
            }
            return InventorySearchMatcher.matches(query: query, fields: fields)
        }
    }

    private var itemSearchSuggestions: [InventoryItemSearchResult] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }

        var suggestions: [InventoryItemSearchResult] = []
        for category in categories {
            let sortedLocations = category.locations.sorted { $0.name < $1.name }
            for location in sortedLocations {
                let sortedItems = location.items.sorted { $0.name < $1.name }
                for item in sortedItems where InventorySearchMatcher.matches(query: query, fields: [item.name, item.vendor ?? ""]) {
                    suggestions.append(
                        InventoryItemSearchResult(
                            itemID: item.id,
                            itemName: item.name,
                            categoryName: category.name,
                            categoryEmoji: category.emoji,
                            locationID: location.id,
                            locationName: location.name,
                            locationEmoji: location.emoji
                        )
                    )
                }
            }
        }

        return Array(suggestions.prefix(10))
    }

    var body: some View {
        Group {
            #if os(macOS)
            VStack(spacing: 0) {
                inventoryHeader

                Divider()
                    .overlay(DesignSystem.Colors.glassStroke.opacity(0.45))

                inventoryList
            }
            #else
            inventoryList
            #endif
        }
        .navigationTitle("Inventory")
#if os(iOS)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search categories, locations, or items") {
            inventorySearchSuggestions
        }
#else
        .searchable(text: $searchText, prompt: "Search categories, locations, or items") {
            inventorySearchSuggestions
        }
        .searchFocused($isSearchFieldFocused)
#endif
        .toolbar {
#if os(iOS)
            ToolbarItem(placement: .topBarLeading) {
                if coordinator.isManager {
                    EditButton()
                }
            }
#endif
            ToolbarItem(placement: .primaryAction) {
                if coordinator.isManager {
                    Button { showingAddCategory = true } label: { Image(systemName: "plus") }
                        #if os(macOS)
                        .keyboardShortcut("n", modifiers: [.command])
                        .help("Add Category (\u{2318}N)")
                        #endif
                }
            }
            #if os(macOS)
            ToolbarItem(placement: .automatic) {
                Button {
                    isSearchFieldFocused = true
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .keyboardShortcut("f", modifiers: [.command])
                .help("Focus Search (\u{2318}F)")
            }
            #endif
        }
        .sheet(isPresented: $showingAddCategory) {
            AddCategorySheet(categoryName: $newCategoryName, categoryEmoji: $newCategoryEmoji) {
                let trimmedName = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedName.isEmpty else { return }

                let cat = InventoryCategory(name: trimmedName, emoji: newCategoryEmoji)
                modelContext.insert(cat)
                newCategoryName = ""
                newCategoryEmoji = "📦"
                do {
                    try modelContext.save()
                } catch {
                    print("Failed to save category: \(error)")
                    DesignSystem.HapticFeedback.trigger(.error)
                }
            }
        }
        .sheet(item: $editingCategory) { category in
            EmojiPickerSheet(currentEmoji: category.emoji) { newEmoji in
                category.emoji = newEmoji
                do {
                    try modelContext.save()
                } catch {
                    print("Failed to update category icon: \(error)")
                    DesignSystem.HapticFeedback.trigger(.error)
                }
            }
        }
        .navigationDestination(item: $selectedItemDestination) { result in
            if let location = location(for: result.locationID) {
                ItemListView(location: location, initialSearchText: result.itemName, showAllForSearch: true)
            } else {
                ContentUnavailableView("Item Not Found", systemImage: "shippingbox")
            }
        }
        #if os(macOS)
        .onDeleteCommand {
            guard coordinator.isManager else { return }
            deleteSelectedCategory()
        }
        #endif
    }

    private var inventoryList: some View {
        Group {
            #if os(macOS)
            List(selection: $selectedCategoryID) {
                categoryRows
            }
            #else
            List {
                categoryRows
            }
            #endif
        }
        .liquidListChrome()
        .listRowBackground(DesignSystem.Colors.surfaceElevated.opacity(0.38))
    }

    @ViewBuilder
    private var categoryRows: some View {
        if filteredCategories.isEmpty {
            ContentUnavailableView(
                searchText.isEmpty ? "No Categories" : "No Search Results",
                systemImage: searchText.isEmpty ? "folder.badge.plus" : "magnifyingglass",
                description: Text(searchText.isEmpty ? "Managers can add categories like 'Weekly' or 'Monthly'" : "No category, location, or item matches that search.")
            )
        }

        ForEach(filteredCategories) { category in
            NavigationLink {
                LocationListView(category: category)
            } label: {
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
            .if(coordinator.isManager) { view in
                view.contextMenu {
                    Button {
                        editingCategory = category
                    } label: {
                        Label("Edit Icon", systemImage: "pencil")
                    }
                    Button {
                        duplicateCategory(category)
                    } label: {
                        Label("Duplicate Category", systemImage: "plus.square.on.square")
                    }
                    Divider()
                    Button(role: .destructive) {
                        deleteCategory(category)
                    } label: {
                        Label("Delete Category", systemImage: "trash")
                    }
                }
            }
            #if os(macOS)
            .tag(category.id.uuidString)
            #endif
        }
        .if(coordinator.isManager) { view in
            view.onDelete(perform: deleteCategory)
        }
    }

    #if os(macOS)
    private var inventoryHeader: some View {
        HStack(spacing: 12) {
            Text(searchText.isEmpty ? "Inventory Categories" : "Search Results")
                .font(DesignSystem.Typography.headline)
            Spacer()
            Text("\(filteredCategories.count) categories")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(DesignSystem.Colors.surface.opacity(0.8))
                )
            Divider().frame(height: 24)
            Text("\(totalCategoryItemCount) items")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondary)
                .monospacedDigit()
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(DesignSystem.Colors.surface.opacity(0.8))
                )
        }
        .padding(.horizontal, DesignSystem.Spacing.grid_2)
        .padding(.top, DesignSystem.Spacing.grid_1)
        .padding(.bottom, DesignSystem.Spacing.grid_1)
    }
    #endif

    @ViewBuilder
    private var inventorySearchSuggestions: some View {
        ForEach(itemSearchSuggestions) { result in
            Button {
                searchText = result.itemName
                selectedItemDestination = result
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.itemName)
                    Text("\(result.categoryEmoji) \(result.categoryName) • \(result.locationEmoji) \(result.locationName)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private func deleteCategory(at offsets: IndexSet) {
        let categoriesToDelete = offsets.map { filteredCategories[$0] }
        for category in categoriesToDelete {
            modelContext.delete(category)
        }
        do {
            try modelContext.save()
        } catch {
            print("Failed to delete category: \(error)")
            DesignSystem.HapticFeedback.trigger(.error)
        }
    }

    private func deleteCategory(_ category: InventoryCategory) {
        modelContext.delete(category)
        if selectedCategoryID == category.id.uuidString {
            selectedCategoryID = nil
        }
        do {
            try modelContext.save()
            DesignSystem.HapticFeedback.trigger(.success)
        } catch {
            print("Failed to delete category: \(error)")
            DesignSystem.HapticFeedback.trigger(.error)
        }
    }

    private func deleteSelectedCategory() {
        guard
            let selectedCategoryID,
            let category = categories.first(where: { $0.id.uuidString == selectedCategoryID })
        else {
            return
        }
        deleteCategory(category)
    }

    private func duplicateCategory(_ category: InventoryCategory) {
        let existingNames = Set(categories.map(\.name))
        let duplicatedName = uniqueName(base: category.name, existingNames: existingNames)
        let duplicate = InventoryCategory(name: duplicatedName, emoji: category.emoji)
        modelContext.insert(duplicate)

        do {
            try modelContext.save()
            DesignSystem.HapticFeedback.trigger(.success)
        } catch {
            print("Failed to duplicate category: \(error)")
            DesignSystem.HapticFeedback.trigger(.error)
        }
    }

    private func uniqueName(base: String, existingNames: Set<String>) -> String {
        let trimmedBase = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultName = trimmedBase.isEmpty ? "Untitled" : trimmedBase
        if !existingNames.contains(defaultName) {
            return defaultName
        }

        var index = 2
        while existingNames.contains("\(defaultName) \(index)") {
            index += 1
        }
        return "\(defaultName) \(index)"
    }

    private func location(for locationID: UUID) -> InventoryLocation? {
        for category in categories {
            if let found = category.locations.first(where: { $0.id == locationID }) {
                return found
            }
        }
        return nil
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
    @State private var searchText = ""
    @State private var selectedItemDestination: InventoryItemSearchResult?
    
    private var locations: [InventoryLocation] {
        category.locations.sorted { $0.name < $1.name }
    }

    private var totalLocationItemCount: Int {
        locations.reduce(into: 0) { partialResult, location in
            partialResult += location.items.count
        }
    }

    private var filteredLocations: [InventoryLocation] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return locations }

        return locations.filter { location in
            var fields: [String] = [location.name]
            for item in location.items {
                fields.append(item.name)
                if let vendor = item.vendor, !vendor.isEmpty {
                    fields.append(vendor)
                }
            }
            return InventorySearchMatcher.matches(query: query, fields: fields)
        }
    }

    private var itemSearchSuggestions: [InventoryItemSearchResult] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }

        var suggestions: [InventoryItemSearchResult] = []
        for location in locations {
            let sortedItems = location.items.sorted { $0.name < $1.name }
            for item in sortedItems where InventorySearchMatcher.matches(query: query, fields: [item.name, item.vendor ?? ""]) {
                suggestions.append(
                    InventoryItemSearchResult(
                        itemID: item.id,
                        itemName: item.name,
                        categoryName: category.name,
                        categoryEmoji: category.emoji,
                        locationID: location.id,
                        locationName: location.name,
                        locationEmoji: location.emoji
                    )
                )
            }
        }

        return Array(suggestions.prefix(10))
    }

    var body: some View {
        Group {
            #if os(macOS)
            VStack(spacing: 0) {
                locationHeader

                Divider()
                    .overlay(DesignSystem.Colors.glassStroke.opacity(0.45))

                locationList
            }
            #else
            locationList
            #endif
        }
        .navigationTitle(category.name)
#if os(iOS)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search subcategories or items") {
            locationSearchSuggestions
        }
#else
        .searchable(text: $searchText, prompt: "Search subcategories or items") {
            locationSearchSuggestions
        }
#endif
        .toolbar {
            if coordinator.isManager {
                Button { showingAddLocation = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showingAddLocation) {
            AddLocationSheet(locationName: $newLocationName, locationEmoji: $newLocationEmoji) {
                let trimmedName = newLocationName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedName.isEmpty else { return }

                let loc = InventoryLocation(name: trimmedName, emoji: newLocationEmoji)
                loc.category = category
                modelContext.insert(loc)
                newLocationName = ""
                newLocationEmoji = "📍"
                do {
                    try modelContext.save()
                } catch {
                    print("Failed to save location: \(error)")
                    DesignSystem.HapticFeedback.trigger(.error)
                }
            }
        }
        .sheet(item: $editingLocation) { location in
            EmojiPickerSheet(currentEmoji: location.emoji) { newEmoji in
                location.emoji = newEmoji
                do {
                    try modelContext.save()
                } catch {
                    print("Failed to update location icon: \(error)")
                    DesignSystem.HapticFeedback.trigger(.error)
                }
            }
        }
        .navigationDestination(item: $selectedItemDestination) { result in
            if let location = location(for: result.locationID) {
                ItemListView(location: location, initialSearchText: result.itemName, showAllForSearch: true)
            } else {
                ContentUnavailableView("Item Not Found", systemImage: "shippingbox")
            }
        }
    }

    private var locationList: some View {
        List {
            if filteredLocations.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No Locations" : "No Search Results",
                    systemImage: searchText.isEmpty ? "mappin.and.ellipse" : "magnifyingglass",
                    description: Text(searchText.isEmpty ? "Add locations like 'Bar Fridge' to this category" : "No location or item matches that search.")
                )
            }
            
            ForEach(filteredLocations) { location in
                NavigationLink {
                    ItemListView(location: location)
                } label: {
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
            .if(coordinator.isManager) { view in
                view.onDelete(perform: deleteLocation)
            }
        }
        .liquidListChrome()
        .listRowBackground(DesignSystem.Colors.surfaceElevated.opacity(0.38))
    }

    #if os(macOS)
    private var locationHeader: some View {
        HStack(spacing: 12) {
            Text(searchText.isEmpty ? "Locations" : "Search Results")
                .font(DesignSystem.Typography.headline)
            Spacer()
            Text("\(filteredLocations.count) locations")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(DesignSystem.Colors.surface.opacity(0.8))
                )
            Divider().frame(height: 24)
            Text("\(totalLocationItemCount) items")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondary)
                .monospacedDigit()
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(DesignSystem.Colors.surface.opacity(0.8))
                )
        }
        .padding(.horizontal, DesignSystem.Spacing.grid_2)
        .padding(.top, DesignSystem.Spacing.grid_1)
        .padding(.bottom, DesignSystem.Spacing.grid_1)
    }
    #endif

    @ViewBuilder
    private var locationSearchSuggestions: some View {
        ForEach(itemSearchSuggestions) { result in
            Button {
                searchText = result.itemName
                selectedItemDestination = result
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.itemName)
                    Text("\(result.locationEmoji) \(result.locationName)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private func deleteLocation(at offsets: IndexSet) {
        let locationsToDelete = offsets.map { filteredLocations[$0] }
        for location in locationsToDelete {
            modelContext.delete(location)
        }
        do {
            try modelContext.save()
        } catch {
            print("Failed to delete location: \(error)")
            DesignSystem.HapticFeedback.trigger(.error)
        }
    }

    private func location(for locationID: UUID) -> InventoryLocation? {
        locations.first(where: { $0.id == locationID })
    }
}

// MARK: - Item List
struct ItemListView: View {
    var location: InventoryLocation
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var modelContext
    @State private var showingAddItem = false
    @State private var editingItem: InventoryItem?
    @State private var editingAmountOnHandItem: InventoryItem?
    @State private var searchText: String
    @State private var selectedFilter: InventoryItemFilter
    @AppStorage(InventoryHiddenItemStore.storageKey) private var hiddenItemIDsRaw = ""
    @SceneStorage("inventory.selectedItemID") private var selectedItemID: String?
    @FocusState private var isSearchFieldFocused: Bool

    init(location: InventoryLocation, initialSearchText: String = "", showAllForSearch: Bool = false) {
        self.location = location
        _searchText = State(initialValue: initialSearchText)
        _selectedFilter = State(initialValue: showAllForSearch ? .all : .visible)
    }
    
    private var items: [InventoryItem] {
        location.items.sorted { $0.name < $1.name }
    }
    
    private var availableFilters: [InventoryItemFilter] {
        coordinator.isManager ? [.visible, .lowStock, .hidden, .all] : [.visible, .lowStock]
    }
    
    private var effectiveFilter: InventoryItemFilter {
        availableFilters.contains(selectedFilter) ? selectedFilter : .visible
    }
    
    private var filteredItems: [InventoryItem] {
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        return items.filter { item in
            let hidden = isItemHidden(item)
            
            let matchesFilter: Bool
            switch effectiveFilter {
            case .visible:
                matchesFilter = !hidden
            case .lowStock:
                matchesFilter = !hidden && item.isBelowPar
            case .hidden:
                matchesFilter = coordinator.isManager && hidden
            case .all:
                matchesFilter = coordinator.isManager || !hidden
            }
            
            guard matchesFilter else { return false }
            guard !term.isEmpty else { return true }
            
            return InventorySearchMatcher.matches(
                query: term,
                fields: [item.name, item.vendor ?? ""]
            )
        }
    }
    
    private var canEditStockLevels: Bool {
        coordinator.isManager
    }

    private var hiddenItemsCount: Int {
        items.reduce(into: 0) { partialResult, item in
            if isItemHidden(item) {
                partialResult += 1
            }
        }
    }

    private var visibleItemsCount: Int {
        max(0, items.count - hiddenItemsCount)
    }

    private var lowStockVisibleCount: Int {
        items.reduce(into: 0) { partialResult, item in
            if !isItemHidden(item) && item.isBelowPar {
                partialResult += 1
            }
        }
    }

    var body: some View {
        Group {
            #if os(macOS)
            VStack(spacing: 0) {
                itemListHeader

                Divider()
                    .overlay(DesignSystem.Colors.glassStroke.opacity(0.45))

                itemList
            }
            #else
            itemList
            #endif
        }
        .navigationTitle(location.name)
#if os(iOS)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search by name or vendor")
#else
        .searchable(text: $searchText, prompt: "Search by name or vendor")
        .searchFocused($isSearchFieldFocused)
#endif
        .toolbar {
#if os(iOS)
            ToolbarItem(placement: .topBarLeading) {
                if coordinator.isManager {
                    EditButton()
                }
            }
#endif
            ToolbarItem(placement: .primaryAction) {
                if coordinator.isManager {
                    Button { showingAddItem = true } label: { Image(systemName: "plus") }
                        #if os(macOS)
                        .keyboardShortcut("n", modifiers: [.command, .option])
                        .help("Add Item (\u{2318}\u{2325}N)")
                        #endif
                }
            }
            #if os(macOS)
            ToolbarItem(placement: .automatic) {
                Button {
                    isSearchFieldFocused = true
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .keyboardShortcut("f", modifiers: [.command])
                .help("Focus Search (\u{2318}F)")
            }
            #endif
        }
        .onChange(of: coordinator.isManager) { _, _ in
            if !availableFilters.contains(selectedFilter) {
                selectedFilter = .visible
            }
        }
        .sheet(isPresented: $showingAddItem) {
            AddInventoryItemView(location: location)
        }
        .sheet(item: $editingItem) { item in
            ItemSettingsSheet(item: item)
        }
        .sheet(item: $editingAmountOnHandItem) { item in
            AmountOnHandEditorSheet(item: item)
        }
        #if os(macOS)
        .onDeleteCommand {
            guard coordinator.isManager else { return }
            deleteSelectedItem()
        }
        #endif
    }

    private var itemList: some View {
        Group {
            #if os(macOS)
            List(selection: $selectedItemID) {
                itemRows
            }
            #else
            List {
                itemRows
            }
            #endif
        }
        .liquidListChrome()
        .listRowBackground(DesignSystem.Colors.surfaceElevated.opacity(0.38))
    }

    @ViewBuilder
    private var itemRows: some View {
        filterChipBar
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)

        if filteredItems.isEmpty {
            ContentUnavailableView(
                searchText.isEmpty ? "No Items" : "No Search Results",
                systemImage: searchText.isEmpty ? "shippingbox" : "magnifyingglass",
                description: Text(searchText.isEmpty ? "Try changing the filter or add a new item." : "No item matches that name or vendor.")
            )
        } else {
            ForEach(filteredItems) { item in
                InventoryItemRow(
                    item: item,
                    isHidden: isItemHidden(item),
                    canEditStockLevels: canEditStockLevels,
                    canOpenSettings: coordinator.isManager
                ) {
                    if coordinator.isManager {
                        editingItem = item
                    }
                } onEditAmountOnHand: {
                    if coordinator.isManager {
                        editingAmountOnHandItem = item
                    }
                } onToggleHidden: {
                    if coordinator.isManager {
                        toggleHidden(for: item)
                    }
                } onDuplicate: {
                    if coordinator.isManager {
                        duplicateItem(item)
                    }
                } onDelete: {
                    if coordinator.isManager {
                        deleteItem(item)
                    }
                }
                .if(coordinator.isManager) { view in
                    view.swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button {
                            toggleHidden(for: item)
                        } label: {
                            Label(isItemHidden(item) ? "Unhide" : "Hide", systemImage: isItemHidden(item) ? "eye" : "eye.slash")
                        }
                        .tint(isItemHidden(item) ? .green : .orange)
                    }
                }
                #if os(macOS)
                .tag(item.id.uuidString)
                #endif
            }
            .if(coordinator.isManager) { view in
                view.onDelete(perform: deleteItem)
            }
        }
    }

    #if os(macOS)
    private var itemListHeader: some View {
        HStack(spacing: 12) {
            Text(searchText.isEmpty ? "Inventory Items" : "Search Results")
                .font(DesignSystem.Typography.headline)
            Spacer()
            Text("\(visibleItemsCount) visible")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondary)
                .monospacedDigit()
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(DesignSystem.Colors.surface.opacity(0.8))
                )

            if coordinator.isManager {
                Divider().frame(height: 24)
                Text("\(hiddenItemsCount) hidden")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondary)
                    .monospacedDigit()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(DesignSystem.Colors.surface.opacity(0.8))
                    )
            }

            Divider().frame(height: 24)
            Text("\(lowStockVisibleCount) low")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.warning)
                .monospacedDigit()
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(DesignSystem.Colors.surface.opacity(0.8))
                )
        }
        .padding(.horizontal, DesignSystem.Spacing.grid_2)
        .padding(.top, DesignSystem.Spacing.grid_1)
        .padding(.bottom, DesignSystem.Spacing.grid_1)
    }
    #endif
    
    private var filterChipBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .foregroundColor(DesignSystem.Colors.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(availableFilters) { filter in
                        let isSelected = selectedFilter == filter
                        Button {
                            selectedFilter = filter
                            DesignSystem.HapticFeedback.trigger(.selection)
                        } label: {
                            HStack(spacing: 6) {
                                if isSelected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption2)
                                }
                                Text(filter.rawValue)
                            }
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(isSelected ? .white : DesignSystem.Colors.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                                        .fill(isSelected ? DesignSystem.Colors.accent : DesignSystem.Colors.surface)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Text("\(filteredItems.count)")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondary)
                .monospacedDigit()
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(DesignSystem.Colors.surface.opacity(0.8))
                )
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                .fill(DesignSystem.Colors.surface.opacity(0.6))
        )
    }

    private func deleteItem(at offsets: IndexSet) {
        let itemsToDelete = offsets.map { filteredItems[$0] }
        for item in itemsToDelete {
            hiddenItemIDsRaw = InventoryHiddenItemStore.updated(raw: hiddenItemIDsRaw, itemID: item.id, hidden: false)
            modelContext.delete(item)
        }
        do {
            try modelContext.save()
        } catch {
            print("Failed to delete item: \(error)")
            DesignSystem.HapticFeedback.trigger(.error)
        }
    }

    private func deleteItem(_ item: InventoryItem) {
        hiddenItemIDsRaw = InventoryHiddenItemStore.updated(raw: hiddenItemIDsRaw, itemID: item.id, hidden: false)
        modelContext.delete(item)
        if selectedItemID == item.id.uuidString {
            selectedItemID = nil
        }
        do {
            try modelContext.save()
            DesignSystem.HapticFeedback.trigger(.success)
        } catch {
            print("Failed to delete item: \(error)")
            DesignSystem.HapticFeedback.trigger(.error)
        }
    }

    private func deleteSelectedItem() {
        guard
            let selectedItemID,
            let item = items.first(where: { $0.id.uuidString == selectedItemID })
        else {
            return
        }
        deleteItem(item)
    }

    private func duplicateItem(_ item: InventoryItem) {
        let existingNames = Set(items.map(\.name))
        let duplicatedName = uniqueName(base: item.name, existingNames: existingNames)
        let duplicate = InventoryItem(
            name: duplicatedName,
            stockLevel: item.stockLevel,
            parLevel: item.parLevel,
            unitType: item.unitType,
            amountOnHand: item.amountOnHand,
            vendor: item.vendor,
            notes: item.notes
        )
        duplicate.location = location
        modelContext.insert(duplicate)
        do {
            try modelContext.save()
            DesignSystem.HapticFeedback.trigger(.success)
        } catch {
            print("Failed to duplicate item: \(error)")
            DesignSystem.HapticFeedback.trigger(.error)
        }
    }

    private func uniqueName(base: String, existingNames: Set<String>) -> String {
        let trimmedBase = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultName = trimmedBase.isEmpty ? "Untitled" : trimmedBase
        if !existingNames.contains(defaultName) {
            return defaultName
        }

        var index = 2
        while existingNames.contains("\(defaultName) \(index)") {
            index += 1
        }
        return "\(defaultName) \(index)"
    }

    private func isItemHidden(_ item: InventoryItem) -> Bool {
        InventoryHiddenItemStore.contains(itemID: item.id, raw: hiddenItemIDsRaw)
    }

    private func toggleHidden(for item: InventoryItem) {
        let shouldHide = !isItemHidden(item)
        hiddenItemIDsRaw = InventoryHiddenItemStore.updated(raw: hiddenItemIDsRaw, itemID: item.id, hidden: shouldHide)
        DesignSystem.HapticFeedback.trigger(.selection)
    }
}

// MARK: - Inventory Item Row
struct InventoryItemRow: View {
    @Bindable var item: InventoryItem
    let isHidden: Bool
    let canEditStockLevels: Bool
    let canOpenSettings: Bool
    let onTapName: () -> Void
    let onEditAmountOnHand: () -> Void
    let onToggleHidden: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Tappable name section with settings indicator
            Button {
                if canOpenSettings {
                    onTapName()
                }
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

                            if isHidden {
                                Text("•")
                                    .foregroundColor(.secondary)
                                Text("Hidden")
                                    .font(.caption)
                                    .foregroundColor(DesignSystem.Colors.warning)
                            }
                        }
                    }
                    
                    if canOpenSettings {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(DesignSystem.Colors.tertiary)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!canOpenSettings)
            
            Spacer()
            
            if canEditStockLevels {
                HStack(spacing: 12) {
                    Button { updateLevel(by: -1) } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.title2)
                            .foregroundColor(.red)
                    }
                    
                    Button {
                        onEditAmountOnHand()
                    } label: {
                        Text(formatValue(item.stockLevel))
                            .font(.system(size: 18, weight: .semibold, design: .monospaced))
                            .frame(width: 64, alignment: .center)
                            .frame(minHeight: 36)
                            .multilineTextAlignment(.center)
                            .background(
                                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                                    .fill(DesignSystem.Colors.surface.opacity(0.75))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Set amount on hand for \(item.name)")
                    
                    Button { updateLevel(by: 1) } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundColor(.green)
                    }
                }
                .buttonStyle(.borderless)
            } else {
                Text(formatValue(item.stockLevel))
                    .font(.headline.monospacedDigit())
            }
        }
        .padding(.vertical, 6)
        .opacity(isHidden ? 0.6 : 1.0)
        .contextMenu {
            if canOpenSettings {
                Button {
                    onToggleHidden()
                } label: {
                    Label(isHidden ? "Unhide Item" : "Hide Item", systemImage: isHidden ? "eye" : "eye.slash")
                }

                Button {
                    onEditAmountOnHand()
                } label: {
                    Label("Set Amount On Hand", systemImage: "pencil")
                }

                Button {
                    onDuplicate()
                } label: {
                    Label("Duplicate Item", systemImage: "plus.square.on.square")
                }

                Divider()

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete Item", systemImage: "trash")
                }
            }
        }
    }
    
    private func updateLevel(by direction: Double) {
        let isDecimal = item.parLevel.truncatingRemainder(dividingBy: 1) != 0 ||
                        item.stockLevel.truncatingRemainder(dividingBy: 1) != 0
        
        let step = isDecimal ? 0.1 : 1.0
        let newLevel = max(0, item.stockLevel + (direction * step))
        item.stockLevel = newLevel
        item.amountOnHand = newLevel
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
    
    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private var trimmedVendor: String {
        vendor.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private var parValue: Double? {
        Double(par)
    }
    
    private var onHandValue: Double? {
        amountOnHand.isEmpty ? nil : Double(amountOnHand)
    }
    
    private var isValid: Bool {
        guard !trimmedName.isEmpty, let parsedPar = parValue, parsedPar >= 0 else {
            return false
        }
        guard let parsedOnHand = onHandValue else {
            return amountOnHand.isEmpty
        }
        return parsedOnHand >= 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Item Details") {
                    TextField("Item Name", text: $name)
                    TextField("Vendor (optional)", text: $vendor)
                }
                
                Section("Quantities") {
                    #if os(iOS)
                    TextField("PAR Level", text: $par)
                        .keyboardType(.decimalPad)
                    #else
                    TextField("PAR Level", text: $par)
                    #endif
                    
                    #if os(iOS)
                    TextField("Amount on Hand", text: $amountOnHand)
                        .keyboardType(.decimalPad)
                    #else
                    TextField("Amount on Hand", text: $amountOnHand)
                    #endif
                    
                    Picker("Unit", selection: $selectedUnit) {
                        ForEach(UnitType.allCases, id: \.self) { unit in
                            Text(unit.rawValue).tag(unit)
                        }
                    }
                }
            }
            .liquidFormChrome()
            .navigationTitle("Add Item")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let parValue, parValue >= 0 else { return }
                        let parsedOnHand = onHandValue ?? parValue
                        guard parsedOnHand >= 0 else { return }
                        let clampedOnHand = max(0, parsedOnHand)
                        
                        let newItem = InventoryItem(
                            name: trimmedName,
                            stockLevel: clampedOnHand,
                            parLevel: parValue,
                            unitType: selectedUnit.rawValue,
                            amountOnHand: clampedOnHand,
                            vendor: trimmedVendor.isEmpty ? nil : trimmedVendor
                        )
                        newItem.location = location
                        modelContext.insert(newItem)
                        do {
                            try modelContext.save()
                            DesignSystem.HapticFeedback.trigger(.success)
                        } catch {
                            print("Failed to save inventory item: \(error)")
                            DesignSystem.HapticFeedback.trigger(.error)
                            return
                        }
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }
}

// MARK: - Amount On Hand Editor
struct AmountOnHandEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable var item: InventoryItem
    @State private var amountOnHandText: String

    private var parsedAmount: Double? {
        Double(amountOnHandText)
    }

    private var canSave: Bool {
        guard let parsedAmount else { return false }
        return parsedAmount >= 0
    }

    init(item: InventoryItem) {
        self.item = item
        _amountOnHandText = State(
            initialValue: String(
                format: item.stockLevel.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.1f",
                item.stockLevel
            )
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Available On Hand") {
                    TextField("Amount", text: $amountOnHandText)
                        .multilineTextAlignment(.trailing)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                }

                Section {
                    Text("This updates the live stock value used across inventory and reports.")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondary)
                }
            }
            .liquidFormChrome()
            .navigationTitle(item.name)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveAmountOnHand()
                    }
                    .disabled(!canSave)
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.fraction(0.34), .medium])
        #endif
    }

    private func saveAmountOnHand() {
        guard let parsedAmount else { return }
        let clampedAmount = max(0, parsedAmount)
        item.stockLevel = clampedAmount
        item.amountOnHand = clampedAmount

        do {
            try modelContext.save()
            DesignSystem.HapticFeedback.trigger(.success)
            dismiss()
        } catch {
            print("Failed to save amount on hand: \(error)")
            DesignSystem.HapticFeedback.trigger(.error)
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
            .liquidFormChrome()
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
            .liquidFormChrome()
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
    @AppStorage(InventoryHiddenItemStore.storageKey) private var hiddenItemIDsRaw = ""
    @Query(sort: \InventoryCategory.name) private var allCategories: [InventoryCategory]
    
    @State private var name: String
    @State private var stockLevel: String
    @State private var parLevel: String
    @State private var selectedUnit: UnitType
    @State private var vendor: String
    @State private var notes: String
    @State private var selectedCategory: InventoryCategory?
    @State private var selectedLocation: InventoryLocation?
    @State private var showingDeleteConfirmation = false
    
    private var isValid: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedName.isEmpty && Double(stockLevel) != nil && Double(parLevel) != nil
    }
    
    init(item: InventoryItem) {
        self.item = item
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

    private var isHiddenBinding: Binding<Bool> {
        Binding(
            get: {
                InventoryHiddenItemStore.contains(itemID: item.id, raw: hiddenItemIDsRaw)
            },
            set: { newValue in
                hiddenItemIDsRaw = InventoryHiddenItemStore.updated(
                    raw: hiddenItemIDsRaw,
                    itemID: item.id,
                    hidden: newValue
                )
                DesignSystem.HapticFeedback.trigger(.selection)
            }
        )
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
                        Text("Available On Hand")
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

                Section("Visibility") {
                    Toggle("Hide Item", isOn: isHiddenBinding)
                    Text("Hidden items only appear when the Hidden or All filter is selected.")
                        .font(.caption)
                        .foregroundColor(.secondary)
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
            .liquidFormChrome()
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
                    .disabled(!isValid)
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
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedVendor = vendor.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsedStock = Double(stockLevel),
              let parsedPar = Double(parLevel),
              !trimmedName.isEmpty else { return }
        let clampedStock = max(0, parsedStock)
        let clampedPar = max(0, parsedPar)

        item.name = trimmedName
        item.stockLevel = clampedStock
        item.amountOnHand = clampedStock
        item.parLevel = clampedPar
        item.unitType = selectedUnit.rawValue
        item.vendor = trimmedVendor.isEmpty ? nil : trimmedVendor
        item.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
        
        // Handle location change
        if let newLocation = selectedLocation, newLocation.id != item.location?.id {
            item.location = newLocation
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
        hiddenItemIDsRaw = InventoryHiddenItemStore.updated(raw: hiddenItemIDsRaw, itemID: item.id, hidden: false)
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
