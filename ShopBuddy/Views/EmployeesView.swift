//
//  EmployeesView.swift
//  ShopBuddy
//
//  Created by Dan on 1/29/26.
//

import SwiftUI
import SwiftData

struct EmployeesView: View {
    
    @Environment(\.modelContext) private var modelContext
    
    @Query(sort: \Employee.name) private var allEmployees: [Employee]
    
    @State private var showingAddEmployee = false
    @State private var editingEmployee: Employee?
    @State private var searchText = ""
    @State private var employeePendingDeletion: Employee?
    @State private var showingDeleteConfirmation = false
    @SceneStorage("employees.selectedEmployeeID") private var selectedEmployeeID: String?
    @FocusState private var isSearchFieldFocused: Bool
    
    private var filteredEmployees: [Employee] {
        if searchText.isEmpty {
            return allEmployees
        } else {
            return allEmployees.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.role.rawValue.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    private var selectedEmployee: Employee? {
        guard let selectedEmployeeID else { return nil }
        return allEmployees.first { $0.id.uuidString == selectedEmployeeID }
    }

    private var activeEmployeeCount: Int {
        allEmployees.filter(\.isActive).count
    }

    private var clockedInEmployeeCount: Int {
        allEmployees.filter(\.isClockedIn).count
    }
    
    @ViewBuilder
    var body: some View {
        #if os(macOS)
        macBody
        #else
        iosBody
        #endif
    }

    private var iosBody: some View {
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.grid_3) {
                    // Search bar
                    searchBar
                    
                    // Employees list
                    if filteredEmployees.isEmpty {
                        EmptyStateView(
                            icon: "person.3",
                            title: "No Employees",
                            message: searchText.isEmpty ? "Add your first employee to get started" : "No employees match your search",
                            actionTitle: searchText.isEmpty ? "Add Employee" : nil,
                            action: searchText.isEmpty ? { showingAddEmployee = true } : nil
                        )
                    } else {
                        employeesList
                    }
            }
            .padding(DesignSystem.Spacing.grid_2)
            .readableContent()
        }
            .liquidBackground()
            .navigationTitle("Employees")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddEmployee = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddEmployee) {
                NavigationStack {
                    AddEditEmployeeView()
                }
            }
            .sheet(item: $editingEmployee) { employee in
                NavigationStack {
                    AddEditEmployeeView(employee: employee)
                }
            }
    }

    #if os(macOS)
    private var macBody: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(searchText.isEmpty ? "Team Members" : "Search Results")
                    .font(DesignSystem.Typography.headline)
                    .foregroundColor(DesignSystem.Colors.primary)
                Spacer()
                employeeStatPill(title: "Shown", value: filteredEmployees.count, color: DesignSystem.Colors.primary)
                employeeStatPill(title: "Active", value: activeEmployeeCount, color: DesignSystem.Colors.success)
                employeeStatPill(title: "Clocked In", value: clockedInEmployeeCount, color: DesignSystem.Colors.accent)
            }
            .padding(.horizontal, DesignSystem.Spacing.grid_2)
            .padding(.vertical, DesignSystem.Spacing.grid_2)

            Divider()
                .overlay(DesignSystem.Colors.glassStroke.opacity(0.45))

            Group {
                if filteredEmployees.isEmpty {
                    ContentUnavailableView {
                        Label(
                            searchText.isEmpty ? "No Employees" : "No Search Results",
                            systemImage: searchText.isEmpty ? "person.3" : "magnifyingglass"
                        )
                    } description: {
                        Text(searchText.isEmpty ? "Add your first employee to get started." : "No employees match that query.")
                    } actions: {
                        if searchText.isEmpty {
                            Button("Add Employee") {
                                showingAddEmployee = true
                            }
                        } else {
                            Button("Clear Search") {
                                searchText = ""
                            }
                        }
                    }
                } else {
                    List(selection: $selectedEmployeeID) {
                        ForEach(filteredEmployees) { employee in
                            macEmployeeRow(employee)
                                .tag(employee.id.uuidString)
                                .contentShape(Rectangle())
                                .contextMenu {
                                    Button("Edit", systemImage: "pencil") {
                                        editingEmployee = employee
                                    }
                                    Button(employee.isActive ? "Mark Inactive" : "Mark Active", systemImage: employee.isActive ? "person.crop.circle.badge.xmark" : "person.crop.circle.badge.checkmark") {
                                        toggleStatus(for: employee)
                                    }
                                    Divider()
                                    Button("Delete Employee", systemImage: "trash", role: .destructive) {
                                        requestDelete(employee)
                                    }
                                }
                                .onTapGesture(count: 2) {
                                    editingEmployee = employee
                                }
                        }
                    }
                    .listStyle(.inset)
                    .liquidListChrome()
                    .listRowBackground(DesignSystem.Colors.surfaceElevated.opacity(0.38))
                }
            }
        }
        .macPagePadding(horizontal: DesignSystem.Spacing.grid_1, vertical: DesignSystem.Spacing.grid_1)
        .liquidBackground()
        .navigationTitle("Employees")
        .searchable(text: $searchText, prompt: "Search employees")
        .searchFocused($isSearchFieldFocused)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showingAddEmployee = true
                } label: {
                    Image(systemName: "plus")
                }
                .keyboardShortcut("n", modifiers: [.command])
                .help("Add Employee (\u{2318}N)")

                Button {
                    if let selectedEmployee {
                        editingEmployee = selectedEmployee
                    }
                } label: {
                    Image(systemName: "pencil")
                }
                .disabled(selectedEmployee == nil)
                .help("Edit Selected Employee")

                Button {
                    isSearchFieldFocused = true
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .keyboardShortcut("f", modifiers: [.command])
                .help("Focus Search (\u{2318}F)")
            }
        }
        .onDeleteCommand {
            guard let selectedEmployee else { return }
            requestDelete(selectedEmployee)
        }
        .onAppear {
            normalizeSelection()
        }
        .onChange(of: allEmployees.count) { _, _ in
            normalizeSelection()
        }
        .alert("Delete Employee", isPresented: $showingDeleteConfirmation, presenting: employeePendingDeletion) { employee in
            Button("Cancel", role: .cancel) {
                employeePendingDeletion = nil
            }
            Button("Delete", role: .destructive) {
                delete(employee)
            }
        } message: { employee in
            Text("Are you sure you want to delete \(employee.name)? This action cannot be undone.")
        }
        .sheet(isPresented: $showingAddEmployee) {
            NavigationStack {
                AddEditEmployeeView()
            }
            .frame(minWidth: 520, minHeight: 520)
        }
        .sheet(item: $editingEmployee) { employee in
            NavigationStack {
                AddEditEmployeeView(employee: employee)
            }
            .frame(minWidth: 520, minHeight: 600)
        }
    }

    private func employeeStatPill(title: String, value: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondary)
            Text("\(value)")
                .font(DesignSystem.Typography.headline)
                .foregroundColor(color)
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(DesignSystem.Colors.surface.opacity(0.8))
        )
    }

    private func macEmployeeRow(_ employee: Employee) -> some View {
        HStack(spacing: DesignSystem.Spacing.grid_2) {
            Circle()
                .fill(employee.isClockedIn ? DesignSystem.Colors.success : DesignSystem.Colors.tertiary.opacity(0.6))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 3) {
                Text(employee.name)
                    .font(DesignSystem.Typography.headline)
                    .foregroundColor(DesignSystem.Colors.primary)

                Text(employee.role.rawValue)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondary)
            }

            Spacer()

            if let wage = employee.hourlyWage {
                Divider()
                    .frame(height: 20)
                Text(wage.currencyString() + "/hr")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondary)
            }

            if !employee.isActive {
                Text("Inactive")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.error)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(DesignSystem.Colors.error.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private func normalizeSelection() {
        guard let selectedEmployeeID else { return }
        let stillExists = allEmployees.contains { $0.id.uuidString == selectedEmployeeID }
        if !stillExists {
            self.selectedEmployeeID = nil
        }
    }

    private func requestDelete(_ employee: Employee) {
        employeePendingDeletion = employee
        showingDeleteConfirmation = true
    }

    private func delete(_ employee: Employee) {
        modelContext.delete(employee)

        if selectedEmployeeID == employee.id.uuidString {
            selectedEmployeeID = nil
        }

        do {
            try modelContext.save()
            DesignSystem.HapticFeedback.trigger(.success)
            employeePendingDeletion = nil
        } catch {
            DesignSystem.HapticFeedback.trigger(.error)
        }
    }

    private func toggleStatus(for employee: Employee) {
        if employee.isActive {
            let now = Date()
            for shift in employee.shifts where shift.clockOutTime == nil {
                shift.clockOutTime = now
            }
        }
        employee.isActive.toggle()

        do {
            try modelContext.save()
            DesignSystem.HapticFeedback.trigger(.selection)
        } catch {
            DesignSystem.HapticFeedback.trigger(.error)
        }
    }
    #endif
    
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(DesignSystem.Colors.secondary)
            
            TextField("Search employees...", text: $searchText)
                .foregroundColor(DesignSystem.Colors.primary)
            
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(DesignSystem.Colors.secondary)
                }
            }
        }
        .padding(DesignSystem.Spacing.grid_2)
        .glassCard()
    }
    
    private var employeesList: some View {
        VStack(spacing: DesignSystem.Spacing.grid_1) {
            ForEach(filteredEmployees) { employee in
                EmployeeRow(employee: employee) {
                    editingEmployee = employee
                }
            }
        }
    }
}

