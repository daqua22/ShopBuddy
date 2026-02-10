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

            // MARK: About
            Section("About") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
            }

            // MARK: Developer
            Section("Developer") {
                Button("Reset All Data", role: .destructive) {
                    do {
                        try modelContext.delete(model: Employee.self)
                        try modelContext.delete(model: AppSettings.self)
                    } catch {
                        print("Failed to reset data: \(error)")
                    }
                }
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
