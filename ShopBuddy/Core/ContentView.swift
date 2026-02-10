//
//  ContentView.swift
//  ShopBuddy
//
//  Created by Dan on 1/29/26.
//

import SwiftUI
import SwiftData
import Combine

struct ContentView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.undoManager) private var undoManager
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Employee.name) private var employees: [Employee]

    @State private var selectedTab: TabItem = .inventory
    @State private var hasCreatedManagerAccount = false
    @State private var selectedSidebarTab: TabItem? = .inventory
    @SceneStorage("content.selectedSidebarTabRaw") private var selectedSidebarTabRaw: String = TabItem.inventory.rawValue
    @State private var showingPINEntry = false

    var body: some View {
        Group {
            if employees.isEmpty && !coordinator.isAuthenticated && !hasCreatedManagerAccount {
                OnboardingView { manager in
                    withAnimation {
                        hasCreatedManagerAccount = true
                        coordinator.currentEmployee = manager
                        coordinator.isAuthenticated = true
                        coordinator.currentViewState = .managerView(manager)
                        selectedTab = .inventory
                        #if os(macOS)
                        selectedSidebarTab = .inventory
                        #endif
                    }
                }
            } else {
                mainInterface
            }
        }
        .background(DesignSystem.Colors.background.ignoresSafeArea())
        .onAppear {
            modelContext.undoManager = undoManager
            normalizeTabSelection()
        }
        .onChange(of: visibleTabs.map(\.rawValue)) { _, _ in
            normalizeTabSelection()
        }
        .onChange(of: undoManager) { _, newValue in
            modelContext.undoManager = newValue
        }
        .onChange(of: selectedSidebarTab) { _, newValue in
            #if os(macOS)
            if let newValue {
                selectedSidebarTabRaw = newValue.rawValue
            }
            #endif
        }
    }

    @ViewBuilder
    private var mainInterface: some View {
        #if os(macOS)
        macMainInterface
        #else
        iosMainInterface
        #endif
    }

    private var iosMainInterface: some View {
        TabView(selection: $selectedTab) {
            ForEach(visibleTabs, id: \.self) { tab in
                NavigationStack {
                    tabContent(for: tab)
                        .navigationTitle(tab.rawValue)
                        .toolbar {
#if os(iOS)
                            ToolbarItem(placement: .topBarLeading) {
                                authToolbarContent
                            }
#else
                            ToolbarItem(placement: .automatic) {
                                authToolbarContent
                            }
#endif
                        }
                }
                .tabItem {
                    Label(tab.rawValue, systemImage: tab.icon)
                }
                .tag(tab)
            }
        }
        .sheet(isPresented: $showingPINEntry) {
            PINEntryView()
        }
    }

    #if os(macOS)
    private var macMainInterface: some View {
        NavigationSplitView {
            List(selection: $selectedSidebarTab) {
                Section("Workspace") {
                    ForEach(sidebarPrimaryTabs, id: \.self) { tab in
                        sidebarRow(for: tab)
                    }
                }

                if !sidebarManagementTabs.isEmpty {
                    Section("Management") {
                        ForEach(sidebarManagementTabs, id: \.self) { tab in
                            sidebarRow(for: tab)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(DesignSystem.Colors.background)
            .navigationTitle("ShopBuddy")
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            tabContent(for: currentMacTab)
                .id(currentMacTab)
                .toolbar {
                    ToolbarItem(placement: .automatic) {
                        accountToolbarMenu
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DesignSystem.Colors.background)
        }
        .onChange(of: selectedSidebarTab) { _, newValue in
            if newValue == nil {
                selectedSidebarTab = visibleTabs.first
            }
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $showingPINEntry) {
            PINEntryView()
                .frame(minWidth: 460, minHeight: 620)
        }
    }

    private func sidebarRow(for tab: TabItem) -> some View {
        Label(tab.rawValue, systemImage: tab.icon)
            .font(.system(size: 14, weight: .medium))
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .onTapGesture {
                selectedSidebarTab = tab
            }
            .tag(Optional(tab))
    }
    #endif

    private var userInfoHeader: some View {
        HStack(spacing: 12) {
            Button {
                handleLogout()
            } label: {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.error)
                    .frame(width: 32, height: 32)
                    .background(DesignSystem.Colors.surface)
                    .clipShape(Circle())
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(coordinator.currentUserDisplayName)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.primary)
                Text(coordinator.currentUserRole)
                    .font(.system(size: 10))
                    .foregroundColor(DesignSystem.Colors.secondary)
            }
        }
    }

    private var loginButton: some View {
        Button {
            showingPINEntry = true
        } label: {
            Image(systemName: "lock.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(DesignSystem.Colors.accent)
                .frame(width: 32, height: 32)
                .background(DesignSystem.Colors.surface)
                .clipShape(Circle())
        }
        .help("Sign In")
    }

    @ViewBuilder
    private var authToolbarContent: some View {
        if coordinator.isAuthenticated {
            userInfoHeader
        } else {
            loginButton
        }
    }

    #if os(macOS)
    private var accountToolbarMenu: some View {
        Menu {
            if coordinator.isAuthenticated {
                Label(coordinator.currentUserDisplayName, systemImage: "person.crop.circle.fill")
                if !coordinator.currentUserRole.isEmpty {
                    Text(coordinator.currentUserRole)
                }
                Divider()
                Button("Sign Out", role: .destructive) {
                    handleLogout()
                }
            } else {
                Button("Sign In") {
                    showingPINEntry = true
                }
            }
        } label: {
            Label(
                coordinator.isAuthenticated ? coordinator.currentUserDisplayName : "Sign In",
                systemImage: coordinator.isAuthenticated ? "person.crop.circle" : "lock.fill"
            )
            .labelStyle(.titleAndIcon)
        }
        .help(coordinator.isAuthenticated ? "Account" : "Sign In")
    }
    #endif

    @ViewBuilder
    private func tabContent(for tab: TabItem) -> some View {
        switch tab {
        case .inventory: InventoryView()
        case .checklists: ChecklistsView()
        case .clockInOut: ClockInOutView()
        case .tips: TipsView()
        case .employees: EmployeesView()
        case .reports: ReportsView()
        case .payroll: PayrollView()
        case .settings: SettingsView()
        }
    }

    private var visibleTabs: [TabItem] {
        TabItem.visibleTabs(for: coordinator.currentViewState)
    }

    private var sidebarPrimaryTabs: [TabItem] {
        let preferredOrder: [TabItem] = [.inventory, .checklists, .clockInOut, .tips]
        return preferredOrder.filter(visibleTabs.contains)
    }

    private var sidebarManagementTabs: [TabItem] {
        let preferredOrder: [TabItem] = [.employees, .reports, .payroll, .settings]
        return preferredOrder.filter(visibleTabs.contains)
    }

    private var currentMacTab: TabItem {
        if let selectedSidebarTab, visibleTabs.contains(selectedSidebarTab) {
            return selectedSidebarTab
        }
        return visibleTabs.first ?? .inventory
    }

    private func normalizeTabSelection() {
        #if os(macOS)
        if selectedSidebarTab == nil,
           let restored = TabItem(rawValue: selectedSidebarTabRaw),
           visibleTabs.contains(restored) {
            selectedSidebarTab = restored
        }

        if let selectedSidebarTab, visibleTabs.contains(selectedSidebarTab) {
            selectedSidebarTabRaw = selectedSidebarTab.rawValue
            return
        }

        selectedSidebarTab = visibleTabs.first
        selectedSidebarTabRaw = selectedSidebarTab?.rawValue ?? TabItem.inventory.rawValue
        #else
        if !visibleTabs.contains(selectedTab) {
            selectedTab = visibleTabs.first ?? .inventory
        }
        #endif
    }

    private func handleLogout() {
        withAnimation {
            coordinator.logout()
            selectedTab = .inventory
            selectedSidebarTab = .inventory
        }
    }
}

// MARK: - Onboarding View
struct OnboardingView: View {

    @Environment(\.modelContext) private var modelContext
    @Query private var settings: [AppSettings]

    let onManagerCreated: (Employee) -> Void

    @State private var managerName = ""
    @State private var managerPIN = ""
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.grid_4) {
            Spacer(minLength: 24)

            VStack(spacing: DesignSystem.Spacing.grid_2) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 72))
                    .foregroundColor(DesignSystem.Colors.accent)

                Text("Welcome to ShopBuddy")
                    .font(DesignSystem.Typography.largeTitle)
                    .foregroundColor(DesignSystem.Colors.primary)

                Text("Create your manager account to continue")
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.secondary)
            }

            DesignSystem.GlassCard {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.grid_2) {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.grid_1) {
                        Text("Manager Name")
                            .font(DesignSystem.Typography.headline)
                            .foregroundColor(DesignSystem.Colors.primary)

                        TextField("Enter your name", text: $managerName)
                            .textFieldStyle(CustomTextFieldStyle())
                            .onChange(of: managerName) { _, _ in
                                showError = false
                            }
                    }

                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.grid_1) {
                        Text("4-Digit PIN")
                            .font(DesignSystem.Typography.headline)
                            .foregroundColor(DesignSystem.Colors.primary)

                        SecureField("Enter 4-digit PIN", text: $managerPIN)
                            .textFieldStyle(CustomTextFieldStyle())
                            .onChange(of: managerPIN) { _, newValue in
                                managerPIN = String(newValue.filter(\.isNumber).prefix(4))
                                showError = false
                            }
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                    }

                    Button {
                        createManager()
                    } label: {
                        Text("Create Manager Account")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!canCreateManager)

                    if showError {
                        Text(errorMessage)
                            .font(DesignSystem.Typography.footnote)
                            .foregroundColor(DesignSystem.Colors.error)
                    }
                }
                .padding(DesignSystem.Spacing.grid_3)
            }
            .padding(.horizontal, DesignSystem.Spacing.grid_4)
            .frame(maxWidth: 680)

            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .liquidBackground()
        .alert("Unable to Create Manager", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    private var canCreateManager: Bool {
        let trimmedName = managerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedName.isEmpty && managerPIN.count == 4 && managerPIN.allSatisfy(\.isNumber)
    }

    private func createManager() {
        let trimmedName = managerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPIN = managerPIN.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            errorMessage = "Name cannot be empty"
            showError = true
            DesignSystem.HapticFeedback.trigger(.error)
            return
        }

        guard normalizedPIN.count == 4 && normalizedPIN.allSatisfy({ $0.isNumber }) else {
            errorMessage = "PIN must be exactly 4 digits"
            showError = true
            DesignSystem.HapticFeedback.trigger(.error)
            return
        }

        let manager = Employee(
            name: trimmedName,
            pin: normalizedPIN,
            role: .manager,
            hourlyWage: nil
        )

        modelContext.insert(manager)
        if settings.isEmpty {
            modelContext.insert(AppSettings())
        }

        do {
            try modelContext.save()
            DesignSystem.HapticFeedback.trigger(.success)
            onManagerCreated(manager)
            managerName = ""
            managerPIN = ""
            showError = false
            errorMessage = ""
        } catch {
            errorMessage = "Failed to create account: \(error.localizedDescription)"
            showError = true
            DesignSystem.HapticFeedback.trigger(.error)
        }
    }
}

