import SwiftUI
import UniformTypeIdentifiers
import SwiftData
import SwiftData
import Combine
import Foundation

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
    @Query private var settings: [AppSettings]
    @AppStorage(InventoryHiddenItemStore.storageKey) private var hiddenItemIDsRaw = ""
    
    @State private var showingAddCategory = false
    @State private var newCategoryName = ""
    @State private var newCategoryEmoji = "📦"
    @State private var editingCategory: InventoryCategory?
    @State private var showingAddLocationFromSidebar = false
    @State private var sidebarNewLocationName = ""
    @State private var sidebarNewLocationEmoji = "📍"
    @State private var expandedCategories: Set<String> = []
    @State private var searchText = ""
    @State private var selectedItemDestination: InventoryItemSearchResult?
    @State private var selectedMacItemID: String?
    @SceneStorage("inventory.selectedCategoryID") private var selectedCategoryID: String?
    @SceneStorage("inventory.selectedLocationID") private var selectedLocationID: String?
    @FocusState private var isSearchFieldFocused: Bool
    @State private var isViewActive = false
    @State private var forceRefreshID = UUID()

    private var dragEnabled: Bool {
        settings.first?.enableDragAndDrop ?? true
    }

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
                        showingAddLocationFromSidebar = true
                    } label: {
                        Image(systemName: "mappin.and.ellipse")
                    }
                    .keyboardShortcut("n", modifiers: [.command, .option])
                    .help("Add Location (\u{2318}\u{2325}N)")
                    .disabled(selectedCategory == nil)

                    Button {
                        NotificationCenter.default.post(name: .shopBuddyInventoryAddItemCommand, object: nil)
                    } label: {
                        Label("Add Item", systemImage: "plus")
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
                searchText = ""
                selectedCategoryID = cat.id.uuidString
                expandedCategories.insert(cat.id.uuidString)
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
        .sheet(isPresented: $showingAddLocationFromSidebar) {
            AddLocationSheet(locationName: $sidebarNewLocationName, locationEmoji: $sidebarNewLocationEmoji) {
                let trimmedName = sidebarNewLocationName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedName.isEmpty, let category = selectedCategory else { return }

                let location = InventoryLocation(name: trimmedName, emoji: sidebarNewLocationEmoji)
                location.category = category
                withAnimation(.easeInOut(duration: 0.2)) {
                    modelContext.insert(location)
                }

                sidebarNewLocationName = ""
                sidebarNewLocationEmoji = "📍"

                // Auto-expand the category so the new location is visible
                expandedCategories.insert(category.id.uuidString)

                do {
                    try modelContext.save()
                } catch {
                    print("Failed to save location: \(error)")
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
        .onChange(of: selectedCategoryID) { _, newValue in
            selectedMacItemID = nil
            // When switching categories, clear location filter unless the location belongs to the new category
            if let selectedLocationID, let newValue {
                let locationBelongs = categories
                    .first(where: { $0.id.uuidString == newValue })?
                    .locations
                    .contains(where: { $0.id.uuidString == selectedLocationID }) ?? false
                if !locationBelongs {
                    self.selectedLocationID = nil
                }
            } else if newValue == nil {
                selectedLocationID = nil
            }
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
    .id(forceRefreshID)
    .onReceive(NotificationCenter.default.publisher(for: Notification.Name("NSUndoManagerDidUndoChangeNotification"))) { _ in
        forceRefreshID = UUID()
    }
    .onReceive(NotificationCenter.default.publisher(for: Notification.Name("NSUndoManagerDidRedoChangeNotification"))) { _ in
        forceRefreshID = UUID()
    }
    }

    #if os(macOS)
    private var macInventorySplitView: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List {
                    macCategoryRows
                }
                .listStyle(.sidebar)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)) // Reduced insets for custom rows
                .liquidListChrome()
                .listRowBackground(Color.clear) // Clear background for custom highlighting
                .overlay {
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
                }
                .onChange(of: selectedLocationID) { _, newLocID in
                    // When a location is selected from the sidebar, auto-select its parent category
                    guard let newLocID else { return }
                    for category in categories {
                        if category.locations.contains(where: { $0.id.uuidString == newLocID }) {
                            if selectedCategoryID != category.id.uuidString {
                                selectedCategoryID = category.id.uuidString
                            }
                            break
                        }
                    }
                }
            }
            .macPagePadding(horizontal: DesignSystem.Spacing.grid_2, vertical: DesignSystem.Spacing.grid_1)
            .navigationSplitViewColumnWidth(min: 260, ideal: 320)
        } detail: {
            if let selectedCategory {
                MacCategoryItemDetailView(
                    category: selectedCategory,
                    searchText: $searchText,
                    selectedItemID: $selectedMacItemID,
                    selectedLocationFilterID: $selectedLocationID
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
                .padding(DesignSystem.Spacing.grid_3)
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private var macCategoryRows: some View {
        ForEach(filteredCategories) { category in
            let isExpanded = expandedCategories.contains(category.id.uuidString)
            let isCategorySelected = selectedCategoryID == category.id.uuidString
            // Highlight header only if collapsed and category is selected (implied)
            // OR if strictly following user rule: "Highlight category only when the dropdown of the category is closed."
            let isHeaderHighlighted = !isExpanded && isCategorySelected
            
            VStack(spacing: 0) {
                // Header Row
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        if isExpanded {
                            expandedCategories.remove(category.id.uuidString)
                        } else {
                            expandedCategories.insert(category.id.uuidString)
                        }
                    }
                    // If clicking header, we select the category context
                    if selectedCategoryID != category.id.uuidString {
                        selectedCategoryID = category.id.uuidString
                        selectedLocationID = nil
                    }
                } label: {
                    HStack(spacing: 12) { // Increased spacing for chevron
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .frame(width: 16) // Fixed width for alignment
                        
                        Text(category.emoji)
                            .font(.system(size: 16)) // Ensure emoji size consistency
                        
                        Text(category.name)
                            .font(DesignSystem.Typography.body)
                            .foregroundColor(isHeaderHighlighted ? .white : DesignSystem.Colors.primary) // Contrast fix
                        
                        Spacer()
                        
                        Text("\(category.totalItemCount)")
                            .font(DesignSystem.Typography.caption)
                            .monospacedDigit()
                            .foregroundColor(isHeaderHighlighted ? .white.opacity(0.8) : DesignSystem.Colors.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isHeaderHighlighted ? DesignSystem.Colors.accent : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8) // Outer padding for row
                .contextMenu {
                     Button("Duplicate Category") {
                         duplicateCategory(category)
                     }
                     Divider()
                     Button("Delete Category", role: .destructive) {
                         deleteCategory(category)
                     }
                 }

                // Children
                if isExpanded {
                    VStack(spacing: 2) {
                        // "All Locations" Row
                        let isAllSelected = isCategorySelected && selectedLocationID == nil
                        
                        Button {
                            selectedCategoryID = category.id.uuidString
                            selectedLocationID = nil
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "tray.2")
                                    .font(.system(size: 14))
                                    .frame(width: 16)
                                    .foregroundColor(isAllSelected ? .white : .secondary)
                                Text("All Locations")
                                    .font(DesignSystem.Typography.body)
                                    .foregroundColor(isAllSelected ? .white : DesignSystem.Colors.primary)
                                Spacer()
                            }
                            .padding(.leading, 40) // Indent (12+16+12)
                            .padding(.vertical, 6)
                            .padding(.trailing, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(isAllSelected ? DesignSystem.Colors.accent : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 8)

                        // Locations
                        ForEach(category.locations.sorted(by: { $0.name < $1.name })) { location in
                            let isLocSelected = selectedLocationID == location.id.uuidString
                            
                            Button {
                                selectedCategoryID = category.id.uuidString
                                selectedLocationID = location.id.uuidString
                            } label: {
                                HStack(spacing: 12) {
                                    Text(location.emoji)
                                        .frame(width: 16, alignment: .center)
                                        .font(.system(size: 14))
                                    Text(location.name)
                                        .font(DesignSystem.Typography.body)
                                        .foregroundColor(isLocSelected ? .white : DesignSystem.Colors.primary)
                                    Spacer()
                                    Text("\(location.items.count)")
                                        .font(DesignSystem.Typography.caption)
                                        .monospacedDigit()
                                        .foregroundColor(isLocSelected ? .white.opacity(0.8) : DesignSystem.Colors.secondary)
                                }
                                .padding(.leading, 40)
                                .padding(.vertical, 6)
                                .padding(.trailing, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(isLocSelected ? DesignSystem.Colors.accent : Color.clear)
                                )
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 8)
                            .if(dragEnabled && coordinator.isManager) { view in
                                view.onDrop(of: [.text], isTargeted: nil) { providers in
                                    guard let provider = providers.first else { return false }
                                    _ = provider.loadObject(ofClass: NSString.self) { nsString, _ in
                                        guard let string = nsString as? String,
                                              let itemID = UUID(uuidString: string) else { return }
                                        DispatchQueue.main.async {
                                            _ = moveItemToLocation(itemID: itemID, targetLocation: location)
                                        }
                                    }
                                    return true
                                }
                            }
                            .contextMenu {
                                Button("Delete Location", role: .destructive) {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        if selectedLocationID == location.id.uuidString {
                                            selectedLocationID = nil
                                        }
                                        modelContext.delete(location)
                                        try? modelContext.save()
                                    }
                                }
                            }
                        }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
    }

    private func moveItemToLocation(itemID: UUID, targetLocation: InventoryLocation) -> Bool {
        guard let item = allInventoryItems.first(where: { $0.id == itemID }),
              item.location?.id != targetLocation.id else { return false }

        item.location = targetLocation

        do {
            try modelContext.save()
            DesignSystem.HapticFeedback.trigger(.success)
            forceRefreshID = UUID()
        } catch {
            print("Failed to move item: \(error)")
            DesignSystem.HapticFeedback.trigger(.error)
        }
        return true
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
        .padding(.vertical, DesignSystem.Spacing.grid_2)
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
    @Query private var settings: [AppSettings]

    private var dragEnabled: Bool {
        settings.first?.enableDragAndDrop ?? true
    }

    @State private var editingItem: InventoryItem?
    @State private var showingAddLocation = false
    @State private var newLocationName = ""
    @State private var newLocationEmoji = "📍"
    @State private var showingLocationPicker = false
    @State private var showingAddItemSheet = false
    @State private var addItemLocationID: String?
    @Binding var selectedLocationFilterID: String?
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

    @State private var editingStockItem: InventoryItem?

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
            .overlay {
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
                }
            }
        }
        .macPagePadding(horizontal: DesignSystem.Spacing.grid_1, vertical: DesignSystem.Spacing.grid_1)
        .sheet(item: $editingItem) { item in
            ItemSettingsSheet(item: item)
                .frame(minWidth: 480, idealWidth: 520, minHeight: 560, idealHeight: 620)
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
                .formStyle(.grouped)
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
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(width: 150, alignment: .leading) // Reduced width
                .background(
                    Capsule()
                        .fill(DesignSystem.Colors.surface.opacity(0.8))
                )
            }
            .fixedSize() // Prevent expansion
            .menuStyle(.borderlessButton)
        }
        .padding(.horizontal, DesignSystem.Spacing.grid_2)
        .padding(.vertical, DesignSystem.Spacing.grid_2)
        .frame(height: 60) // Fixed height for header container
    }

    @ViewBuilder
    private var detailRows: some View {
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

    private func itemRow(_ record: MacCategoryItemRecord) -> some View {
        let isLowStock = record.item.stockLevel <= record.item.parLevel

        return HStack(spacing: 12) {
            if dragEnabled && coordinator.isManager {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.tertiary)
                    .frame(width: 20, height: 30)
                    .contentShape(Rectangle())
                    .onDrag {
                        NSItemProvider(object: record.item.id.uuidString as NSString)
                    }
                    .help("Drag to move to another location")
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(record.item.name)
                    .font(DesignSystem.Typography.headline)
                    .foregroundColor(DesignSystem.Colors.primary)

                HStack(spacing: 6) {
                    Text(record.item.unitType)
                    Text("•")
                    Text("Min \(formattedQuantity(record.item.parLevel)) \(record.item.unitType)")
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
                .contentTransition(.numericText(value: NSDecimalNumber(decimal: record.item.stockLevel).doubleValue))
                .animation(.easeInOut(duration: 0.2), value: record.item.stockLevel)
                .onTapGesture {
                    if coordinator.isManager {
                        editingStockItem = record.item
                    }
                }
                .popover(isPresented: Binding(
                    get: { editingStockItem?.id == record.item.id },
                    set: { if !$0 { editingStockItem = nil } }
                )) {
                    VStack(spacing: 12) {
                        Text("Update Stock")
                            .font(.headline)
                        
                        TextField("Quantity", value: Binding(
                            get: { record.item.stockLevel },
                            set: { record.item.stockLevel = max(0, $0) }
                        ), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        .multilineTextAlignment(.center)
                        .onSubmit {
                            editingStockItem = nil
                        }
                        
                        HStack {
                            Button("-1") {
                                if record.item.stockLevel >= 1 {
                                    record.item.stockLevel -= 1
                                }
                            }
                            Button("+1") {
                                record.item.stockLevel += 1
                            }
                        }
                    }
                    .padding()
                    .frame(width: 160)
                    .presentationCompactAdaptation(.popover)
                    .onDisappear {
                        do {
                            try modelContext.save()
                        } catch {
                             print("Failed to save stock update: \(error)")
                        }
                    }
                }
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

    private func formattedQuantity(_ value: Decimal) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
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
    @Query private var settings: [AppSettings]
    @Query(sort: \InventoryItem.name) private var allInventoryItems: [InventoryItem]
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

    private var dragEnabled: Bool {
        settings.first?.enableDragAndDrop ?? true
    }

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
                .frame(minWidth: 480, idealWidth: 520, minHeight: 560, idealHeight: 620)
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
                    canOpenSettings: coordinator.isManager,
                    showDragHandle: dragEnabled && coordinator.isManager
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
                // .onDrag moved inside InventoryItemRow drag handle
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
    let showDragHandle: Bool
    let onTapName: () -> Void
    let onEditAmountOnHand: () -> Void
    let onToggleHidden: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if showDragHandle {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.tertiary)
                    .frame(width: 20, height: 30)
                    .contentShape(Rectangle())
                    .onDrag {
                        NSItemProvider(object: item.id.uuidString as NSString)
                    }
                    .help("Drag to move to another location")
            }
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

                            Text("Min \(formatValue(item.parLevel)) \(item.unitType)")
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
                            .contentTransition(.numericText(value: NSDecimalNumber(decimal: item.stockLevel).doubleValue))
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
                    .contentTransition(.numericText(value: NSDecimalNumber(decimal: item.stockLevel).doubleValue))
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
        // Simple logic for drag/buttons - assuming 1 or 0.1 step
        let step = Decimal(direction) // Simplified step
        let newLevel = max(0, item.stockLevel + step)
        withAnimation(.easeInOut(duration: 0.2)) {
            item.stockLevel = newLevel
            item.amountOnHand = newLevel
        }
    }
    
    private func formatValue(_ val: Decimal) -> String {
        val.formatted(.number.precision(.fractionLength(0...2)))
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
    @State private var price = ""
    
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
                    TextField("Price per Unit (optional)", text: $price)
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
            .formStyle(.grouped)
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
                            stockLevel: Decimal(clampedOnHand),
                            parLevel: Decimal(parValue),
                            unitType: selectedUnit.rawValue,
                            baseUnit: selectedUnit.rawValue, // Default to same unit for simple add
                            amountOnHand: Decimal(clampedOnHand),
                            vendor: trimmedVendor.isEmpty ? nil : trimmedVendor,
                            pricePerUnit: Double(price) == nil ? nil : Decimal(Double(price)!)
                        )
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
        return Decimal(value).formatted(.number.precision(.fractionLength(0...1)))
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
            initialValue: item.stockLevel.formatted(.number.precision(.fractionLength(0...1)))
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
            .formStyle(.grouped)
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
        let clampedAmount = max(0, Decimal(parsedAmount))
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
            .formStyle(.grouped)
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
                    .disabled(categoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
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
            .formStyle(.grouped)
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
                    .disabled(locationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
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
    @State private var price: String
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
        _stockLevel = State(initialValue: item.stockLevel == 0 ? "" : item.stockLevel.formatted(.number.precision(.fractionLength(0...1))))
        _parLevel = State(initialValue: item.parLevel == 0 ? "" : item.parLevel.formatted(.number.precision(.fractionLength(0...1))))
        _selectedUnit = State(initialValue: UnitType(rawValue: item.unitType) ?? .units)
        _vendor = State(initialValue: item.vendor ?? "")
        _price = State(initialValue: item.pricePerUnit == nil ? "" : item.pricePerUnit!.formatted(.number.precision(.fractionLength(2))))
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
                    TextField("Price per Unit (optional)", text: $price)
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
            .formStyle(.grouped)
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
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 520, minHeight: 560, idealHeight: 620)
        #else
        .presentationDetents([.large])
        #endif
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
        item.stockLevel = Decimal(clampedStock)
        item.amountOnHand = Decimal(clampedStock)
        item.parLevel = Decimal(clampedPar)
        item.unitType = selectedUnit.rawValue
        item.vendor = trimmedVendor.isEmpty ? nil : trimmedVendor
        item.pricePerUnit = Double(price) == nil ? nil : Decimal(Double(price)!)
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
        return Decimal(value).formatted(.number.precision(.fractionLength(0...1)))
    }
}

extension NumberFormatter {
    static var decimalFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimum = 0
        formatter.maximumFractionDigits = 2
        return formatter
    }
}
