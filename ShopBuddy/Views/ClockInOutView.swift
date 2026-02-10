//
//  ClockInOutView.swift
//  ShopBuddy
//
//  Created by Dan on 1/29/26.
//

import SwiftUI
import SwiftData
import Combine

enum ClockPINEntryIntent {
    case clockIn
    case clockOut
}

struct ClockInOutView: View {
    
    @Environment(\.modelContext) private var modelContext
    
    @Query(filter: #Predicate<Employee> { $0.isActive }, sort: \Employee.name)
    private var activeEmployees: [Employee]
    
    @State private var selectedEmployee: Employee?
    @State private var showingPINEntry = false
    @State private var showingConfirmation = false
    @State private var pinEntryIntent: ClockPINEntryIntent = .clockIn
    
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
#if os(iOS)
        .fullScreenCover(isPresented: $showingPINEntry) {
            ClockPINEntryView(employee: selectedEmployee, intent: pinEntryIntent)
        }
#else
        .sheet(isPresented: $showingPINEntry) {
            ClockPINEntryView(employee: selectedEmployee, intent: pinEntryIntent)
                .frame(minWidth: 340, minHeight: 520)
        }
#endif
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
                pinEntryIntent = .clockIn
                showingPINEntry = true
                selectedEmployee = nil
            } label: {
                Label("Clock In", systemImage: "clock.badge.checkmark")
            }
            .buttonStyle(.bordered)
            .tint(DesignSystem.Colors.success)
            .controlSize(.large)
            
            Button {
                // Clock out - show employee selector if multiple clocked in
                if clockedInEmployees.count == 1 {
                    selectedEmployee = clockedInEmployees.first
                    showingConfirmation = true
                } else {
                    pinEntryIntent = .clockOut
                    showingPINEntry = true
                    selectedEmployee = nil
                }
            } label: {
                Label("Clock Out", systemImage: "clock.badge.xmark")
            }
            .buttonStyle(.bordered)
            .tint(DesignSystem.Colors.error)
            .controlSize(.large)
            .disabled(clockedInEmployees.isEmpty)
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
            .buttonStyle(.plain)
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
    let intent: ClockPINEntryIntent
    
    @State private var enteredPIN = ""
    @State private var showError = false
    @State private var errorMessage = ""
    #if os(macOS)
    @State private var keyMonitor: Any?
    #endif
    
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.grid_2) {
            // Header
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(DesignSystem.Colors.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, DesignSystem.Spacing.grid_2)
            .padding(.top, DesignSystem.Spacing.grid_1)
            
            Spacer(minLength: 4)
            
            // PIN Entry Content
            VStack(spacing: DesignSystem.Spacing.grid_2) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 36))
                    .foregroundColor(DesignSystem.Colors.accent)
                
                Text("Enter Your PIN")
                    .font(DesignSystem.Typography.title3)
                    .foregroundColor(DesignSystem.Colors.primary)
                
                Text("Enter your 4-digit PIN to \(intent == .clockIn ? "clock in" : "clock out")")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondary)
                    .multilineTextAlignment(.center)
                
                // PIN display
                HStack(spacing: DesignSystem.Spacing.grid_2) {
                    ForEach(0..<4, id: \.self) { index in
                        Circle()
                            .fill(index < enteredPIN.count ? DesignSystem.Colors.accent : DesignSystem.Colors.surface)
                            .frame(width: 16, height: 16)
                            .overlay(
                                Circle()
                                    .stroke(DesignSystem.Colors.primary.opacity(0.3), lineWidth: 1.5)
                            )
                    }
                }
                .padding(.vertical, DesignSystem.Spacing.grid_1)
                
                if showError {
                    Text(errorMessage)
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.error)
                        .multilineTextAlignment(.center)
                }
            }
            
            Spacer(minLength: 4)
            
            // Number pad — compact
            compactNumberPad
                .padding(.horizontal, DesignSystem.Spacing.grid_3)
                .padding(.bottom, DesignSystem.Spacing.grid_2)
        }
        .frame(minWidth: 300, minHeight: 440)
        .background(DesignSystem.Colors.background)
        #if os(macOS)
        .focusable()
        .onAppear {
            // Install a local key monitor for digit and delete keys
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                let chars = event.charactersIgnoringModifiers ?? ""
                if let digit = chars.first, digit.isNumber {
                    handleNumberPress(String(digit))
                    return nil  // consume the event
                }
                if event.keyCode == 51 { // backspace
                    handleNumberPress("⌫")
                    return nil
                }
                if event.keyCode == 53 { // escape
                    dismiss()
                    return nil
                }
                return event
            }
        }
        .onDisappear {
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
                keyMonitor = nil
            }
        }
        #endif
    }

    private var compactNumberPad: some View {
        let buttonSize: CGFloat = 48
        let spacing: CGFloat = 10
        let fontSize: CGFloat = 20

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
                                .background(number.isEmpty ? Color.clear : DesignSystem.Colors.surface)
                                .cornerRadius(DesignSystem.CornerRadius.medium)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
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
        guard let employee = employee ?? activeEmployees.first(where: { $0.pin == enteredPIN }) else {
            errorMessage = "Invalid PIN. Please try again."
            showError = true
            enteredPIN = ""
            DesignSystem.HapticFeedback.trigger(.error)
            return
        }

        switch intent {
        case .clockIn:
            guard !employee.isClockedIn else {
                errorMessage = "\(employee.name) is already clocked in."
                showError = true
                enteredPIN = ""
                DesignSystem.HapticFeedback.trigger(.error)
                return
            }
            let shift = Shift(employee: employee)
            modelContext.insert(shift)
            DesignSystem.HapticFeedback.trigger(.success)

        case .clockOut:
            guard employee.isClockedIn else {
                errorMessage = "\(employee.name) is not currently clocked in."
                showError = true
                enteredPIN = ""
                DesignSystem.HapticFeedback.trigger(.error)
                return
            }
            guard let shift = employee.currentShift else {
                errorMessage = "Current shift was not found."
                showError = true
                enteredPIN = ""
                DesignSystem.HapticFeedback.trigger(.error)
                return
            }
            shift.clockOutTime = Date()
            DesignSystem.HapticFeedback.trigger(.success)
        }
        
        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = "Failed to process clock action: \(error.localizedDescription)"
            showError = true
            enteredPIN = ""
            DesignSystem.HapticFeedback.trigger(.error)
        }
    }
}
