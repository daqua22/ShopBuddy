//
//  PrepItApp.swift
//  PrepIt
//
//  Created by Dan on 1/29/26.
//

import SwiftUI
import SwiftData

@main
struct PrepItApp: App {
    
    @State private var coordinator = AppCoordinator()
    @AppStorage("appTheme") private var selectedTheme: String = AppTheme.system.rawValue

    private var currentTheme: AppTheme {
        AppTheme(rawValue: selectedTheme) ?? .system
    }

    let modelContainer: ModelContainer

    init() {
        self.modelContainer = Self.makeResilientModelContainer()
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
            PrepItInventoryCommands()
        }
        #endif
    }
}

private extension PrepItApp {
    static func makeResilientModelContainer() -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV3.self)
        let storeURL = persistentStoreURL()

        let persistentConfig = ModelConfiguration(
            "PrepIt",
            schema: schema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )

        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: PrepItMigrationPlan.self,
                configurations: [persistentConfig]
            )
        } catch {
            // Recovery path for schema/module-name changes or corrupted local store.
            removeStoreArtifacts(at: storeURL)

            do {
                return try ModelContainer(
                    for: schema,
                    migrationPlan: PrepItMigrationPlan.self,
                    configurations: [persistentConfig]
                )
            } catch {
                let memoryConfig = ModelConfiguration(
                    "PrepIt-InMemory",
                    schema: schema,
                    isStoredInMemoryOnly: true,
                    allowsSave: true,
                    groupContainer: .none,
                    cloudKitDatabase: .none
                )
                do {
                    return try ModelContainer(for: schema, configurations: [memoryConfig])
                } catch {
                    fatalError("Failed to create ModelContainer: \(error)")
                }
            }
        }
    }

    static func persistentStoreURL() -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
        let directory = base.appendingPathComponent("PrepIt", isDirectory: true)
        if !fm.fileExists(atPath: directory.path) {
            try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory.appendingPathComponent("PrepIt.sqlite")
    }

    static func removeStoreArtifacts(at storeURL: URL) {
        let fm = FileManager.default
        let artifacts = [
            storeURL,
            URL(fileURLWithPath: storeURL.path + "-shm"),
            URL(fileURLWithPath: storeURL.path + "-wal")
        ]
        for artifact in artifacts where fm.fileExists(atPath: artifact.path) {
            try? fm.removeItem(at: artifact)
        }
    }
}

#if os(macOS)
private struct PrepItInventoryCommands: Commands {
    var body: some Commands {
        CommandMenu("Inventory") {
            Button("Add Category") {
                NotificationCenter.default.post(name: .prepItInventoryAddCategoryCommand, object: nil)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("Add Location") {
                NotificationCenter.default.post(name: .prepItInventoryAddLocationCommand, object: nil)
            }
            .keyboardShortcut("n", modifiers: [.command, .option])

            Button("Add Item") {
                NotificationCenter.default.post(name: .prepItInventoryAddItemCommand, object: nil)
            }
            .keyboardShortcut("n", modifiers: [.command])

            Divider()

            Button("Focus Search") {
                NotificationCenter.default.post(name: .prepItInventoryFocusSearchCommand, object: nil)
            }
            .keyboardShortcut("f", modifiers: [.command])

            Button("Delete Selection") {
                NotificationCenter.default.post(name: .prepItInventoryDeleteSelectionCommand, object: nil)
            }
            .keyboardShortcut(.delete, modifiers: [])
        }
    }
}

#endif
