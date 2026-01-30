//
//  ContentView.swift
//  ShopBuddy
//
//  Created by Dan on 1/29/26.
//

import SwiftUI
import SwiftData
import Combine // Required for Timer and Publisher functionality

struct ContentView: View {
    
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var modelContext
    
    @Query(sort: \Employee.name) private var employees: [Employee]
    @Query private var settings: [AppSettings]
    
    @State private var selectedTab: TabItem = .inventory
    @State private var showingPINEntry = false
    
    var body: some View {
        Group {
            if employees.isEmpty {
                // First launch - create default manager
                OnboardingView()
            } else {
                mainInterface
            }
        }
        .background(DesignSystem.Colors.background.ignoresSafeArea())
    }
    
    private var mainInterface: some View {
        TabView(selection: $selectedTab) {
            ForEach(visibleTabs, id: \.self) { tab in
                tabContent(for: tab)
                    .tabItem {
                        Label(tab.rawValue, systemImage: tab.icon)
                    }
                    .tag(tab)
            }
        }
        .overlay(alignment: .topTrailing) {
            headerButtons
        }
        .sheet(isPresented: $showingPINEntry) {
            PINEntryView()
        }
    }
    
    @ViewBuilder
    private func tabContent(for tab: TabItem) -> some View {
        switch tab {
        case .inventory:
            InventoryView()
        case .checklists:
            ChecklistsView()
        case .clockInOut:
            ClockInOutView()
        case .tips:
            TipsView()
        case .employees:
            EmployeesView()
        case .reports:
            ReportsView()
        case .payroll:
            PayrollView()
        }
    }
    
    private var headerButtons: some View {
        HStack(spacing: DesignSystem.Spacing.grid_2) {
            if coordinator.isAuthenticated {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(coordinator.currentUserDisplayName)
                        .font(DesignSystem.Typography.headline)
                        .foregroundColor(DesignSystem.Colors.primary)
                    
                    Text(coordinator.currentUserRole)
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondary)
                }
                
                Button {
                    withAnimation {
                        coordinator.logout()
                        selectedTab = .inventory
                    }
                } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.title2)
                        .foregroundColor(DesignSystem.Colors.primary)
                }
            } else {
                Button {
                    showingPINEntry = true
                } label: {
                    Label("Login", systemImage: "person.circle")
                        .font(DesignSystem.Typography.headline)
                        .foregroundColor(DesignSystem.Colors.primary)
                }
                .buttonStyle(DesignSystem.SecondaryButtonStyle())
            }
        }
        .padding(DesignSystem.Spacing.grid_2)
    }
    
    private var visibleTabs: [TabItem] {
        TabItem.visibleTabs(for: coordinator.currentViewState)
    }
}

// MARK: - Onboarding View
struct OnboardingView: View {
    
    @Environment(\.modelContext) private var modelContext
    @State private var managerName = ""
    @State private var managerPIN = ""
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.grid_4) {
            Spacer()
            
            VStack(spacing: DesignSystem.Spacing.grid_2) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 80))
                    .foregroundColor(DesignSystem.Colors.accent)
                
                Text("Welcome to ShopBuddy")
                    .font(DesignSystem.Typography.largeTitle)
                    .foregroundColor(DesignSystem.Colors.primary)
                
                Text("Let's create your manager account")
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.secondary)
            }
            
            Spacer()
            
            VStack(spacing: DesignSystem.Spacing.grid_3) {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.grid_1) {
                    Text("Manager Name")
                        .font(DesignSystem.Typography.headline)
                        .foregroundColor(DesignSystem.Colors.primary)
                    
                    TextField("Enter your name", text: $managerName)
                        .textFieldStyle(CustomTextFieldStyle())
                }
                
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.grid_1) {
                    Text("4-Digit PIN")
                        .font(DesignSystem.Typography.headline)
                        .foregroundColor(DesignSystem.Colors.primary)
                    
                    SecureField("Enter 4-digit PIN", text: $managerPIN)
                        .textFieldStyle(CustomTextFieldStyle())
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                }
                
                if showError {
                    Text(errorMessage)
                        .font(DesignSystem.Typography.footnote)
                        .foregroundColor(DesignSystem.Colors.error)
                }
                
                Button {
                    createManager()
                } label: {
                    Text("Create Manager Account")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(managerName.isEmpty || managerPIN.isEmpty)
            }
            .padding(DesignSystem.Spacing.grid_3)
            .glassCard()
            .padding(DesignSystem.Spacing.grid_4)
            
            Spacer()
        }
        .background(DesignSystem.Colors.background.ignoresSafeArea())
    }
    
    private func createManager() {
        guard managerPIN.count == 4 && managerPIN.allSatisfy({ $0.isNumber }) else {
            errorMessage = "PIN must be exactly 4 digits"
            showError = true
            DesignSystem.HapticFeedbackDesignSystem.HapticFeedback.trigger(.error)
            return
        }
        
        let manager = Employee(
            name: managerName,
            pin: managerPIN,
            role: .manager,
            hourlyWage: nil
        )
        
        modelContext.insert(manager)
        let settings = AppSettings()
        modelContext.insert(settings)
        
        do {
            try modelContext.save()
            DesignSystem.HapticFeedbackDesignSystem.HapticFeedback.trigger(.success)
        } catch {
            errorMessage = "Failed to create account: \(error.localizedDescription)"
            showError = true
            DesignSystem.HapticFeedbackDesignSystem.HapticFeedback.trigger(.error)
        }
    }
}

