import Foundation
import SwiftData
import SwiftUI

// MARK: - Importable Field

/// Every inventory field that a CSV column can map to.
enum InventoryField: String, CaseIterable, Identifiable {
    case itemName     = "Item Name"
    case category     = "Category"
    case location     = "Location"
    case unit         = "Unit"
    case stock        = "Stock Level"
    case parLevel     = "Par Level"
    case amountOnHand = "Amount On Hand"
    case vendor       = "Vendor"
    case pricePerUnit = "Price Per Unit"
    case notes        = "Notes"
    case skip         = "— Skip —"

    var id: String { rawValue }

    /// Keywords used to match CSV header text to this field.
    var keywords: [String] {
        switch self {
        case .itemName:     return ["item", "product", "name", "description", "desc", "sku", "title", "ingredient"]
        case .category:     return ["category", "group", "type", "class", "department", "dept", "project"]
        case .location:     return ["location", "area", "zone", "shelf", "storage", "fridge", "place", "room", "section", "bin"]
        case .unit:         return ["unit", "uom", "measure", "measurement"]
        case .stock:        return ["stock", "qty", "quantity", "count", "level", "on hand", "onhand", "current"]
        case .parLevel:     return ["par", "reorder", "minimum", "min", "threshold", "target"]
        case .amountOnHand: return ["amount", "actual", "physical", "counted"]
        case .vendor:       return ["vendor", "supplier", "distributor", "source", "brand", "manufacturer"]
        case .pricePerUnit: return ["price", "cost", "value", "rate", "ppp", "unit price"]
        case .notes:        return ["note", "notes", "comment", "comments", "memo", "remark", "remarks"]
        case .skip:         return []
        }
    }
}

// MARK: - Column Mapping

/// A single detected column mapping: CSV column index + header → app field.
struct ColumnMapping: Identifiable {
    let id = UUID()
    let columnIndex: Int
    let headerText: String
    var field: InventoryField
    var confidence: Double // 0-1
}

// MARK: - Parsed Spreadsheet

/// Represents a parsed CSV ready for the user to review mappings.
struct ParsedSpreadsheet {
    let headers: [String]
    let rows: [[String]]
    var mappings: [ColumnMapping]

    /// Preview of the first N data rows.
    var previewRows: [[String]] {
        Array(rows.prefix(5))
    }

    var rowCount: Int { rows.count }
}

// MARK: - CSV Service

@MainActor
final class CSVService {
    let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: Export
    func exportInventory() throws -> Data {
        let items = try modelContext.fetch(FetchDescriptor<InventoryItem>())

        var csvString = "Category,Location,Item Name,Unit,Stock,Par Level,Vendor,Price Per Unit,Sort Order\n"

        for item in items {
            let categoryName = item.location?.category?.name ?? "Uncategorized"
            let locationName = item.location?.name ?? "No Location"
            let itemName = escapeCSV(item.name)
            let unit = escapeCSV(item.unitType)
            let stock = "\(item.stockLevel)"
            let par = "\(item.parLevel)"
            let vendor = escapeCSV(item.vendor ?? "")
            let price = item.pricePerUnit != nil ? "\(item.pricePerUnit!)" : ""
            let sortOrder = String(item.sortOrder)

            let row = "\(categoryName),\(locationName),\(itemName),\(unit),\(stock),\(par),\(vendor),\(price),\(sortOrder)\n"
            csvString.append(row)
        }

        return csvString.data(using: .utf8) ?? Data()
    }

    // MARK: - Smart Parse (Phase 1 — detect columns)

