//
//  ClockInOutView.swift
//  ShopBuddy
//
//  Created by Dan on 1/29/26.
//

import SwiftUI
import SwiftData
import Combine

struct ClockInOutView: View {
    
    @Environment(\.modelContext) private var modelContext
    
    @Query(filter: #Predicate<Employee> { $0.isActive }, sort: \Employee.name)
    private var activeEmployees: [Employee]
    
    @State private var selectedEmployee: Employee?
    @State private var showingPINEntry = false
    @State private var showingConfirmation = false
    
    private var clockedInEmployees: [Employee] {
        activeEmployees.filter { $0.isClockedIn }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: DesignSystem.Spacing.grid_4) {
                // Currently clocked in section
                currentlyClockedInSection
                
                // Clock in/out buttons
                clockActionButtons
                
                // All employees list
                allEmployeesSection
            }
            .padding(DesignSystem.Spacing.grid_2)
        }
        .background(DesignSystem.Colors.background.ignoresSafeArea())
        .navigationTitle("Clock In/Out")
        .fullScreenCover(isPresented: $showingPINEntry) {
            ClockPINEntryView(employee: selectedEmployee)
        }
        .alert("Clock Out Confirmation", isPresented: $showingConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clock Out", role: .destructive) {
                if let employee = selectedEmployee {
                    clockOut(employee: employee)
                }
            }
        } message: {
            if let employee = selectedEmployee {
                Text("Clock out \(employee.name)?")
            }
        }
    }
    
    private var currentlyClockedInSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.grid_2) {
            Text("Currently Clocked In")
                .font(DesignSystem.Typography.title3)
                .foregroundColor(DesignSystem.Colors.primary)
            
            if clockedInEmployees.isEmpty {
                Text("No employees clocked in")
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, DesignSystem.Spacing.grid_4)
                    .glassCard()
            } else {
                VStack(spacing: DesignSystem.Spacing.grid_1) {
                    ForEach(clockedInEmployees) { employee in
                        ClockedInEmployeeRow(employee: employee) {
                            selectedEmployee = employee
                            showingConfirmation = true
                        }
                    }
                }
            }
        }
    }
    
    private var clockActionButtons: some View {
        HStack(spacing: DesignSystem.Spacing.grid_2) {
            Button {
                // Clock in action
                showingPINEntry = true
                selectedEmployee = nil
            } label: {
                VStack(spacing: DesignSystem.Spacing.grid_1) {
                    Image(systemName: "clock.badge.checkmark")
                        .font(.system(size: 40))
                    
                    Text("Clock In")
                        .font(DesignSystem.Typography.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignSystem.Spacing.grid_4)
                .foregroundColor(.white)
                .background(DesignSystem.Colors.success)
                .cornerRadius(DesignSystem.CornerRadius.large)
            }
            
            Button {
                // Clock out - show employee selector if multiple clocked in
                if clockedInEmployees.count == 1 {
                    selectedEmployee = clockedInEmployees.first
                    showingConfirmation = true
                } else {
                    showingPINEntry = true
                    selectedEmployee = nil
                }
            } label: {
                VStack(spacing: DesignSystem.Spacing.grid_1) {
                    Image(systemName: "clock.badge.xmark")
                        .font(.system(size: 40))
                    
                    Text("Clock Out")
                        .font(DesignSystem.Typography.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignSystem.Spacing.grid_4)
                .foregroundColor(.white)
                .background(DesignSystem.Colors.error)
                .cornerRadius(DesignSystem.CornerRadius.large)
            }
            .disabled(clockedInEmployees.isEmpty)
            .opacity(clockedInEmployees.isEmpty ? 0.5 : 1.0)
        }
    }
    
    private var allEmployeesSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.grid_2) {
            Text("All Employees")
                .font(DesignSystem.Typography.title3)
                .foregroundColor(DesignSystem.Colors.primary)
            
            VStack(spacing: DesignSystem.Spacing.grid_1) {
                ForEach(activeEmployees) { employee in
                    EmployeeStatusRow(employee: employee)
                }
            }
        }
    }
    
    private func clockOut(employee: Employee) {
        guard let shift = employee.currentShift else { return }
        
        shift.clockOutTime = Date()
        DesignSystem.HapticFeedback.trigger(.success)
        
        do {
            try modelContext.save()
        } catch {
            print("Failed to clock out: \(error)")
            DesignSystem.HapticFeedback.trigger(.error)
        }
    }
}

