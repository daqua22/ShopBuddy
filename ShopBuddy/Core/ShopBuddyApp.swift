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
                    InventoryItem.self,
                    ChecklistTemplate.self,
                    ChecklistTask.self,
                    DailyTips.self,
                    PayrollPeriod.self,
                    AppSettings.self
                ])
                .preferredColorScheme(.dark)
        }
    }
}
