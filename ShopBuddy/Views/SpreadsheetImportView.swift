import SwiftUI
import SwiftData

/// A sheet that lets users review and adjust auto-detected column mappings
/// before importing a spreadsheet into inventory.
struct SpreadsheetImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let fileData: Data
    @State private var spreadsheet: ParsedSpreadsheet?
    @State private var parseError: String?
    @State private var isImporting = false
    @State private var importSuccess = false
    @State private var importError: String?
    @Query(sort: \InventoryCategory.name) private var allCategories: [InventoryCategory]
    @Query(sort: \InventoryLocation.name) private var allLocations: [InventoryLocation]

    @State private var targetMode: ImportTargetMode = .csvColumns
    @State private var selectedCategory: InventoryCategory?
    @State private var selectedLocation: InventoryLocation?

    enum ImportTargetMode: String, CaseIterable, Identifiable {
        case csvColumns = "Use CSV Data"
        case specificCategory = "Specific Category"
        case specificLocation = "Specific Location"
        var id: String { rawValue }
    }
    var body: some View {
        NavigationStack {
            Group {
                if let error = parseError {
                    errorView(error)
                } else if let sheet = spreadsheet {
                    mappingContent(sheet)
                } else {
                    ProgressView("Analyzing spreadsheet…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Import Spreadsheet")
            #if os(macOS)
            .frame(minWidth: 600, minHeight: 450)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        performImport()
                    }
                    .disabled(spreadsheet == nil || !hasItemNameMapping || isImporting)
                }
            }
            .alert("Import Complete", isPresented: $importSuccess) {
                Button("Done") { dismiss() }
            } message: {
                let count = spreadsheet?.rowCount ?? 0
                Text("Successfully imported \(count) items into your inventory.")
            }
            .alert("Import Failed", isPresented: .constant(importError != nil)) {
                Button("OK") { importError = nil }
            } message: {
                Text(importError ?? "")
            }
        }
        .task {
            parseFile()
        }
    }

    // MARK: - Computed

    private var hasItemNameMapping: Bool {
        spreadsheet?.mappings.contains(where: { $0.field == .itemName }) ?? false
    }

    // MARK: - Subviews

    @ViewBuilder
    private func mappingContent(_ sheet: ParsedSpreadsheet) -> some View {
        VStack(spacing: 0) {
            // Header Stats
            HStack {
                Label("\(sheet.headers.count) columns", systemImage: "tablecells")
                Spacer()
                Label("\(sheet.rowCount) rows", systemImage: "list.bullet")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Mappings List + Preview in a scrollable area
            List {
                // Destination Section
                Section("Destination") {
                    Picker("Import Into", selection: $targetMode) {
                        ForEach(ImportTargetMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    
                    if targetMode == .specificCategory {
                        Picker("Category", selection: $selectedCategory) {
                            Text("Select Category...").tag(nil as InventoryCategory?)
                            ForEach(allCategories) { cat in
                                Text(cat.name).tag(cat as InventoryCategory?)
                            }
                        }
                    }
                    
                    if targetMode == .specificLocation {
                        Picker("Location", selection: $selectedLocation) {
                            Text("Select Location...").tag(nil as InventoryLocation?)
                            ForEach(allLocations) { loc in
                                Text(loc.name + (loc.category != nil ? " (\(loc.category!.name))" : "")).tag(loc as InventoryLocation?)
                            }
                        }
                    }
                }

                // Column Mappings Section
                Section {
                    ForEach(sheet.mappings.indices, id: \.self) { index in
                        mappingRow(index: index, mapping: sheet.mappings[index])
                    }
                } header: {
                    Text("Column Assignments")
                } footer: {
                    if !hasItemNameMapping {
                        Label("\"Item Name\" must be assigned to at least one column.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    } else {
                        Text("Columns marked \"Skip\" will be ignored during import.")
                    }
                }

                // Data Preview Section
                Section("Data Preview") {
                    ScrollView(.horizontal) {
                        VStack(alignment: .leading, spacing: 0) {
                            // Header row
                            HStack(spacing: 0) {
                                ForEach(sheet.headers.indices, id: \.self) { i in
                                    let mapping = sheet.mappings[i]
                                    Text(mapping.field == .skip ? sheet.headers[i] : mapping.field.rawValue)
                                        .font(.caption.bold())
                                        .foregroundStyle(mapping.field == .skip ? .secondary : .primary)
                                        .frame(width: 120, alignment: .leading)
                                        .padding(.vertical, 6)
                                        .padding(.horizontal, 4)
                                }
                            }
                            .background(Color.secondary.opacity(0.1))

                            Divider()

                            // Data rows
                            ForEach(sheet.previewRows.indices, id: \.self) { rowIdx in
                                HStack(spacing: 0) {
                                    ForEach(sheet.headers.indices, id: \.self) { colIdx in
                                        let value = colIdx < sheet.previewRows[rowIdx].count ? sheet.previewRows[rowIdx][colIdx] : ""
                                        let isSkipped = sheet.mappings[colIdx].field == .skip
                                        Text(value)
                                            .font(.caption)
                                            .foregroundStyle(isSkipped ? .tertiary : .primary)
                                            .lineLimit(1)
                                            .frame(width: 120, alignment: .leading)
                                            .padding(.vertical, 4)
                                            .padding(.horizontal, 4)
                                    }
                                }
                                if rowIdx < sheet.previewRows.count - 1 {
                                    Divider()
                                }
                            }
                        }
                    }
                }
            }
            #if os(macOS)
            .listStyle(.inset(alternatesRowBackgrounds: true))
            #endif
        }
    }

    @ViewBuilder
    private func mappingRow(index: Int, mapping: ColumnMapping) -> some View {
        HStack {
            // CSV Header
            VStack(alignment: .leading, spacing: 2) {
                Text(mapping.headerText)
                    .font(.body.weight(.medium))

                // Confidence indicator
                if mapping.field != .skip {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(confidenceColor(mapping.confidence))
                            .frame(width: 6, height: 6)
                        Text(confidenceLabel(mapping.confidence))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Field Picker
            Picker("", selection: fieldBinding(for: index)) {
                ForEach(InventoryField.allCases) { field in
                    Text(field.rawValue).tag(field)
                }
            }
            .labelsHidden()
            #if os(macOS)
            .frame(width: 160)
            #endif
        }
    }

    @ViewBuilder
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.yellow)
            Text("Could not parse file")
                .font(.title3.bold())
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func fieldBinding(for index: Int) -> Binding<InventoryField> {
        Binding(
            get: { spreadsheet?.mappings[index].field ?? .skip },
            set: { newField in
                spreadsheet?.mappings[index].field = newField
            }
        )
    }

    private func confidenceColor(_ score: Double) -> Color {
        if score >= 0.8 { return .green }
        if score >= 0.5 { return .orange }
        return .red
    }

    private func confidenceLabel(_ score: Double) -> String {
        if score >= 0.8 { return "High confidence" }
        if score >= 0.5 { return "Best guess" }
        return "Low confidence"
    }

    // MARK: - Actions

    private func parseFile() {
        do {
            let service = CSVService(modelContext: modelContext)
            spreadsheet = try service.parseSpreadsheet(from: fileData)
        } catch {
            parseError = error.localizedDescription
        }
    }

    private func performImport() {
        guard var sheet = spreadsheet else { return }

        // Validate item name mapping
        guard sheet.mappings.contains(where: { $0.field == .itemName }) else {
            importError = "Please assign an 'Item Name' column before importing."
            return
        }

        isImporting = true
        do {
            let service = CSVService(modelContext: modelContext)
            
            var targetCat: InventoryCategory?
            var targetLoc: InventoryLocation?
            
            switch targetMode {
            case .csvColumns:
                break
            case .specificCategory:
                targetCat = selectedCategory
            case .specificLocation:
                targetLoc = selectedLocation
            }
            
            try service.importWithMappings(sheet, targetCategory: targetCat, targetLocation: targetLoc)
            importSuccess = true
        } catch {
            importError = error.localizedDescription
        }
        isImporting = false
    }
}