// MARK: - Clocked In Employee Row
struct ClockedInEmployeeRow: View {
    
    @Bindable var employee: Employee
    let onClockOut: () -> Void
    
    @State private var currentTime = Date()
    
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.grid_2) {
            VStack(alignment: .leading, spacing: 4) {
                Text(employee.name)
                    .font(DesignSystem.Typography.headline)
                    .foregroundColor(DesignSystem.Colors.primary)
                
                if let shift = employee.currentShift {
                    HStack(spacing: DesignSystem.Spacing.grid_1) {
                        Text("Since \(shift.clockInTime.timeString())")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondary)
                        
                        Text("•")
                            .foregroundColor(DesignSystem.Colors.tertiary)
                        
                        Text(shift.durationString)
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.accent)
                    }
                }
            }
            
            Spacer()
            
            Button {
                onClockOut()
            } label: {
                Text("Clock Out")
                    .font(DesignSystem.Typography.callout)
                    .foregroundColor(.white)
                    .padding(.horizontal, DesignSystem.Spacing.grid_2)
                    .padding(.vertical, DesignSystem.Spacing.grid_1)
                    .background(DesignSystem.Colors.error)
                    .cornerRadius(DesignSystem.CornerRadius.small)
            }
        }
        .padding(DesignSystem.Spacing.grid_2)
        .glassCard()
        .onReceive(timer) { _ in
            currentTime = Date()
        }
    }
}

// MARK: - Employee Status Row
struct EmployeeStatusRow: View {
    
    let employee: Employee
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.grid_2) {
            Circle()
                .fill(employee.isClockedIn ? DesignSystem.Colors.success : DesignSystem.Colors.secondary)
                .frame(width: 12, height: 12)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(employee.name)
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.primary)
                
                Text(employee.role.rawValue)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondary)
            }
            
            Spacer()
            
            Text(employee.isClockedIn ? "Clocked In" : "Clocked Out")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(employee.isClockedIn ? DesignSystem.Colors.success : DesignSystem.Colors.secondary)
        }
        .padding(DesignSystem.Spacing.grid_2)
        .glassCard()
    }
}

// MARK: - Clock PIN Entry View - FULLSCREEN
struct ClockPINEntryView: View {
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @Query(filter: #Predicate<Employee> { $0.isActive }, sort: \Employee.name)
    private var activeEmployees: [Employee]
    
    let employee: Employee?
    
    @State private var enteredPIN = ""
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                DesignSystem.Colors.background.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Cancel button at top
                    HStack {
                        Spacer()
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(DesignSystem.Colors.secondary)
                        }
                        .padding(DesignSystem.Spacing.grid_3)
                    }
                    
                    Spacer()
                    
                    // PIN Entry Content
                    VStack(spacing: DesignSystem.Spacing.grid_3) {
                        VStack(spacing: DesignSystem.Spacing.grid_2) {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 60))
                                .foregroundColor(DesignSystem.Colors.accent)
                            
                            Text("Enter Your PIN")
                                .font(DesignSystem.Typography.title)
                                .foregroundColor(DesignSystem.Colors.primary)
                            
