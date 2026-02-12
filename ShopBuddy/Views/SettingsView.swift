//
//  SettingsView.swift
//  ShopBuddy
//
//  Created by Dan on 1/30/26.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - App Theme

enum AppTheme: String, CaseIterable, Identifiable {
    case system    = "System"
    case light     = "Light"
    case graphite  = "Graphite"
    case dark      = "Dark"
    case midnight  = "Midnight"
    case ocean     = "Ocean"
    case forest    = "Forest"

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:   return nil
        case .light:    return .light
        case .graphite: return .dark
        case .dark, .midnight, .ocean, .forest: return .dark
        }
    }

    /// Accent tint applied app-wide for this theme.
    var accentColor: Color {
        switch self {
        case .system:    return .accentColor
        case .light:     return Color(red: 0.20, green: 0.40, blue: 0.85) // vivid blue
        case .graphite:  return Color(red: 0.65, green: 0.68, blue: 0.72) // warm silver
        case .dark:      return Color(red: 0.40, green: 0.60, blue: 1.00) // soft blue
        case .midnight:  return Color(red: 0.65, green: 0.55, blue: 1.00) // lavender
        case .ocean:     return Color(red: 0.20, green: 0.75, blue: 0.80) // teal
        case .forest:    return Color(red: 0.35, green: 0.75, blue: 0.45) // green
        }
    }

    var icon: String {
        switch self {
        case .system:    return "gearshape"
        case .light:     return "sun.max.fill"
        case .graphite:  return "circle.lefthalf.filled"
        case .dark:      return "moon.fill"
        case .midnight:  return "moon.stars.fill"
        case .ocean:     return "water.waves"
        case .forest:    return "leaf.fill"
        }
    }

    var subtitle: String {
        switch self {
        case .system:    return "Matches macOS appearance"
        case .light:     return "Clean, bright workspace"
        case .graphite:  return "Neutral grey, easy balance"
        case .dark:      return "Easy on the eyes"
        case .midnight:  return "Deep purple accents"
        case .ocean:     return "Cool teal tones"
        case .forest:    return "Calm green palette"
        }
    }

    /// Background tint overlaid on the glass for custom theme colors.
    var backgroundOverlay: Color {
        switch self {
        case .graphite: return Color(white: 0.32, opacity: 0.35)
        default:        return .clear
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settings: [AppSettings]

    @AppStorage("appTheme") private var selectedTheme: String = AppTheme.system.rawValue

    private var currentTheme: AppTheme {
        AppTheme(rawValue: selectedTheme) ?? .system
    }

    var body: some View {
        Form {
            // MARK: Appearance
            Section("Appearance") {
                Picker("Theme", selection: $selectedTheme) {
                    ForEach(AppTheme.allCases) { theme in
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(theme.rawValue)
                                Text(theme.subtitle)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: theme.icon)
                            .foregroundColor(theme.accentColor)
                        }
                        .tag(theme.rawValue)
                    }
                }
                .pickerStyle(.inline)
            }

            // MARK: Checklists
            Section("Checklists") {
                if let setting = settings.first {
                    Toggle("Only clocked-in employees can complete tasks", isOn: Bindable(setting).requireClockInForChecklists)
                }
            }

            // MARK: Inventory Permissions
            Section("Inventory Permissions") {
                if let setting = settings.first {
                    Toggle("Employees can change stock levels", isOn: Bindable(setting).allowEmployeeInventoryEdit)
                }
            }

            // MARK: Drag & Drop
            Section {
                if let setting = settings.first {
                    Toggle("Enable Drag & Drop", isOn: Bindable(setting).enableDragAndDrop)
                }
            } header: {
                Text("Drag & Drop")
            } footer: {
                Text("Reorder checklist tasks and move inventory items between locations by dragging")
            }

            // MARK: Operating Schedule
            Section("Operating Schedule") {
                if let setting = settings.first {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Operating Days")
                            .font(DesignSystem.Typography.subheadline)
                            .foregroundColor(DesignSystem.Colors.secondary)
                        HStack(spacing: 6) {
                            ForEach(AppSettings.weekdaySymbols, id: \.index) { day in
                                let isOn = setting.operatingDays.contains(day.index)
                                Button {
                                    var days = setting.operatingDays
                                    if isOn { days.remove(day.index) } else { days.insert(day.index) }
                                    setting.operatingDays = days
                                } label: {
                                    Text(day.short)
                                        .font(.system(size: 12, weight: .semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 6)
                                        .background(isOn ? DesignSystem.Colors.accent.opacity(0.25) : DesignSystem.Colors.surface.opacity(0.3))
                                        .foregroundColor(isOn ? DesignSystem.Colors.accent : DesignSystem.Colors.secondary)
                                        .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.vertical, 4)

                    DatePicker("Opens at", selection: Bindable(setting).openTime, displayedComponents: .hourAndMinute)
                    DatePicker("Closes at", selection: Bindable(setting).closeTime, displayedComponents: .hourAndMinute)
                }
            }
            
            // MARK: Account
            Section("Account") {
                LabeledContent("Role", value: "Manager")
            }

            // MARK: Data Management
            Section("Data Management") {
                Button {
                    exportBackup()
                } label: {
                    Label("Export Full Backup (JSON)", systemImage: "square.and.arrow.up")
                }
                
                Button {
                    showingBackupImporter = true
                } label: {
                    Label("Restore from Backup", systemImage: "square.and.arrow.down")
                }
                
                Button {
                    exportCSV()
                } label: {
                    Label("Export Inventory (CSV)", systemImage: "tablecells")
                }
                
                Button {
                    showingCSVImporter = true
                } label: {
                    Label("Import from Spreadsheet", systemImage: "square.and.arrow.down.on.square")
                }
            }

            // MARK: About
            Section("About") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
            }

            // MARK: Developer
            Section("Developer") {
                Button("Reset All Data", role: .destructive) {
                    showingResetConfirmation = true
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .alert("Reset Data", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                resetAllData()
            }
        } message: {
            Text("This will permanently delete all data. This action cannot be undone.")
        }
        .alert("Reset Complete", isPresented: $showingResetSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("All data has been successfully deleted.")
        }
        .alert("Reset Failed", isPresented: $showingResetError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(resetErrorMessage)
        }
        // File Exporters/Importers
        .fileExporter(isPresented: $showingBackupExporter, document: backupDocument, contentType: .json, defaultFilename: "ShopBuddy_Backup_\(Date().formatted(.iso8601))") { result in
            if case .failure(let error) = result {
                print("Export failed: \(error.localizedDescription)")
            }
        }
        .fileImporter(isPresented: $showingBackupImporter, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                restoreBackup(from: url)
            case .failure(let error):
                importErrorMessage = error.localizedDescription
                showingImportError = true
            }
        }
        .fileExporter(isPresented: $showingCSVExporter, document: csvDocument, contentType: .commaSeparatedText, defaultFilename: "ShopBuddy_Inventory_\(Date().formatted(.iso8601))") { result in
             if case .failure(let error) = result {
                 print("Export failed: \(error.localizedDescription)")
             }
         }
        .fileImporter(isPresented: $showingCSVImporter, allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText]) { result in
            switch result {
            case .success(let url):
                loadSpreadsheetFile(from: url)
            case .failure(let error):
                importErrorMessage = error.localizedDescription
                showingImportError = true
            }
        }
        .sheet(item: $spreadsheetFileData) { data in
            SpreadsheetImportView(fileData: data.data)
        }
        .alert("Import/Restore Complete", isPresented: $showingImportSuccess) {
             Button("OK", role: .cancel) { }
         } message: {
             Text("Operation completed successfully.")
         }
        .alert("Import Failed", isPresented: $showingImportError) {
             Button("OK", role: .cancel) { }
         } message: {
             Text(importErrorMessage)
         }
        .onAppear {
            if settings.isEmpty {
                modelContext.insert(AppSettings())
            }
        }
    }

    @State private var showingResetConfirmation = false
    @State private var showingResetSuccess = false
    @State private var showingResetError = false
    @State private var resetErrorMessage = ""

    private func resetAllData() {
        do {
            // Inventory
            try modelContext.fetch(FetchDescriptor<InventoryItem>()).forEach { modelContext.delete($0) }
            try modelContext.fetch(FetchDescriptor<InventoryLocation>()).forEach { modelContext.delete($0) }
            try modelContext.fetch(FetchDescriptor<InventoryCategory>()).forEach { modelContext.delete($0) }
            
            // Checklists
            try modelContext.fetch(FetchDescriptor<ChecklistTask>()).forEach { modelContext.delete($0) }
            try modelContext.fetch(FetchDescriptor<ChecklistTemplate>()).forEach { modelContext.delete($0) }
            
            // Daily & Tips
            try modelContext.fetch(FetchDescriptor<DailyTask>()).forEach { modelContext.delete($0) }
            try modelContext.fetch(FetchDescriptor<DailyTips>()).forEach { modelContext.delete($0) }
            
            // Payroll & Shifts
            try modelContext.fetch(FetchDescriptor<PayPeriod>()).forEach { modelContext.delete($0) }
            try modelContext.fetch(FetchDescriptor<Shift>()).forEach { modelContext.delete($0) }
            try modelContext.fetch(FetchDescriptor<Employee>()).forEach { modelContext.delete($0) }
            
            // Settings
            try modelContext.fetch(FetchDescriptor<AppSettings>()).forEach { modelContext.delete($0) }
            
            try modelContext.save()
            showingResetSuccess = true
            
            // Re-initialize settings
            modelContext.insert(AppSettings())
        } catch {
            print("Failed to reset data: \(error)")
            resetErrorMessage = error.localizedDescription
            showingResetError = true
        }
    }

    // MARK: - Data Management State
    @State private var showingBackupExporter = false
    @State private var showingBackupImporter = false
    @State private var backupDocument: BackupFile?
    
    @State private var showingCSVExporter = false
    @State private var showingCSVImporter = false
    @State private var csvDocument: CSVFile?
    
    @State private var showingImportSuccess = false
    @State private var showingImportError = false
    @State private var importErrorMessage = ""
    
    // MARK: - Handlers
    
    private func exportBackup() {
        do {
            let data = try BackupService(modelContext: modelContext).exportData()
            backupDocument = BackupFile(initialData: data)
            showingBackupExporter = true
        } catch {
            importErrorMessage = "Export failed: \(error.localizedDescription)"
            showingImportError = true
        }
    }
    
    private func restoreBackup(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            importErrorMessage = "Permission denied to access file."
            showingImportError = true
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        do {
            let data = try Data(contentsOf: url)
            try BackupService(modelContext: modelContext).restoreData(from: data)
            showingImportSuccess = true
            // Re-init happens inside restoreData via clearAllData() + inserts
        } catch {
            importErrorMessage = "Restore failed: \(error.localizedDescription)"
            showingImportError = true
        }
    }
    
    private func exportCSV() {
        do {
            let data = try CSVService(modelContext: modelContext).exportInventory()
            csvDocument = CSVFile(initialData: data)
            showingCSVExporter = true
        } catch {
            importErrorMessage = "Export failed: \(error.localizedDescription)"
            showingImportError = true
        }
    }
    
    private func loadSpreadsheetFile(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
             importErrorMessage = "Permission denied to access file."
             showingImportError = true
             return
         }
         defer { url.stopAccessingSecurityScopedResource() }
         
         do {
             let data = try Data(contentsOf: url)
             spreadsheetFileData = SpreadsheetFileData(data: data)
         } catch {
             importErrorMessage = "Could not read file: \(error.localizedDescription)"
             showingImportError = true
         }
    }
    
    @State private var spreadsheetFileData: SpreadsheetFileData?
}

/// Wrapper to make raw Data identifiable for .sheet(item:)
struct SpreadsheetFileData: Identifiable {
    let id = UUID()
    let data: Data
}
