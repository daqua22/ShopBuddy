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
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(coordinator)
                .modelContainer(for: [
                    Employee.self,
                    Shift.self,
                    InventoryCategory.self,
                    InventoryLocation.self,
                    InventoryItem.self,
                    ChecklistTemplate.self,
                    ChecklistTask.self,
                    DailyTips.self,
                    PayrollPeriod.self,
                    AppSettings.self
                ])
                #if os(iOS)
                .preferredColorScheme(.dark)
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
            .keyboardShortcut("n", modifiers: [.command])

            Button("Add Location") {
                NotificationCenter.default.post(name: .shopBuddyInventoryAddLocationCommand, object: nil)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("Add Item") {
                NotificationCenter.default.post(name: .shopBuddyInventoryAddItemCommand, object: nil)
            }
            .keyboardShortcut("n", modifiers: [.command, .option])

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