    /// Parse a CSV/TSV file and auto-detect column mappings.
    func parseSpreadsheet(from data: Data) throws -> ParsedSpreadsheet {
        guard let content = String(data: data, encoding: .utf8) else {
            throw CSVError.invalidEncoding
        }

        // Detect delimiter (comma, tab, semicolon)
        let delimiter = detectDelimiter(content)

        let rawRows = content.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        guard let headerRow = rawRows.first else {
            throw CSVError.invalidHeader
        }

        let headers = parseRow(headerRow, delimiter: delimiter)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        let dataRows = rawRows.dropFirst().map { parseRow($0, delimiter: delimiter) }

        // Auto-detect mappings
        var mappings = detectMappings(headers: headers)

        // If no "Item Name" was detected, try to guess by looking at data
        if !mappings.contains(where: { $0.field == .itemName }) {
            // Pick the first text-heavy column that isn't already mapped
            for i in 0..<headers.count {
                if mappings[i].field == .skip {
                    let sampleValues = dataRows.prefix(10).compactMap { $0.count > i ? $0[i] : nil }
                    let isTextHeavy = sampleValues.allSatisfy { Double($0) == nil && !$0.isEmpty }
                    if isTextHeavy {
                        mappings[i].field = .itemName
                        mappings[i].confidence = 0.5
                        break
                    }
                }
            }
        }

        return ParsedSpreadsheet(headers: headers, rows: dataRows.map { Array($0) }, mappings: mappings)
    }

    // MARK: - Smart Import (Phase 2 — execute with confirmed mappings)

    func importWithMappings(_ spreadsheet: ParsedSpreadsheet, targetCategory: InventoryCategory? = nil, targetLocation: InventoryLocation? = nil) throws {
        let mappings = spreadsheet.mappings

        // Build field→columnIndex lookup
        var fieldIndex: [InventoryField: Int] = [:]
        for m in mappings where m.field != .skip {
            fieldIndex[m.field] = m.columnIndex
        }

        // Cache existing entities
        let existingCategories = try modelContext.fetch(FetchDescriptor<InventoryCategory>())
        var categoryMap = Dictionary(uniqueKeysWithValues: existingCategories.map { ($0.name.lowercased(), $0) })
        
        // Locations can have same name but different categories.
        // Map: Name -> [Location]
        let existingLocations = try modelContext.fetch(FetchDescriptor<InventoryLocation>())
        var locationMap: [String: [InventoryLocation]] = [:]
        for loc in existingLocations {
            let key = loc.name.lowercased()
            locationMap[key, default: []].append(loc)
        }

        for row in spreadsheet.rows {
            // Extract values by field
            func val(_ field: InventoryField) -> String? {
                guard let idx = fieldIndex[field], idx < row.count else { return nil }
                let v = row[idx].trimmingCharacters(in: .whitespacesAndNewlines)
                return v.isEmpty ? nil : v
            }

            guard let itemName = val(.itemName) else { continue }

            let catName   = val(.category) ?? "Imported"
            let locName   = val(.location) ?? "General"
            let unit      = val(.unit)     ?? "Units"
            
            // Helper for Decimal parsing
            func parseDecimal(_ string: String?) -> Decimal {
                guard let string = string, !string.isEmpty else { return 0 }
                // Try standard decimal conversion
                return Decimal(string: string, locale: Locale(identifier: "en_US")) ?? 0
            }
            
            let stock     = parseDecimal(val(.stock))
            let par       = parseDecimal(val(.parLevel))
            let amount    = parseDecimal(val(.amountOnHand))
            let vendor    = val(.vendor)
            
            var price: Decimal? = nil
            if let pString = val(.pricePerUnit), !pString.isEmpty {
                 price = Decimal(string: pString, locale: Locale(identifier: "en_US"))
            }
            
            let notes     = val(.notes)

            // 1. Determine Category
            let category: InventoryCategory
            
            if let targetLoc = targetLocation {
                // If specific location selected, use its category (or catch-all)
                if let locCat = targetLoc.category {
                    category = locCat
                } else {
                    // Fallback if target location has no category? 
                    // Use targetCategory if provided, else "Imported"
                    if let targetCat = targetCategory {
                        category = targetCat
                    } else {
                        // Create/Find default
                        if let existing = categoryMap["imported"] {
                            category = existing
                        } else {
                            category = InventoryCategory(name: "Imported", emoji: "📦")
                            modelContext.insert(category)
                            categoryMap["imported"] = category
                        }
                    }
                }
            } else if let targetCat = targetCategory {
                // specific category selected
                category = targetCat
            } else {
                // Use CSV
                if let existing = categoryMap[catName.lowercased()] {
                    category = existing
                } else {
                    category = InventoryCategory(name: catName, emoji: "📦")
                    modelContext.insert(category)
                    categoryMap[catName.lowercased()] = category
                }
            }

            // 2. Determine Location
            let location: InventoryLocation
            
            if let targetLoc = targetLocation {
                location = targetLoc
            } else {
                // Look for location (scoped to the determined category)
                let candidates = locationMap[locName.lowercased()] ?? []
                
                if let existing = candidates.first(where: { $0.category?.id == category.id }) {
                    location = existing
                } else {
                    location = InventoryLocation(name: locName, emoji: "📍")
                    location.category = category
                    modelContext.insert(location)
                    locationMap[locName.lowercased(), default: []].append(location)
                }
            }

            // Create item
            let item = InventoryItem(name: itemName, stockLevel: stock, parLevel: par, unitType: unit, baseUnit: unit, amountOnHand: amount, vendor: vendor, pricePerUnit: price, notes: notes)
            item.location = location
            modelContext.insert(item)
        }

        try modelContext.save()
    }

