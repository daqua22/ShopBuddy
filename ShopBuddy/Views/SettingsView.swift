//
//  SettingsView.swift
//  ShopBuddy
//
//  Created by Dan on 1/30/26.
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settings: [AppSettings]
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Inventory Permissions") {
                    if let setting = settings.first {
                        Toggle("Employees can change stock levels", isOn: Bindable(setting).allowEmployeeInventoryEdit)
                    }
                }
                
                Section("Account") {
                    Text("Role: Manager")
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                if settings.isEmpty {
                    modelContext.insert(AppSettings())
                }
            }
        }
    }
}