// MARK: - Employee Row
struct EmployeeRow: View {
    
    let employee: Employee
    let onTap: () -> Void
    
    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(spacing: DesignSystem.Spacing.grid_2) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(employee.name)
                        .font(DesignSystem.Typography.headline)
                        .foregroundColor(DesignSystem.Colors.primary)
                    
                    HStack(spacing: DesignSystem.Spacing.grid_1) {
                        Text(employee.role.rawValue)
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondary)
                        
                        if let wage = employee.hourlyWage {
                            Text("•")
                                .foregroundColor(DesignSystem.Colors.tertiary)
                            Text(wage.currencyString() + "/hr")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.secondary)
                        }
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    if employee.isClockedIn {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(DesignSystem.Colors.success)
                                .frame(width: 8, height: 8)
                            Text("Clocked In")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.success)
                        }
                    }
                    
                    if !employee.isActive {
                        Text("Inactive")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.error)
                    }
                }
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(DesignSystem.Colors.tertiary)
            }
            .padding(DesignSystem.Spacing.grid_2)
        }
        .glassCard()
    }
}

// MARK: - Add/Edit Employee View
struct AddEditEmployeeView: View {
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Employee.name) private var allEmployees: [Employee]
    @AppStorage("passIssuerBaseURL") private var passIssuerBaseURL = ""
    @AppStorage("enableGoogleWalletPasses") private var enableGoogleWalletPasses = true
    
    let employee: Employee?
    
    @State private var name = ""
    @State private var pin = ""
    @State private var role: EmployeeRole = .employee
    @State private var hourlyWage = ""
    @State private var isActive = true
    @State private var birthday: Date? = nil
    @State private var hasBirthday = false
    
    @State private var showError = false
    @State private var errorMessage = ""
    
    init(employee: Employee? = nil) {
        self.employee = employee
        if let employee = employee {
            _name = State(initialValue: employee.name)
            _pin = State(initialValue: "")
            _role = State(initialValue: employee.role)
            _hourlyWage = State(initialValue: employee.hourlyWage?.description ?? "")
            _isActive = State(initialValue: employee.isActive)
            _birthday = State(initialValue: employee.birthday)
            _hasBirthday = State(initialValue: employee.birthday != nil)
        }
    }
    
    var body: some View {
            Form {
                Section("Basic Information") {
                    TextField("Name", text: $name)
                    
                    #if os(iOS)
                    TextField(employee == nil ? "4-Digit PIN" : "New PIN (optional)", text: $pin)
                        .keyboardType(.numberPad)
                    #else
                    TextField(employee == nil ? "4-Digit PIN" : "New PIN (optional)", text: $pin)
                    #endif
                    
                    Picker("Role", selection: $role) {
                        ForEach(EmployeeRole.allCases, id: \.self) { role in
                            Text(role.rawValue).tag(role)
                        }
                    }
                }
                
                Section("Compensation") {
                    #if os(iOS)
                    TextField("Hourly Wage (optional)", text: $hourlyWage)
                        .keyboardType(.decimalPad)
                    #else
                    TextField("Hourly Wage (optional)", text: $hourlyWage)
                    #endif
                }

                Section("Personal") {
                    Toggle("Birthday", isOn: $hasBirthday)
                        .onChange(of: hasBirthday) { _, newValue in
                            if newValue && birthday == nil {
                                birthday = Date()
                            }
                        }
                    if hasBirthday {
                        DatePicker(
                            "Date",
                            selection: Binding(
                                get: { birthday ?? Date() },
                                set: { birthday = $0 }
                            ),
                            displayedComponents: .date
                        )
                    }
                }
                
                if let employee {
                    Section("Digital Passes") {
                        if let passIssuerURL {
                            NavigationLink {
                                EmployeePassManagementView(
                                    employee: employee,
                                    issuerBaseURL: passIssuerURL,
                                    enableGoogleWalletPasses: enableGoogleWalletPasses
                                )
                            } label: {
                                Label("Manage Wallet Passes", systemImage: "wallet.pass")
                            }

                            Text(passIssuerURL.absoluteString)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                        } else {
                            Text("Set Pass Issuer API Base URL in Settings to issue Apple and Google wallet passes.")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }

                    Section("Status") {
                        Toggle("Active Employee", isOn: $isActive)
                    }
                    
                    Section {
                        Button(role: .destructive) {
                            deleteEmployee()
                        } label: {
                            Label("Delete Employee", systemImage: "trash")
                        }
                    }
                }
                
                if showError {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(DesignSystem.Colors.error)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(employee == nil ? "Add Employee" : "Edit Employee")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveEmployee()
                    }
                    .disabled(!isValid)
                }
            }
    }
    
    private var isValid: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if employee == nil {
            return !trimmedName.isEmpty && !pin.isEmpty
        }
        return !trimmedName.isEmpty
    }

    private var passIssuerURL: URL? {
        let normalized = passIssuerBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, let url = URL(string: normalized), let scheme = url.scheme else {
            return nil
        }
        let normalizedScheme = scheme.lowercased()
        if normalizedScheme == "https" {
            return url
        }
#if DEBUG
        if normalizedScheme == "http", let host = url.host?.lowercased(), host == "localhost" || host == "127.0.0.1" {
            return url
        }
#endif
        return nil
    }
    
    private func saveEmployee() {
        let normalizedPIN = pin.trimmingCharacters(in: .whitespacesAndNewlines)
        if employee == nil || !normalizedPIN.isEmpty {
            guard normalizedPIN.isValidPIN else {
                errorMessage = "PIN must be exactly 4 digits"
                showError = true
                DesignSystem.HapticFeedback.trigger(.error)
                return
            }
        }
        
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Name cannot be empty"
            showError = true
            DesignSystem.HapticFeedback.trigger(.error)
            return
        }

        if !normalizedPIN.isEmpty {
            let duplicatePINExists = allEmployees.contains(where: { (existing: Employee) in
                let isSameEmployee = employee.map { existing.id == $0.id } ?? false
                return !isSameEmployee && existing.matchesPIN(normalizedPIN)
            })
            guard !duplicatePINExists else {
                errorMessage = "PIN is already assigned to another employee"
                showError = true
                DesignSystem.HapticFeedback.trigger(.error)
                return
            }
        }

        let trimmedWage = hourlyWage.trimmingCharacters(in: .whitespacesAndNewlines)
        let wage: Double?
        if trimmedWage.isEmpty {
            wage = nil
        } else if let parsedWage = Double(trimmedWage), parsedWage >= 0 {
            wage = parsedWage
        } else {
            errorMessage = "Hourly wage must be a valid non-negative number"
            showError = true
            DesignSystem.HapticFeedback.trigger(.error)
            return
        }
        
        if let employee = employee {
            // Update existing employee
            if employee.isActive && !isActive {
                let now = Date()
                for shift in employee.shifts where shift.clockOutTime == nil {
                    shift.clockOutTime = now
                }
            }

            employee.name = trimmedName
            if !normalizedPIN.isEmpty {
                employee.setPIN(normalizedPIN)
            }
            employee.role = role
            employee.hourlyWage = wage
            employee.birthday = hasBirthday ? birthday : nil
            employee.isActive = isActive
        } else {
            // Create new employee
            let newEmployee = Employee(
                name: trimmedName,
                pin: normalizedPIN,
                role: role,
                hourlyWage: wage,
                birthday: hasBirthday ? birthday : nil
            )
            modelContext.insert(newEmployee)
        }
        
        do {
            try modelContext.save()
            DesignSystem.HapticFeedback.trigger(.success)
            dismiss()
        } catch {
            errorMessage = "Failed to save employee: \(error.localizedDescription)"
            showError = true
            DesignSystem.HapticFeedback.trigger(.error)
        }
    }
    
    private func deleteEmployee() {
        guard let employee = employee else { return }
        
        modelContext.delete(employee)
        
        do {
            try modelContext.save()
            DesignSystem.HapticFeedback.trigger(.success)
            dismiss()
        } catch {
            errorMessage = "Failed to delete employee: \(error.localizedDescription)"
            showError = true
            DesignSystem.HapticFeedback.trigger(.error)
        }
    }
}

