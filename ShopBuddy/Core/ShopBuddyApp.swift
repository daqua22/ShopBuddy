//
//  ShopBuddyApp.swift
//  ShopBuddy
//
//  Created by Dan on 1/29/26.
//

import SwiftUI
import SwiftData

@main
struct ShopBuddyApp: App {
    
    @State private var coordinator = AppCoordinator()
    @AppStorage("appTheme") private var selectedTheme: String = AppTheme.system.rawValue

    private var currentTheme: AppTheme {
        AppTheme(rawValue: selectedTheme) ?? .system
    }

    let modelContainer: ModelContainer

    init() {
        let schema = Schema([
            Employee.self,
            Shift.self,
            InventoryCategory.self,
            InventoryLocation.self,
            InventoryItem.self,
            ChecklistTemplate.self,
            ChecklistTask.self,
            DailyTips.self,
            DailyTask.self,
            PayrollPeriod.self,
            AppSettings.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: false)
        do {
            let container = try ModelContainer(for: schema, configurations: config)

            self.modelContainer = container
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(coordinator)
                .modelContainer(modelContainer)
                .preferredColorScheme(currentTheme.colorScheme)
                .tint(currentTheme.accentColor)
                #if os(macOS)
                // Force the NSWindow to be transparent
                .background(
                    WindowAccessor { window in
                        window.isOpaque = false
                        window.backgroundColor = .clear
                        window.isMovableByWindowBackground = true
                        // Critical: make contentView layer transparent too
                        window.contentView?.wantsLayer = true
                        window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
                        // titlebarAppearsTransparent is handled by FullScreenObserver
                    }
                )
                #endif
        }
        #if os(macOS)
        .commands {
            SidebarCommands()
            ShopBuddyInventoryCommands()
        }
        #endif
    }
}

#if os(macOS)
private struct ShopBuddyInventoryCommands: Commands {
    var body: some Commands {
        CommandMenu("Inventory") {
            Button("Add Category") {
                NotificationCenter.default.post(name: .shopBuddyInventoryAddCategoryCommand, object: nil)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("Add Location") {
                NotificationCenter.default.post(name: .shopBuddyInventoryAddLocationCommand, object: nil)
            }
            .keyboardShortcut("n", modifiers: [.command, .option])

            Button("Add Item") {
                NotificationCenter.default.post(name: .shopBuddyInventoryAddItemCommand, object: nil)
            }
            .keyboardShortcut("n", modifiers: [.command])

            Divider()

            Button("Focus Search") {
                NotificationCenter.default.post(name: .shopBuddyInventoryFocusSearchCommand, object: nil)
            }
            .keyboardShortcut("f", modifiers: [.command])

            Button("Delete Selection") {
                NotificationCenter.default.post(name: .shopBuddyInventoryDeleteSelectionCommand, object: nil)
            }
            .keyboardShortcut(.delete, modifiers: [])
        }
    }
}
#endif
