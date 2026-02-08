import SwiftUI
import SwiftData
import Combine

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

    static func pruned(raw: String, validIDs: Set<String>) -> String {
        let pruned = idSet(from: raw).intersection(validIDs)
        return serialized(from: pruned)
    }
}

private enum InventorySearchMatcher {
    static func matches(query: String, fields: [String]) -> Bool {
        let queryTokens = queryTokenized(query)
        return matches(queryTokens: queryTokens, fields: fields)
    }

    static func queryTokenized(_ query: String) -> [String] {
        tokenize(query)
    }

    static func matches(queryTokens: [String], fields: [String]) -> Bool {
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
    let categoryID: UUID
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
    @Query(sort: \InventoryItem.name) private var allInventoryItems: [InventoryItem]
    @AppStorage(InventoryHiddenItemStore.storageKey) private var hiddenItemIDsRaw = ""
    
    @State private var showingAddCategory = false
    @State private var newCategoryName = ""
    @State private var newCategoryEmoji = "📦"
    @State private var editingCategory: InventoryCategory?
    @State private var searchText = ""
    @State private var selectedItemDestination: InventoryItemSearchResult?
    @State private var selectedMacItemID: String?
    @SceneStorage("inventory.selectedCategoryID") private var selectedCategoryID: String?
    @FocusState private var isSearchFieldFocused: Bool
    @State private var isViewActive = false

    private var totalCategoryItemCount: Int {
        categories.reduce(into: 0) { partialResult, category in
            partialResult += category.totalItemCount
        }
    }

    private var selectedCategory: InventoryCategory? {
        guard let selectedCategoryID else { return nil }
        return categories.first(where: { $0.id.uuidString == selectedCategoryID })
    }

    private var filteredCategories: [InventoryCategory] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let queryTokens = InventorySearchMatcher.queryTokenized(query)
        guard !queryTokens.isEmpty else { return categories }

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
            return InventorySearchMatcher.matches(queryTokens: queryTokens, fields: fields)
        }
    }

    private var itemSearchSuggestions: [InventoryItemSearchResult] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let queryTokens = InventorySearchMatcher.queryTokenized(query)
        guard !queryTokens.isEmpty else { return [] }

        var suggestions: [InventoryItemSearchResult] = []
        for category in categories {
            let sortedLocations = category.locations.sorted { $0.name < $1.name }
            for location in sortedLocations {
                let sortedItems = location.items.sorted { $0.name < $1.name }
                for item in sortedItems where InventorySearchMatcher.matches(queryTokens: queryTokens, fields: [item.name, item.vendor ?? ""]) {
                    suggestions.append(
                        InventoryItemSearchResult(
                            itemID: item.id,
                            categoryID: category.id,
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
            macInventorySplitView
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
            #if os(macOS)
            ToolbarItemGroup(placement: .primaryAction) {
                if coordinator.isManager {
                    Button {
                        showingAddCategory = true
                    } label: {
                        Image(systemName: "folder.badge.plus")
                    }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                    .help("Add Category (\u{2318}\u{21E7}N)")

                    Button {
                        NotificationCenter.default.post(name: .shopBuddyInventoryAddItemCommand, object: nil)
                    } label: {
                        Image(systemName: "shippingbox.badge.plus")
                    }
                    .keyboardShortcut("n", modifiers: [.command])
                    .help("Add Item (\u{2318}N)")
                    .disabled(selectedCategory == nil)

                    Button {
                        NotificationCenter.default.post(name: .shopBuddyInventoryDeleteSelectionCommand, object: nil)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .keyboardShortcut(.delete, modifiers: [])
                    .help("Delete Selection (\u{232B})")
                }

                Button {
                    isSearchFieldFocused = true
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .keyboardShortcut("f", modifiers: [.command])
                .help("Focus Search (\u{2318}F)")
            }
            #else
            ToolbarItem(placement: .primaryAction) {
                if coordinator.isManager {
                    Button { showingAddCategory = true } label: { Image(systemName: "plus") }
                }
            }
            #endif
        }
        .sheet(isPresented: $showingAddCategory) {
            AddCategorySheet(categoryName: $newCategoryName, categoryEmoji: $newCategoryEmoji) {
                let trimmedName = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedName.isEmpty else { return }

                let cat = InventoryCategory(name: trimmedName, emoji: newCategoryEmoji)
                withAnimation(.easeInOut(duration: 0.2)) {
                    modelContext.insert(cat)
                }
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
        .onAppear {
            isViewActive = true
            pruneHiddenItemStorage()
            normalizeCategorySelectionIfNeeded()
        }
        .onDisappear {
            isViewActive = false
        }
        .onChange(of: categories.count) { _, _ in
            normalizeCategorySelectionIfNeeded()
        }
        .onChange(of: allInventoryItems.count) { _, _ in
            pruneHiddenItemStorage()
        }
        .onChange(of: selectedCategoryID) { _, _ in
            selectedMacItemID = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .shopBuddyInventoryAddCategoryCommand)) { _ in
            guard isViewActive, coordinator.isManager else { return }
            showingAddCategory = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .shopBuddyInventoryFocusSearchCommand)) { _ in
            guard isViewActive else { return }
            isSearchFieldFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .shopBuddyInventoryDeleteSelectionCommand)) { _ in
            guard isViewActive, coordinator.isManager else { return }
            #if os(macOS)
            guard selectedMacItemID == nil else { return }
            #endif
            deleteSelectedCategory()
        }
        #if os(macOS)
        .onDeleteCommand {
            guard coordinator.isManager else { return }
            guard selectedMacItemID == nil else { return }
            deleteSelectedCategory()
        }
        #endif
    }

    #if os(macOS)
    private var macInventorySplitView: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                inventoryHeader

                Divider()
                    .overlay(DesignSystem.Colors.glassStroke.opacity(0.45))

                List(selection: $selectedCategoryID) {
                    macCategoryRows
                }
                .listStyle(.sidebar)
                .liquidListChrome()
                .listRowBackground(DesignSystem.Colors.surfaceElevated.opacity(0.38))
            }
            .navigationSplitViewColumnWidth(min: 240, ideal: 290)
        } detail: {
            if let selectedCategory {
                MacCategoryItemDetailView(
                    category: selectedCategory,
                    searchText: $searchText,
                    selectedItemID: $selectedMacItemID
                )
            } else {
                ContentUnavailableView {
                    Label("No Category Selected", systemImage: "square.grid.2x2")
                } description: {
                    Text("Pick a category from the sidebar to manage inventory items.")
                } actions: {
                    if coordinator.isManager {
                        Button("Add Category") {
                            showingAddCategory = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .liquidBackground()
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private var macCategoryRows: some View {
        if filteredCategories.isEmpty {
            ContentUnavailableView {
                Label(
                    searchText.isEmpty ? "No Categories" : "No Search Results",
                    systemImage: searchText.isEmpty ? "folder.badge.plus" : "magnifyingglass"
                )
            } description: {
                Text(
                    searchText.isEmpty
                        ? "Create your first category to start organizing items."
                        : "No category, location, or item matches that search."
                )
            } actions: {
                if searchText.isEmpty {
                    if coordinator.isManager {
                        Button("Add Category") {
                            showingAddCategory = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    Button("Clear Search") {
                        searchText = ""
                    }
                }
            }
        }

        ForEach(filteredCategories) { category in
            HStack(spacing: 10) {
                Text(category.emoji)
                    .font(.system(size: 24))
                    .onLongPressGesture {
                        if coordinator.isManager {
                            editingCategory = category
                        }
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(category.name)
                        .font(DesignSystem.Typography.headline)
                        .foregroundColor(DesignSystem.Colors.primary)
                    Text("\(category.locationCount) locations")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondary)
                }

                Spacer(minLength: 10)

                Text("\(category.totalItemCount)")
                    .font(DesignSystem.Typography.caption)
                    .monospacedDigit()
                    .foregroundColor(DesignSystem.Colors.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(DesignSystem.Colors.surface.opacity(0.8))
                    )
            }
            .padding(.vertical, 6)
            .tag(category.id.uuidString)
            .if(coordinator.isManager) { view in
                view.contextMenu {
                    Button("Edit Category", systemImage: "pencil") {
                        editingCategory = category
                    }
                    Divider()
                    Button("Delete Category", systemImage: "trash", role: .destructive) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            deleteCategory(category)
                        }
                    }
                }
            }
        }
        .if(coordinator.isManager) { view in
            view.onDelete(perform: deleteCategory)
        }
    }
    #endif

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
                #if os(macOS)
                selectedCategoryID = result.categoryID.uuidString
                selectedMacItemID = result.itemID.uuidString
                #else
                selectedItemDestination = result
                #endif
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
        withAnimation(.easeInOut(duration: 0.2)) {
            for category in categoriesToDelete {
                modelContext.delete(category)
            }
        }
        do {
            try modelContext.save()
        } catch {
            print("Failed to delete category: \(error)")
            DesignSystem.HapticFeedback.trigger(.error)
        }
    }

    private func deleteCategory(_ category: InventoryCategory) {
        withAnimation(.easeInOut(duration: 0.2)) {
            modelContext.delete(category)
        }
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
        withAnimation(.easeInOut(duration: 0.2)) {
            modelContext.insert(duplicate)
        }

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

    private func pruneHiddenItemStorage() {
        let validItemIDs = Set(allInventoryItems.map { $0.id.uuidString })
        let prunedRaw = InventoryHiddenItemStore.pruned(raw: hiddenItemIDsRaw, validIDs: validItemIDs)
        if prunedRaw != hiddenItemIDsRaw {
            hiddenItemIDsRaw = prunedRaw
        }
    }

    private func normalizeCategorySelectionIfNeeded() {
        if let selectedCategoryID {
            let exists = categories.contains(where: { $0.id.uuidString == selectedCategoryID })
            if !exists {
                self.selectedCategoryID = nil
            }
        }

        if self.selectedCategoryID == nil, let fallback = filteredCategories.first ?? categories.first {
            self.selectedCategoryID = fallback.id.uuidString
        }
    }
}

#if os(macOS)
private struct MacCategoryItemRecord: Identifiable {
    let item: InventoryItem
    let location: InventoryLocation

    var id: UUID { item.id }
}

private struct MacCategoryItemDetailView: View {
    let category: InventoryCategory
    @Binding var searchText: String
    @Binding var selectedItemID: String?

    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var modelContext

    @State private var editingItem: InventoryItem?
    @State private var showingAddLocation = false
    @State private var newLocationName = ""
    @State private var newLocationEmoji = "📍"
    @State private var showingLocationPicker = false
    @State private var showingAddItemSheet = false
    @State private var addItemLocationID: String?
    @State private var selectedLocationFilterID: String?
    @State private var isViewActive = false

    private var locations: [InventoryLocation] {
        category.locations.sorted { $0.name < $1.name }
    }

    private var allItemRecords: [MacCategoryItemRecord] {
        var records: [MacCategoryItemRecord] = []
        for location in locations {
            let sortedItems = location.items.sorted { $0.name < $1.name }
            for item in sortedItems {
                records.append(MacCategoryItemRecord(item: item, location: location))
            }
        }
        return records
    }

    private var filteredByLocationRecords: [MacCategoryItemRecord] {
        guard let selectedLocationFilterID else { return allItemRecords }
        return allItemRecords.filter { $0.location.id.uuidString == selectedLocationFilterID }
    }

    private var filteredRecords: [MacCategoryItemRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let queryTokens = InventorySearchMatcher.queryTokenized(query)
        guard !queryTokens.isEmpty else { return filteredByLocationRecords }

        return filteredByLocationRecords.filter { record in
            InventorySearchMatcher.matches(
                queryTokens: queryTokens,
                fields: [
                    record.item.name,
                    record.item.vendor ?? "",
                    record.item.unitType,
                    record.location.name
                ]
            )
        }
    }

    private var lowStockCount: Int {
        filteredRecords.reduce(into: 0) { partialResult, record in
            if record.item.stockLevel <= record.item.parLevel {
                partialResult += 1
            }
        }
    }

    private var selectedLocationFilter: InventoryLocation? {
        guard let selectedLocationFilterID else { return nil }
        return locations.first(where: { $0.id.uuidString == selectedLocationFilterID })
    }

    private var selectedAddLocation: InventoryLocation? {
        guard let addItemLocationID else { return nil }
        return locations.first(where: { $0.id.uuidString == addItemLocationID })
    }

    var body: some View {
        VStack(spacing: 0) {
            detailHeader

            Divider()
                .overlay(DesignSystem.Colors.glassStroke.opacity(0.45))

            List(selection: $selectedItemID) {
                detailRows
            }
            .listStyle(.inset)
            .liquidListChrome()
            .listRowBackground(DesignSystem.Colors.surfaceElevated.opacity(0.38))
            .animation(.easeInOut(duration: 0.2), value: filteredRecords.map { $0.item.id })
        }
        .sheet(item: $editingItem) { item in
            ItemSettingsSheet(item: item)
        }
        .sheet(isPresented: $showingAddLocation) {
            AddLocationSheet(locationName: $newLocationName, locationEmoji: $newLocationEmoji) {
                let trimmedName = newLocationName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedName.isEmpty else { return }

                let location = InventoryLocation(name: trimmedName, emoji: newLocationEmoji)
                location.category = category
                withAnimation(.easeInOut(duration: 0.2)) {
                    modelContext.insert(location)
                }

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
        .sheet(isPresented: $showingLocationPicker) {
            NavigationStack {
                Form {
                    Picker("Location", selection: $addItemLocationID) {
                        ForEach(locations) { location in
                            Text("\(location.emoji) \(location.name)")
                                .tag(Optional(location.id.uuidString))
                        }
                    }
                }
                .liquidFormChrome()
                .navigationTitle("Choose Location")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showingLocationPicker = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Continue") {
                            showingLocationPicker = false
                            if selectedAddLocation != nil {
                                showingAddItemSheet = true
                            }
                        }
                        .disabled(selectedAddLocation == nil)
                    }
                }
            }
            .frame(minWidth: 420, minHeight: 260)
        }
        .sheet(isPresented: $showingAddItemSheet) {
            if let selectedAddLocation {
                AddInventoryItemView(location: selectedAddLocation)
            } else {
                ContentUnavailableView("No Location Selected", systemImage: "mappin.slash")
            }
        }
        .onAppear {
            isViewActive = true
            normalizeSelection()
        }
        .onDisappear {
            isViewActive = false
        }
        .onChange(of: allItemRecords.map { $0.item.id }) { _, _ in
            normalizeSelection()
        }
        .onChange(of: locations.map { $0.id.uuidString }) { _, _ in
            normalizeLocationFilter()
        }
        .onChange(of: selectedItemID) { _, _ in
            revealSelectedItemIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .shopBuddyInventoryAddItemCommand)) { _ in
            guard isViewActive, coordinator.isManager else { return }
            presentAddItemFlow()
        }
        .onReceive(NotificationCenter.default.publisher(for: .shopBuddyInventoryDeleteSelectionCommand)) { _ in
            guard isViewActive, coordinator.isManager else { return }
            deleteSelectedItem()
        }
        .onDeleteCommand {
            guard coordinator.isManager else { return }
            deleteSelectedItem()
        }
    }

    private var detailHeader: some View {
        HStack(spacing: 12) {
            Text("\(category.emoji) \(category.name)")
                .font(DesignSystem.Typography.headline)

            Spacer()

            Text("\(filteredRecords.count) items")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondary)
                .monospacedDigit()
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(DesignSystem.Colors.surface.opacity(0.8))
                )

            Divider().frame(height: 24)

            Text("\(lowStockCount) low")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.warning)
                .monospacedDigit()
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(DesignSystem.Colors.surface.opacity(0.8))
                )

            Divider().frame(height: 24)

            Menu {
                Button("All Locations") {
                    selectedLocationFilterID = nil
                }

                if !locations.isEmpty {
                    Divider()
                    ForEach(locations) { location in
                        Button("\(location.emoji) \(location.name)") {
                            selectedLocationFilterID = location.id.uuidString
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "list.bullet.indent")
                    Text(selectedLocationFilter.map { "\($0.emoji) \($0.name)" } ?? "All Locations")
                        .lineLimit(1)
                }
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(DesignSystem.Colors.surface.opacity(0.8))
                )
            }
            .menuStyle(.borderlessButton)
        }
        .padding(.horizontal, DesignSystem.Spacing.grid_2)
        .padding(.top, DesignSystem.Spacing.grid_1)
        .padding(.bottom, DesignSystem.Spacing.grid_1)
    }

    @ViewBuilder
    private var detailRows: some View {
        if filteredRecords.isEmpty {
            ContentUnavailableView {
                Label(
                    searchText.isEmpty ? "No Items" : "No Search Results",
                    systemImage: searchText.isEmpty ? "shippingbox" : "magnifyingglass"
                )
            } description: {
                Text(
                    searchText.isEmpty
                        ? "Add items to this category so staff can track quantity and minimum levels."
                        : "No items in this category match that search."
                )
            } actions: {
                if searchText.isEmpty {
                    if coordinator.isManager {
                        Button(locations.isEmpty ? "Add Location" : "Add Item") {
                            if locations.isEmpty {
                                showingAddLocation = true
                            } else {
                                presentAddItemFlow()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    Button("Clear Search") {
                        searchText = ""
                    }
                }
            }
            .listRowBackground(Color.clear)
        } else {
            ForEach(filteredRecords) { record in
                itemRow(record)
                    .tag(record.item.id.uuidString)
                    .contextMenu {
                        Button("Edit Item", systemImage: "pencil") {
                            editingItem = record.item
                        }
                        Button("Delete Item", systemImage: "trash", role: .destructive) {
                            deleteItem(record.item)
                        }
                    }
                    .onTapGesture(count: 2) {
                        editingItem = record.item
                    }
            }
        }
    }

    private func itemRow(_ record: MacCategoryItemRecord) -> some View {
        let isLowStock = record.item.stockLevel <= record.item.parLevel

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(record.item.name)
                    .font(DesignSystem.Typography.headline)
                    .foregroundColor(DesignSystem.Colors.primary)

                HStack(spacing: 6) {
                    Text(record.item.unitType)
                    Text("•")
                    Text("Min \(formattedQuantity(record.item.parLevel))")
                    Text("•")
                    Text(record.location.name)
                }
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondary)
            }

            Spacer(minLength: 12)

            if isLowStock {
                Text("Low Stock")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.warning)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(DesignSystem.Colors.warning.opacity(0.16))
                    )
            }

            Text(formattedQuantity(record.item.stockLevel))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(DesignSystem.Colors.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(DesignSystem.Colors.surface.opacity(0.9))
                )
                .contentTransition(.numericText(value: record.item.stockLevel))
                .animation(.easeInOut(duration: 0.2), value: record.item.stockLevel)
        }
        .padding(.vertical, 6)
    }

    private func presentAddItemFlow() {
        guard coordinator.isManager else { return }

        if locations.isEmpty {
            showingAddLocation = true
            return
        }

        if locations.count == 1 {
            addItemLocationID = locations[0].id.uuidString
            showingAddItemSheet = true
            return
        }

        if let selectedLocationFilterID,
           locations.contains(where: { $0.id.uuidString == selectedLocationFilterID }) {
            addItemLocationID = selectedLocationFilterID
        } else if addItemLocationID == nil || selectedAddLocation == nil {
            addItemLocationID = locations[0].id.uuidString
        }
        showingLocationPicker = true
    }

    private func normalizeSelection() {
        guard let selectedItemID else { return }
        let exists = allItemRecords.contains(where: { $0.item.id.uuidString == selectedItemID })
        if !exists {
            self.selectedItemID = nil
        }
    }

    private func normalizeLocationFilter() {
        guard let selectedLocationFilterID else { return }
        let exists = locations.contains(where: { $0.id.uuidString == selectedLocationFilterID })
        if !exists {
            self.selectedLocationFilterID = nil
        }
    }

    private func revealSelectedItemIfNeeded() {
        guard
            let selectedItemID,
            let selectedRecord = allItemRecords.first(where: { $0.item.id.uuidString == selectedItemID }),
            let selectedLocationFilterID,
            selectedRecord.location.id.uuidString != selectedLocationFilterID
        else {
            return
        }
        self.selectedLocationFilterID = nil
    }

    private func deleteSelectedItem() {
        guard
            let selectedItemID,
            let record = allItemRecords.first(where: { $0.item.id.uuidString == selectedItemID })
        else {
            return
        }
        deleteItem(record.item)
    }

    private func deleteItem(_ item: InventoryItem) {
        withAnimation(.easeInOut(duration: 0.2)) {
            modelContext.delete(item)
        }
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

    private func formattedQuantity(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }
}
#endif

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
    @SceneStorage("inventory.selectedLocationID") private var selectedLocationID: String?
    @FocusState private var isSearchFieldFocused: Bool
    @State private var isViewActive = false
    
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
        let queryTokens = InventorySearchMatcher.queryTokenized(query)
        guard !queryTokens.isEmpty else { return locations }

        return locations.filter { location in
            var fields: [String] = [location.name]
            for item in location.items {
                fields.append(item.name)
                if let vendor = item.vendor, !vendor.isEmpty {
                    fields.append(vendor)
                }
            }
            return InventorySearchMatcher.matches(queryTokens: queryTokens, fields: fields)
        }
    }

    private var itemSearchSuggestions: [InventoryItemSearchResult] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let queryTokens = InventorySearchMatcher.queryTokenized(query)
        guard !queryTokens.isEmpty else { return [] }

        var suggestions: [InventoryItemSearchResult] = []
        for location in locations {
            let sortedItems = location.items.sorted { $0.name < $1.name }
            for item in sortedItems where InventorySearchMatcher.matches(queryTokens: queryTokens, fields: [item.name, item.vendor ?? ""]) {
                suggestions.append(
                    InventoryItemSearchResult(
                        itemID: item.id,
                        categoryID: category.id,
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
        .searchFocused($isSearchFieldFocused)
#endif
        .toolbar {
            if coordinator.isManager {
                Button { showingAddLocation = true } label: { Image(systemName: "plus") }
                    #if os(macOS)
                    .keyboardShortcut("n", modifiers: [.command, .option])
                    .help("Add Location (\u{2318}\u{2325}N)")
                    #endif
            }
            #if os(macOS)
            Button {
                isSearchFieldFocused = true
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .keyboardShortcut("f", modifiers: [.command])
            .help("Focus Search (\u{2318}F)")
            #endif
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
        .onAppear {
            isViewActive = true
        }
        .onDisappear {
            isViewActive = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .shopBuddyInventoryAddLocationCommand)) { _ in
            guard isViewActive, coordinator.isManager else { return }
            showingAddLocation = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .shopBuddyInventoryFocusSearchCommand)) { _ in
            guard isViewActive else { return }
            isSearchFieldFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .shopBuddyInventoryDeleteSelectionCommand)) { _ in
            guard isViewActive, coordinator.isManager else { return }
            deleteSelectedLocation()
        }
        #if os(macOS)
        .onDeleteCommand {
            guard coordinator.isManager else { return }
            deleteSelectedLocation()
        }
        #endif
    }

    private var locationList: some View {
        Group {
            #if os(macOS)
            List(selection: $selectedLocationID) {
                locationRows
            }
            #else
            List {
                locationRows
            }
            #endif
        }
        .liquidListChrome()
        .listRowBackground(DesignSystem.Colors.surfaceElevated.opacity(0.38))
    }

    @ViewBuilder
    private var locationRows: some View {
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
            .if(coordinator.isManager) { view in
                view.contextMenu {
                    Button {
                        editingLocation = location
                    } label: {
                        Label("Edit Icon", systemImage: "pencil")
                    }
                    Button {
                        duplicateLocation(location)
                    } label: {
                        Label("Duplicate Location", systemImage: "plus.square.on.square")
                    }
                    Divider()
                    Button(role: .destructive) {
                        deleteLocation(location)
                    } label: {
                        Label("Delete Location", systemImage: "trash")
                    }
                }
            }
            #if os(macOS)
            .tag(location.id.uuidString)
            #endif
        }
        .if(coordinator.isManager) { view in
            view.onDelete(perform: deleteLocation)
        }
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
            if selectedLocationID == location.id.uuidString {
                selectedLocationID = nil
            }
        }
        do {
            try modelContext.save()
        } catch {
            print("Failed to delete location: \(error)")
            DesignSystem.HapticFeedback.trigger(.error)
        }
    }

    private func deleteLocation(_ location: InventoryLocation) {
        modelContext.delete(location)
        if selectedLocationID == location.id.uuidString {
            selectedLocationID = nil
        }
        do {
            try modelContext.save()
            DesignSystem.HapticFeedback.trigger(.success)
        } catch {
            print("Failed to delete location: \(error)")
            DesignSystem.HapticFeedback.trigger(.error)
        }
    }

    private func deleteSelectedLocation() {
        guard
            let selectedLocationID,
            let location = locations.first(where: { $0.id.uuidString == selectedLocationID })
        else {
            return
        }
        deleteLocation(location)
    }

    private func duplicateLocation(_ location: InventoryLocation) {
        let existingNames = Set(locations.map(\.name))
        let duplicatedName = uniqueName(base: location.name, existingNames: existingNames)
        let duplicate = InventoryLocation(name: duplicatedName, emoji: location.emoji)
        duplicate.category = category
        modelContext.insert(duplicate)
        do {
            try modelContext.save()
            DesignSystem.HapticFeedback.trigger(.success)
        } catch {
            print("Failed to duplicate location: \(error)")
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
    @State private var hiddenItemIDSet = Set<String>()
    @SceneStorage("inventory.selectedItemID") private var selectedItemID: String?
    @FocusState private var isSearchFieldFocused: Bool
    @State private var isViewActive = false

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
        let queryTokens = InventorySearchMatcher.queryTokenized(term)
        
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
            guard !queryTokens.isEmpty else { return true }
            
            return InventorySearchMatcher.matches(
                queryTokens: queryTokens,
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
                        .keyboardShortcut("n", modifiers: [.command])
                        .help("Add Item (\u{2318}N)")
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
        .onAppear {
            isViewActive = true
            syncHiddenItemSet()
        }
        .onDisappear {
            isViewActive = false
        }
        .onChange(of: hiddenItemIDsRaw) { _, _ in
            syncHiddenItemSet()
        }
        .onReceive(NotificationCenter.default.publisher(for: .shopBuddyInventoryAddItemCommand)) { _ in
            guard isViewActive, coordinator.isManager else { return }
            showingAddItem = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .shopBuddyInventoryFocusSearchCommand)) { _ in
            guard isViewActive else { return }
            isSearchFieldFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .shopBuddyInventoryDeleteSelectionCommand)) { _ in
            guard isViewActive, coordinator.isManager else { return }
            deleteSelectedItem()
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
        .animation(.easeInOut(duration: 0.2), value: filteredItems.map { $0.id })
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
        withAnimation(.easeInOut(duration: 0.2)) {
            for item in itemsToDelete {
                hiddenItemIDSet.remove(item.id.uuidString)
                modelContext.delete(item)
            }
        }
        persistHiddenItemSet()
        do {
            try modelContext.save()
        } catch {
            print("Failed to delete item: \(error)")
            DesignSystem.HapticFeedback.trigger(.error)
        }
    }

    private func deleteItem(_ item: InventoryItem) {
        hiddenItemIDSet.remove(item.id.uuidString)
        persistHiddenItemSet()
        withAnimation(.easeInOut(duration: 0.2)) {
            modelContext.delete(item)
        }
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
        withAnimation(.easeInOut(duration: 0.2)) {
            modelContext.insert(duplicate)
        }
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
        hiddenItemIDSet.contains(item.id.uuidString)
    }

    private func toggleHidden(for item: InventoryItem) {
        let shouldHide = !isItemHidden(item)
        if shouldHide {
            hiddenItemIDSet.insert(item.id.uuidString)
        } else {
            hiddenItemIDSet.remove(item.id.uuidString)
        }
        persistHiddenItemSet()
        DesignSystem.HapticFeedback.trigger(.selection)
    }

    private func syncHiddenItemSet() {
        let parsedSet = InventoryHiddenItemStore.idSet(from: hiddenItemIDsRaw)
        if parsedSet != hiddenItemIDSet {
            hiddenItemIDSet = parsedSet
        }
    }

    private func persistHiddenItemSet() {
        let serialized = InventoryHiddenItemStore.serialized(from: hiddenItemIDSet)
        if serialized != hiddenItemIDsRaw {
            hiddenItemIDsRaw = serialized
        }
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

                            Text("•")
                                .foregroundColor(.secondary)

                            Text("Min \(formatValue(item.parLevel))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            if let vendor = item.vendor, !vendor.isEmpty {
                                Text("•")
                                    .foregroundColor(.secondary)
                                Text(vendor)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            if item.stockLevel <= item.parLevel {
                                Text("•")
                                    .foregroundColor(.secondary)
                                Text("Low Stock")
                                    .font(.caption)
                                    .foregroundColor(DesignSystem.Colors.warning)
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
                            .contentTransition(.numericText(value: item.stockLevel))
                            .animation(.easeInOut(duration: 0.2), value: item.stockLevel)
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
                    .contentTransition(.numericText(value: item.stockLevel))
                    .animation(.easeInOut(duration: 0.2), value: item.stockLevel)
            }
        }
        .padding(.vertical, 6)
        .opacity(isHidden ? 0.6 : 1.0)
        .contextMenu {
            if canOpenSettings {
                Button {
                    onTapName()
                } label: {
                    Label("Edit Item", systemImage: "pencil")
                }

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
        withAnimation(.easeInOut(duration: 0.2)) {
            item.stockLevel = newLevel
            item.amountOnHand = newLevel
        }
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

    private var parStepperBinding: Binding<Double> {
        Binding(
            get: { max(0, Double(par) ?? 0) },
            set: { newValue in
                par = formattedQuantity(newValue)
                if amountOnHand.isEmpty {
                    amountOnHand = formattedQuantity(max(0, newValue))
                }
            }
        )
    }

    private var onHandStepperBinding: Binding<Double> {
        Binding(
            get: { max(0, Double(amountOnHand) ?? 0) },
            set: { newValue in
                amountOnHand = formattedQuantity(newValue)
            }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Item Details") {
                    TextField("Item Name", text: $name)
                    TextField("Vendor (optional)", text: $vendor)
                }
                
                Section("Quantities") {
                    HStack {
                        Text("PAR Level")
                        Spacer()
                        #if os(iOS)
                        TextField("0", text: $par)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        #else
                        TextField("0", text: $par)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        #endif

                        Stepper("", value: parStepperBinding, in: 0...10_000, step: 1)
                            .labelsHidden()
                    }

                    HStack {
                        Text("Amount on Hand")
                        Spacer()
                        #if os(iOS)
                        TextField("0", text: $amountOnHand)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        #else
                        TextField("0", text: $amountOnHand)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        #endif

                        Stepper("", value: onHandStepperBinding, in: 0...10_000, step: 1)
                            .labelsHidden()
                    }
                    
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

    private func formattedQuantity(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
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
        guard
            !trimmedName.isEmpty,
            let stock = Double(stockLevel),
            let par = Double(parLevel)
        else {
            return false
        }
        return stock >= 0 && par >= 0
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

    private var stockLevelStepperBinding: Binding<Double> {
        Binding(
            get: { max(0, Double(stockLevel) ?? 0) },
            set: { stockLevel = formattedQuantity($0) }
        )
    }

    private var parLevelStepperBinding: Binding<Double> {
        Binding(
            get: { max(0, Double(parLevel) ?? 0) },
            set: { parLevel = formattedQuantity($0) }
        )
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
                        Stepper("", value: stockLevelStepperBinding, in: 0...10_000, step: 1)
                            .labelsHidden()
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
                        Stepper("", value: parLevelStepperBinding, in: 0...10_000, step: 1)
                            .labelsHidden()
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

    private func formattedQuantity(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }
}
