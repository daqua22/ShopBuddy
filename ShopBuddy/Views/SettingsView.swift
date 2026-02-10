//
//  SettingsView.swift
//  ShopBuddy
//
//  Created by Dan on 1/30/26.
//

import SwiftUI
import SwiftData

// MARK: - App Theme

enum AppTheme: String, CaseIterable, Identifiable {
    case system   = "System"
    case light    = "Light"
    case dark     = "Dark"
    case midnight = "Midnight"
    case ocean    = "Ocean"
    case forest   = "Forest"

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:   return nil
        case .light:    return .light
        case .dark, .midnight, .ocean, .forest: return .dark
        }
    }

    /// Accent tint applied app-wide for this theme.
    var accentColor: Color {
        switch self {
        case .system:   return .accentColor
        case .light:    return Color(red: 0.20, green: 0.40, blue: 0.85) // vivid blue
        case .dark:     return Color(red: 0.40, green: 0.60, blue: 1.00) // soft blue
        case .midnight: return Color(red: 0.65, green: 0.55, blue: 1.00) // lavender
        case .ocean:    return Color(red: 0.20, green: 0.75, blue: 0.80) // teal
        case .forest:   return Color(red: 0.35, green: 0.75, blue: 0.45) // green
        }
    }

    var icon: String {
        switch self {
        case .system:   return "gearshape"
        case .light:    return "sun.max.fill"
        case .dark:     return "moon.fill"
        case .midnight: return "moon.stars.fill"
        case .ocean:    return "water.waves"
        case .forest:   return "leaf.fill"
        }
    }

    var subtitle: String {
        switch self {
        case .system:   return "Matches macOS appearance"
        case .light:    return "Clean, bright workspace"
        case .dark:     return "Easy on the eyes"
        case .midnight: return "Deep purple accents"
        case .ocean:    return "Cool teal tones"
        case .forest:   return "Calm green palette"
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
        NavigationStack {
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

                // MARK: Inventory Permissions
                Section("Inventory Permissions") {
                    if let setting = settings.first {
                        Toggle("Employees can change stock levels", isOn: Bindable(setting).allowEmployeeInventoryEdit)
                    }
                }
                
                // MARK: Account
                Section("Account") {
                    LabeledContent("Role", value: "Manager")
                }

                // MARK: About
                Section("About") {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .onAppear {
                if settings.isEmpty {
                    modelContext.insert(AppSettings())
                }
            }
        }
    }
}