// MARK: - PIN Entry View
struct PINEntryView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(AppCoordinator.self) private var coordinator

    @Query(sort: \Employee.name) private var employees: [Employee]

    @State private var enteredPIN = ""
    @State private var showError = false
    @FocusState private var isPINFieldFocused: Bool

    private let keypadLayout: [[String]] = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        ["", "0", "⌫"]
    ]

    var body: some View {
        ZStack {
            DesignSystem.LiquidBackdrop()
                .ignoresSafeArea()

            DesignSystem.GlassCard {
                VStack(spacing: DesignSystem.Spacing.grid_3) {
                    HStack {
                        Spacer()
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(DesignSystem.Colors.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    VStack(spacing: DesignSystem.Spacing.grid_2) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 54))
                            .foregroundColor(DesignSystem.Colors.accent)

                        Text("Enter Your PIN")
                            .font(DesignSystem.Typography.title)
                            .foregroundColor(DesignSystem.Colors.primary)

                        Text("Use your 4-digit PIN to sign in")
                            .font(DesignSystem.Typography.body)
                            .foregroundColor(DesignSystem.Colors.secondary)
                    }

                    PINDotIndicator(enteredCount: enteredPIN.count)
                        .padding(.vertical, DesignSystem.Spacing.grid_1)
                        .onTapGesture {
                            #if os(macOS)
                            isPINFieldFocused = true
                            #endif
                        }

                    if showError {
                        Text("Invalid PIN. Please try again.")
                            .font(DesignSystem.Typography.body)
                            .foregroundColor(DesignSystem.Colors.error)
                    }

                    #if os(macOS)
                    TextField("", text: $enteredPIN)
                        .textFieldStyle(.plain)
                        .frame(width: 1, height: 1)
                        .opacity(0.01)
                        .focused($isPINFieldFocused)
                        .onChange(of: enteredPIN) { _, newValue in
                            enteredPIN = sanitizedPIN(from: newValue)
                            if enteredPIN.count == 4 {
                                attemptLogin()
                            }
                        }
                    #endif

                    VStack(spacing: DesignSystem.Spacing.grid_1) {
                        ForEach(keypadLayout, id: \.self) { row in
                            HStack(spacing: DesignSystem.Spacing.grid_1) {
                                ForEach(row, id: \.self) { number in
                                    pinButton(number)
                                }
                            }
                        }
                    }
                }
                .padding(DesignSystem.Spacing.grid_3)
            }
            .frame(maxWidth: 380)
            .padding(DesignSystem.Spacing.grid_3)
        }
        .onAppear {
            #if os(macOS)
            DispatchQueue.main.async {
                isPINFieldFocused = true
            }
            #endif
        }
    }

    private func pinButton(_ number: String) -> some View {
        Button {
            handleNumberPress(number)
        } label: {
            Text(number)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundColor(DesignSystem.Colors.primary)
                .frame(width: 88, height: 60)
                .background(number.isEmpty ? Color.clear : DesignSystem.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
        }
        .buttonStyle(.plain)
        .disabled(number.isEmpty)
        .opacity(number.isEmpty ? 0 : 1)
    }

    private func sanitizedPIN(from rawValue: String) -> String {
        let digitsOnly = rawValue.filter(\.isNumber)
        return String(digitsOnly.prefix(4))
    }

    private func handleNumberPress(_ number: String) {
        guard !number.isEmpty else { return }
        DesignSystem.HapticFeedback.trigger(.light)

        if number == "⌫" {
            if !enteredPIN.isEmpty {
                enteredPIN.removeLast()
            }
            showError = false
            return
        }

        guard enteredPIN.count < 4 else { return }
        enteredPIN = sanitizedPIN(from: enteredPIN + number)

        if enteredPIN.count == 4 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                attemptLogin()
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
            DesignSystem.HapticFeedback.trigger(.error)
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
                    .stroke(DesignSystem.Colors.glassStroke, lineWidth: 1)
            )
    }
}