// MARK: - Employee Pass Management
struct EmployeePassManagementView: View {
    let employee: Employee
    let issuerBaseURL: URL
    let enableGoogleWalletPasses: Bool

    @Environment(\.openURL) private var openURL

    @State private var isLoading = false
    @State private var passBundle: EmployeePassBundle?
    @State private var fallbackPayload: String?
    @State private var qrImage: Image?
    @State private var errorMessage: String?

    private var qrPayload: String? {
        passBundle?.qrPayload ?? fallbackPayload
    }

    var body: some View {
        ScrollView {
            VStack(spacing: DesignSystem.Spacing.grid_3) {
                headerCard
                linksCard
                qrCard
            }
            .padding(DesignSystem.Spacing.grid_2)
            .readableContent(maxWidth: 680)
        }
        .background(DesignSystem.Colors.background.ignoresSafeArea())
        .navigationTitle("\(employee.name) Pass")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        await loadPassBundle()
                    }
                } label: {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(isLoading)
            }
        }
        .task {
            if passBundle == nil {
                await loadPassBundle()
            }
        }
        .onChange(of: qrPayload) { _, _ in
            updateQRCodeImage()
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.grid_1) {
            Text("Digital Pass Distribution")
                .font(DesignSystem.Typography.title3)
                .foregroundColor(DesignSystem.Colors.primary)

            Text("Issue Apple Wallet and Google Wallet links from your pass service. QR fallback works for any phone.")
                .font(DesignSystem.Typography.body)
                .foregroundColor(DesignSystem.Colors.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignSystem.Spacing.grid_2)
        .glassCard()
    }

    private var linksCard: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.grid_2) {
            Text("Distribution Links")
                .font(DesignSystem.Typography.headline)
                .foregroundColor(DesignSystem.Colors.primary)

            if let appleWalletURL = passBundle?.appleWalletURL {
                Button {
                    openURL(appleWalletURL)
                } label: {
                    Label("Open Apple Wallet Link", systemImage: "wallet.pass")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(SecondaryButtonStyle())
            }

            if enableGoogleWalletPasses, let googleWalletURL = passBundle?.googleWalletURL {
                Button {
                    openURL(googleWalletURL)
                } label: {
                    Label("Open Google Wallet Link", systemImage: "link")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(SecondaryButtonStyle())
            }

            if let expiresAt = passBundle?.expiresAt {
                Text("Link expires \(expiresAt.dateTimeString())")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondary)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.warning)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignSystem.Spacing.grid_2)
        .glassCard()
    }

    private var qrCard: some View {
        VStack(spacing: DesignSystem.Spacing.grid_2) {
            HStack {
                Text("Universal QR")
                    .font(DesignSystem.Typography.headline)
                    .foregroundColor(DesignSystem.Colors.primary)
                Spacer()
            }

            if let qrImage {
                qrImage
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(maxWidth: 240, maxHeight: 240)
                    .padding(DesignSystem.Spacing.grid_1)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))

                Text("Employees can use this QR from Apple Wallet, Google Wallet, or an app fallback.")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondary)
                    .multilineTextAlignment(.center)
            } else if isLoading {
                ProgressView("Loading pass data...")
            } else {
                Text("No QR payload is available yet.")
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(DesignSystem.Spacing.grid_2)
        .glassCard()
    }

    private func loadPassBundle() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let bundle = try await EmployeePassService().fetchPassBundle(
                for: employee.id,
                issuerBaseURL: issuerBaseURL,
                includeGoogleWallet: enableGoogleWalletPasses
            )
            passBundle = bundle
            fallbackPayload = nil
            errorMessage = nil
            updateQRCodeImage()
        } catch {
            passBundle = nil
            fallbackPayload = EmployeePassService().localFallbackPayload(for: employee.id)
            errorMessage = error.localizedDescription + " Showing fallback QR payload for development."
            updateQRCodeImage()
        }
    }

    private func updateQRCodeImage() {
        guard let qrPayload else {
            qrImage = nil
            return
        }
        qrImage = QRCodeRenderer.shared.makeImage(from: qrPayload)
    }
}