    // MARK: - Legacy Import (kept for backward compatibility)

    func importInventory(from csvData: Data) throws {
        let spreadsheet = try parseSpreadsheet(from: csvData)
        try importWithMappings(spreadsheet)
    }

    // MARK: - Column Detection Engine

    private func detectMappings(headers: [String]) -> [ColumnMapping] {
        var mappings: [ColumnMapping] = []
        var usedFields: Set<InventoryField> = []

        for (index, header) in headers.enumerated() {
            let normalized = header.lowercased()
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            var bestField: InventoryField = .skip
            var bestScore: Double = 0

            for field in InventoryField.allCases where field != .skip && !usedFields.contains(field) {
                let score = matchScore(normalized: normalized, keywords: field.keywords)
                if score > bestScore {
                    bestScore = score
                    bestField = field
                }
            }

            // Require a minimum confidence threshold
            if bestScore < 0.3 {
                bestField = .skip
                bestScore = 0
            }

            if bestField != .skip {
                usedFields.insert(bestField)
            }

            mappings.append(ColumnMapping(columnIndex: index, headerText: header, field: bestField, confidence: bestScore))
        }

        return mappings
    }

    private func matchScore(normalized: String, keywords: [String]) -> Double {
        // Exact match
        for kw in keywords {
            if normalized == kw { return 1.0 }
        }
        // Contains keyword
        for kw in keywords {
            if normalized.contains(kw) { return 0.8 }
        }
        // Keyword contained in normalized (partial)
        for kw in keywords {
            if kw.contains(normalized) && normalized.count >= 3 { return 0.6 }
        }
        return 0
    }

    // MARK: - Delimiter Detection

    private func detectDelimiter(_ content: String) -> Character {
        let firstLine = content.prefix(while: { $0 != "\n" && $0 != "\r" })
        let commaCount = firstLine.filter { $0 == "," }.count
        let tabCount   = firstLine.filter { $0 == "\t" }.count
        let semiCount  = firstLine.filter { $0 == ";" }.count

        if tabCount > commaCount && tabCount > semiCount { return "\t" }
        if semiCount > commaCount && semiCount > tabCount { return ";" }
        return ","
    }

    // MARK: - CSV Helpers

    func escapeCSV(_ text: String) -> String {
        if text.contains(",") || text.contains("\"") || text.contains("\n") {
            let escaped = text.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return text
    }

    func parseRow(_ row: String, delimiter: Character = ",") -> [String] {
        var result: [String] = []
        var current = ""
        var insideQuotes = false

        for char in row {
            if char == "\"" {
                insideQuotes.toggle()
            } else if char == delimiter && !insideQuotes {
                result.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        result.append(current)
        return result
    }
}

// MARK: - Errors

enum CSVError: LocalizedError {
    case invalidEncoding
    case invalidHeader
    case noItemNameColumn

    var errorDescription: String? {
        switch self {
        case .invalidEncoding: return "Could not read file encoding."
        case .invalidHeader:   return "File appears to be empty or has no header row."
        case .noItemNameColumn: return "No column could be identified as 'Item Name'. Please assign it manually."
        }
    }
}