                            Text("Enter your 4-digit PIN to clock in/out")
                                .font(DesignSystem.Typography.body)
                                .foregroundColor(DesignSystem.Colors.secondary)
                                .multilineTextAlignment(.center)
                        }
                        
                        // PIN display
                        HStack(spacing: DesignSystem.Spacing.grid_3) {
                            ForEach(0..<4, id: \.self) { index in
                                Circle()
                                    .fill(index < enteredPIN.count ? DesignSystem.Colors.accent : DesignSystem.Colors.surface)
                                    .frame(width: 20, height: 20)
                                    .overlay(
                                        Circle()
                                            .stroke(DesignSystem.Colors.primary.opacity(0.3), lineWidth: 2)
                                    )
                            }
                        }
                        .padding(.vertical, DesignSystem.Spacing.grid_2)
                        
                        if showError {
                            Text(errorMessage)
                                .font(DesignSystem.Typography.body)
                                .foregroundColor(DesignSystem.Colors.error)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, DesignSystem.Spacing.grid_4)
                        }
                    }
                    
                    Spacer()
                    
                    // Number pad with responsive sizing
                    numberPad(geometry: geometry)
                        .padding(.horizontal, DesignSystem.Spacing.grid_2)
                        .padding(.bottom, DesignSystem.Spacing.grid_2)
                        .safeAreaInset(edge: .bottom) {
                            Color.clear.frame(height: 0)
                        }
                }
            }
        }
    }
    
    private func numberPad(geometry: GeometryProxy) -> some View {
        // Calculate button size based on available width, with min/max constraints
        let availableWidth = geometry.size.width - (DesignSystem.Spacing.grid_2 * 2)
        let spacing = DesignSystem.Spacing.grid_2
        let buttonSize = min(80, max(56, (availableWidth - spacing * 2) / 3))
        let fontSize = max(24, min(32, buttonSize * 0.4))
        
        return VStack(spacing: spacing) {
            ForEach([["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["", "0", "⌫"]], id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(row, id: \.self) { number in
                        Button {
                            handleNumberPress(number)
                        } label: {
                            Text(number)
                                .font(.system(size: fontSize, weight: .medium, design: .rounded))
                                .foregroundColor(DesignSystem.Colors.primary)
                                .frame(width: buttonSize, height: buttonSize)
                                .frame(minWidth: 44, minHeight: 44) // Apple HIG minimum
                                .background(number.isEmpty ? Color.clear : DesignSystem.Colors.surface)
                                .cornerRadius(DesignSystem.CornerRadius.medium)
                                .contentShape(Rectangle())
                        }
                        .disabled(number.isEmpty)
                        .opacity(number.isEmpty ? 0 : 1)
                    }
                }
            }
        }
    }
    
    private func handleNumberPress(_ number: String) {
        DesignSystem.HapticFeedback.trigger(.light)
        
        if number == "⌫" {
            if !enteredPIN.isEmpty {
                enteredPIN.removeLast()
            }
            showError = false
        } else if enteredPIN.count < 4 {
            enteredPIN.append(number)
            
            if enteredPIN.count == 4 {
                // Attempt clock action
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    processClockAction()
                }
            }
        }
    }
    
    private func processClockAction() {
        // Debug logging to diagnose clock-in issues
        print("🔐 Clock Action Debug:")
        print("   Entered PIN: '\(enteredPIN)'")
        print("   Active employees count: \(activeEmployees.count)")
        for emp in activeEmployees {
            print("   - \(emp.name): PIN='\(emp.pin)', isActive=\(emp.isActive)")
        }
        
        guard let employee = activeEmployees.first(where: { $0.pin == enteredPIN }) else {
            print("❌ No employee found with PIN '\(enteredPIN)'")
            errorMessage = "Invalid PIN. Please try again."
            showError = true
            enteredPIN = ""
            DesignSystem.HapticFeedback.trigger(.error)
            return
        }
        
        print("✅ Found employee: \(employee.name)")
        
        if employee.isClockedIn {
            // Clock out
            guard let shift = employee.currentShift else {
                print("❌ Employee is marked as clocked in but has no current shift")
                return
            }
            shift.clockOutTime = Date()
            print("✅ Clocking out \(employee.name)")
            DesignSystem.HapticFeedback.trigger(.success)
        } else {
            // Clock in
            let shift = Shift(employee: employee)
            modelContext.insert(shift)
            print("✅ Clocking in \(employee.name)")
            DesignSystem.HapticFeedback.trigger(.success)
        }
        
        do {
            try modelContext.save()
            print("✅ Context saved successfully")
            dismiss()
        } catch {
            print("❌ Failed to save: \(error)")
            errorMessage = "Failed to process clock action: \(error.localizedDescription)"
            showError = true
            enteredPIN = ""
            DesignSystem.HapticFeedback.trigger(.error)
        }
    }
}