private struct EmployeePassBundle: Decodable {
    let appleWalletURL: URL
    let googleWalletURL: URL?
    let qrPayload: String
    let expiresAt: Date
}

private struct EmployeePassService {
    func fetchPassBundle(
        for employeeID: UUID,
        issuerBaseURL: URL,
        includeGoogleWallet: Bool
    ) async throws -> EmployeePassBundle {
        var components = URLComponents(
            url: issuerBaseURL.appending(path: "v1/passes/employees/\(employeeID.uuidString)"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "include_google_wallet", value: includeGoogleWallet ? "true" : "false")
        ]

        guard let url = components?.url else {
            throw EmployeePassServiceError.invalidIssuerURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw EmployeePassServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw EmployeePassServiceError.httpStatus(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601

        do {
            return try decoder.decode(EmployeePassBundle.self, from: data)
        } catch {
            throw EmployeePassServiceError.decodingFailed
        }
    }

    // Fallback payload used only for development if the pass service is unavailable.
    func localFallbackPayload(for employeeID: UUID) -> String {
        let timestamp = Int(Date().timeIntervalSince1970)
        return "shopbuddy://clock?employee_id=\(employeeID.uuidString)&issued_at=\(timestamp)"
    }
}

private enum EmployeePassServiceError: LocalizedError {
    case invalidIssuerURL
    case invalidResponse
    case httpStatus(Int)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidIssuerURL:
            return "Pass issuer URL is invalid."
        case .invalidResponse:
            return "Pass issuer returned an invalid response."
        case .httpStatus(let statusCode):
            return "Pass issuer request failed with status \(statusCode)."
        case .decodingFailed:
            return "Pass issuer response format is invalid."
        }
    }
}
