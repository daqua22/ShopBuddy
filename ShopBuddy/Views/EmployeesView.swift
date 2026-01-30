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
    
    var body: some View {
        NavigationStack {
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
            }
            .background(DesignSystem.Colors.background.ignoresSafeArea())
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
                AddEditEmployeeView()
            }
            .sheet(item: $editingEmployee) { employee in
                AddEditEmployeeView(employee: employee)
            }
        }
    }
    
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
    
    let employee: Employee?
    
    @State private var name = ""
    @State private var pin = ""
    @State private var role: EmployeeRole = .employee
    @State private var hourlyWage = ""
    @State private var isActive = true
    
    @State private var showError = false
    @State private var errorMessage = ""
    
    init(employee: Employee? = nil) {
        self.employee = employee
        if let employee = employee {
            _name = State(initialValue: employee.name)
            _pin = State(initialValue: employee.pin)
            _role = State(initialValue: employee.role)
            _hourlyWage = State(initialValue: employee.hourlyWage?.description ?? "")
            _isActive = State(initialValue: employee.isActive)
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Basic Information") {
                    TextField("Name", text: $name)
                    
                    TextField("4-Digit PIN", text: $pin)
                        .keyboardType(.numberPad)
                    
                    Picker("Role", selection: $role) {
                        ForEach(EmployeeRole.allCases, id: \.self) { role in
                            Text(role.rawValue).tag(role)
                        }
                    }
                }
                
                Section("Compensation") {
                    TextField("Hourly Wage (optional)", text: $hourlyWage)
                        .keyboardType(.decimalPad)
                }
                
                if employee != nil {
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
            .scrollContentBackground(.hidden)
            .background(DesignSystem.Colors.background)
            .navigationTitle(employee == nil ? "Add Employee" : "Edit Employee")
            .navigationBarTitleDisplayMode(.inline)
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
    }
    
    private var isValid: Bool {
        !name.isEmpty && !pin.isEmpty
    }
    
    private func saveEmployee() {
        // Validate PIN
        guard pin.isValidPIN else {
            errorMessage = "PIN must be exactly 4 digits"
            showError = true
            DesignSystem.HapticFeedbackDesignSystem.HapticFeedback.trigger(.error)
            return
        }
        
        let wage = hourlyWage.isEmpty ? nil : Double(hourlyWage)
        
        if let employee = employee {
            // Update existing employee
            employee.name = name
            employee.pin = pin
            employee.role = role
            employee.hourlyWage = wage
            employee.isActive = isActive
        } else {
            // Create new employee
            let newEmployee = Employee(
                name: name,
                pin: pin,
                role: role,
                hourlyWage: wage
            )
            modelContext.insert(newEmployee)
        }
        
        do {
            try modelContext.save()
            DesignSystem.HapticFeedbackDesignSystem.HapticFeedback.trigger(.success)
            dismiss()
        } catch {
            errorMessage = "Failed to save employee: \(error.localizedDescription)"
            showError = true
            DesignSystem.HapticFeedbackDesignSystem.HapticFeedback.trigger(.error)
        }
    }
    
    private func deleteEmployee() {
        guard let employee = employee else { return }
        
        modelContext.delete(employee)
        
        do {
            try modelContext.save()
            DesignSystem.HapticFeedbackDesignSystem.HapticFeedback.trigger(.success)
            dismiss()
        } catch {
            errorMessage = "Failed to delete employee: \(error.localizedDescription)"
            showError = true
            DesignSystem.HapticFeedbackDesignSystem.HapticFeedback.trigger(.error)
        }
    }
}