// MARK: - PIN Entry View
struct PINEntryView: View {
    
    @Environment(\.dismiss) private var dismiss
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var modelContext
    
    @Query(sort: \Employee.name) private var employees: [Employee]
    
    @State private var enteredPIN = ""
    @State private var showError = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: DesignSystem.Spacing.grid_4) {
                Spacer()
                
                VStack(spacing: DesignSystem.Spacing.grid_2) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 60))
                        .foregroundColor(DesignSystem.Colors.accent)
                    
                    Text("Enter Your PIN")
                        .font(DesignSystem.Typography.title)
                        .foregroundColor(DesignSystem.Colors.primary)
                    
                    Text("Enter your 4-digit PIN to continue")
                        .font(DesignSystem.Typography.body)
                        .foregroundColor(DesignSystem.Colors.secondary)
                }
                
                HStack(spacing: DesignSystem.Spacing.grid_2) {
                    ForEach(0..<4, id: \.self) { index in
                        Circle()
                            .fill(index < enteredPIN.count ? DesignSystem.Colors.accent : DesignSystem.Colors.surface)
                            .frame(width: 20, height: 20)
                            .overlay(
                                Circle()
                                    .stroke(DesignSystem.Colors.primary.opacity(0.3), lineWidth: 1)
                            )
                    }
                }
                .padding(.vertical, DesignSystem.Spacing.grid_3)
                
                if showError {
                    Text("Invalid PIN. Please try again.")
                        .font(DesignSystem.Typography.body)
                        .foregroundColor(DesignSystem.Colors.error)
                }
                
                numberPad
                
                Spacer()
            }
            .padding(DesignSystem.Spacing.grid_4)
            .background(DesignSystem.Colors.background.ignoresSafeArea())
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var numberPad: some View {
        VStack(spacing: DesignSystem.Spacing.grid_2) {
            ForEach([["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["", "0", "⌫"]], id: \.self) { row in
                HStack(spacing: DesignSystem.Spacing.grid_2) {
                    ForEach(row, id: \.self) { number in
                        Button {
                            handleNumberPress(number)
                        } label: {
                            Text(number)
                                .font(DesignSystem.Typography.largeTitle)
                                .foregroundColor(DesignSystem.Colors.primary)
                                .frame(width: 80, height: 80)
                                .background(number.isEmpty ? Color.clear : DesignSystem.Colors.surface)
                                .cornerRadius(DesignSystem.CornerRadius.large)
                        }
                        .disabled(number.isEmpty)
                    }
                }
            }
        }
    }
    
    private func handleNumberPress(_ number: String) {
        DesignSystem.HapticFeedbackDesignSystem.HapticFeedback.trigger(.light)
        
        if number == "⌫" {
            if !enteredPIN.isEmpty {
                enteredPIN.removeLast()
            }
            showError = false
        } else if enteredPIN.count < 4 {
            enteredPIN.append(number)
            
            if enteredPIN.count == 4 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    attemptLogin()
                }
            }
        }
    }
    
    private func attemptLogin() {
        let success = coordinator.login(with: enteredPIN, employees: employees)
        
        if success {
            dismiss()
        } else {
            showError = true
            enteredPIN = ""
            DesignSystem.HapticFeedbackDesignSystem.HapticFeedback.trigger(.error)
        }
    }
}

// MARK: - Custom Text Field Style
struct CustomTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(DesignSystem.Typography.body)
            .foregroundColor(DesignSystem.Colors.primary)
            .padding(DesignSystem.Spacing.grid_2)
            .background(DesignSystem.Colors.surface)
            .cornerRadius(DesignSystem.CornerRadius.medium)
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
    }
}
