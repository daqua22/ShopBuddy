//
//  TipsView.swift
//  ShopBuddy
//
//  Created by Dan on 1/29/26.
//

import SwiftUI
import SwiftData

struct TipsView: View {
    
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var modelContext
    
    @Query(sort: \DailyTips.date, order: .reverse) private var allTips: [DailyTips]
    @Query(filter: #Predicate<Employee> { $0.isActive }) private var employees: [Employee]
    
    @State private var showingAddTips = false
    @State private var selectedDateRange = DateRange.thisWeek
    @State private var showingDateRangePicker = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: DesignSystem.Spacing.grid_3) {
                // Date range selector
                dateRangeSelector
                
                // Tips summary
                tipsSummaryCard
                
                // Employee breakdown
                if coordinator.isManager {
                    employeeTipsBreakdown
                } else if let employee = coordinator.currentEmployee {
                    singleEmployeeTips(employee: employee)
                }
                
                // Daily tips list
                if coordinator.isManager {
                    dailyTipsList
                }
            }
            .padding(DesignSystem.Spacing.grid_2)
        }
        .background(DesignSystem.Colors.background.ignoresSafeArea())
        .navigationTitle("Tips")
        .toolbar {
            if coordinator.isManager {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddTips = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddTips) {
            NavigationStack {
                AddDailyTipsView()
            }
            .frame(minWidth: 480, idealWidth: 520, minHeight: 480, idealHeight: 520)
        }
        .sheet(isPresented: $showingDateRangePicker) {
            DateRangePickerView(selectedRange: $selectedDateRange)
        }
    }
    
    private var dateRangeSelector: some View {
        Button {
            showingDateRangePicker = true
        } label: {
            HStack {
                Image(systemName: "calendar")
                Text(selectedDateRange.rangeString())
                    .font(DesignSystem.Typography.headline)
                Spacer()
                Image(systemName: "chevron.down")
            }
            .foregroundColor(DesignSystem.Colors.primary)
            .padding(DesignSystem.Spacing.grid_2)
        }
        .glassCard()
    }
    
    private var tipsSummaryCard: some View {
        let tipsInRange = allTips.filter { selectedDateRange.contains($0.date) }
        let totalTips = tipsInRange.reduce(0) { $0 + $1.totalAmount }
        let paidTips = tipsInRange.filter { $0.isPaid }.reduce(0) { $0 + $1.totalAmount }
        let unpaidTips = totalTips - paidTips
        
        return VStack(spacing: DesignSystem.Spacing.grid_2) {
            HStack {
                Text("Tips Summary")
                    .font(DesignSystem.Typography.title3)
                    .foregroundColor(DesignSystem.Colors.primary)
                Spacer()
            }
            
            HStack(spacing: DesignSystem.Spacing.grid_3) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondary)
                    Text(totalTips.currencyString())
                        .font(DesignSystem.Typography.title2)
                        .foregroundColor(DesignSystem.Colors.primary)
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Paid")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondary)
                    Text(paidTips.currencyString())
                        .font(DesignSystem.Typography.title2)
                        .foregroundColor(DesignSystem.Colors.success)
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Unpaid")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondary)
                    Text(unpaidTips.currencyString())
                        .font(DesignSystem.Typography.title2)
                        .foregroundColor(DesignSystem.Colors.warning)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(DesignSystem.Spacing.grid_2)
        .glassCard()
    }
    
    private var employeeTipsBreakdown: some View {
        let tipsData = calculateTipsForAllEmployees()
        
        return VStack(alignment: .leading, spacing: DesignSystem.Spacing.grid_2) {
            Text("Employee Breakdown")
                .font(DesignSystem.Typography.title3)
                .foregroundColor(DesignSystem.Colors.primary)
            
            if tipsData.isEmpty {
                Text("No tips recorded in this period")
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignSystem.Spacing.grid_3)
                    .glassCard()
            } else {
                VStack(spacing: DesignSystem.Spacing.grid_1) {
                    ForEach(tipsData, id: \.employee.id) { data in
                        EmployeeTipsRow(
                            employeeName: data.employee.name,
                            hours: data.hours,
                            tipAmount: data.tips
                        )
                    }
                }
            }
        }
    }
    
    private func singleEmployeeTips(employee: Employee) -> some View {
        let tipsData = calculateTipsForEmployee(employee)
        
        return VStack(alignment: .leading, spacing: DesignSystem.Spacing.grid_2) {
            Text("Your Tips")
                .font(DesignSystem.Typography.title3)
                .foregroundColor(DesignSystem.Colors.primary)
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hours Worked")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondary)
                    Text(tipsData.hours.hoursString())
                        .font(DesignSystem.Typography.title2)
                        .foregroundColor(DesignSystem.Colors.primary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Tips Earned")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondary)
                    Text(tipsData.tips.currencyString())
                        .font(DesignSystem.Typography.title2)
                        .foregroundColor(DesignSystem.Colors.success)
                }
            }
            .padding(DesignSystem.Spacing.grid_2)
            .glassCard()
        }
    }
    
    private var dailyTipsList: some View {
        let tipsInRange = allTips.filter { selectedDateRange.contains($0.date) }
        
        return VStack(alignment: .leading, spacing: DesignSystem.Spacing.grid_2) {
            Text("Daily Tips")
                .font(DesignSystem.Typography.title3)
                .foregroundColor(DesignSystem.Colors.primary)
            
            if tipsInRange.isEmpty {
                Text("No tips recorded")
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignSystem.Spacing.grid_3)
                    .glassCard()
            } else {
                VStack(spacing: DesignSystem.Spacing.grid_1) {
                    ForEach(tipsInRange) { tips in
                        DailyTipsRow(tips: tips)
                    }
                }
            }
        }
    }
    
    private func calculateTipsForAllEmployees() -> [(employee: Employee, hours: Double, tips: Double)] {
        let tipsInRange = allTips.filter { selectedDateRange.contains($0.date) }
        let totalTips = tipsInRange.reduce(0) { $0 + $1.totalAmount }
        
        var employeeData: [(employee: Employee, hours: Double, tips: Double)] = []
        
        for employee in employees {
            let shifts = employee.shifts.filter { shift in
                guard shift.isComplete, shift.includeTips else { return false }
                return selectedDateRange.contains(shift.clockInTime)
            }
            
            let totalHours = shifts.reduce(0) { $0 + $1.hoursWorked }
            employeeData.append((employee: employee, hours: totalHours, tips: 0))
        }
        
        let totalHours = employeeData.reduce(0) { $0 + $1.hours }
        
        if totalHours > 0 {
            employeeData = employeeData.map { data in
                let tipShare = (data.hours / totalHours) * totalTips
                return (employee: data.employee, hours: data.hours, tips: tipShare)
            }
        }
        
        return employeeData.sorted { $0.tips > $1.tips }
    }
    
    private func calculateTipsForEmployee(_ employee: Employee) -> (hours: Double, tips: Double) {
        let tipsInRange = allTips.filter { selectedDateRange.contains($0.date) }
        let totalTips = tipsInRange.reduce(0) { $0 + $1.totalAmount }
        
        let shifts = employee.shifts.filter { shift in
            guard shift.isComplete, shift.includeTips else { return false }
            return selectedDateRange.contains(shift.clockInTime)
        }
        
        let employeeHours = shifts.reduce(0) { $0 + $1.hoursWorked }
        
        // Calculate total hours for all employees
        var totalHours = 0.0
        for emp in employees {
            let empShifts = emp.shifts.filter { shift in
                guard shift.isComplete, shift.includeTips else { return false }
                return selectedDateRange.contains(shift.clockInTime)
            }
            totalHours += empShifts.reduce(0) { $0 + $1.hoursWorked }
        }
        
        let tipShare = totalHours > 0 ? (employeeHours / totalHours) * totalTips : 0
        
        return (hours: employeeHours, tips: tipShare)
    }
}

// MARK: - Employee Tips Row
struct EmployeeTipsRow: View {
    let employeeName: String
    let hours: Double
    let tipAmount: Double
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(employeeName)
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.primary)
                
                Text(hours.hoursString())
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondary)
            }
            
            Spacer()
            
            Text(tipAmount.currencyString())
                .font(DesignSystem.Typography.headline)
                .foregroundColor(DesignSystem.Colors.success)
        }
        .padding(DesignSystem.Spacing.grid_2)
        .glassCard()
    }
}

// MARK: - Daily Tips Row
struct DailyTipsRow: View {
    
    @Bindable var tips: DailyTips
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(tips.date.dateString())
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.primary)
                
                if tips.isPaid, let paidDate = tips.paidDate {
                    Text("Paid on \(paidDate.dateString())")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.success)
                }
            }
            
            Spacer()
            
            Text(tips.totalAmount.currencyString())
                .font(DesignSystem.Typography.headline)
                .foregroundColor(DesignSystem.Colors.primary)
            
            if !tips.isPaid {
                Button {
                    markAsPaid()
                } label: {
                    Text("Mark Paid")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, DesignSystem.Spacing.grid_1)
                        .padding(.vertical, 6)
                        .background(DesignSystem.Colors.accent)
                        .cornerRadius(DesignSystem.CornerRadius.small)
                }
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(DesignSystem.Colors.success)
            }
        }
        .padding(DesignSystem.Spacing.grid_2)
        .glassCard()
    }
    
    private func markAsPaid() {
        tips.markAsPaid()
        DesignSystem.HapticFeedback.trigger(.success)
        
        do {
            try modelContext.save()
        } catch {
            print("Failed to mark tips as paid: \(error)")
            DesignSystem.HapticFeedback.trigger(.error)
        }
    }
}

// MARK: - Add Daily Tips View
struct AddDailyTipsView: View {
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var selectedDate = Date()
    @State private var amount = ""
    @State private var notes = ""
    
    var body: some View {
        Form {
            Section("Tip Information") {
                DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
                
                #if os(iOS)
                TextField("Amount", text: $amount)
                    .keyboardType(.decimalPad)
                #else
                TextField("Amount", text: $amount)
                #endif
            }
            
            Section("Notes") {
                TextField("Notes (optional)", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Add Tips")
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
                    saveTips()
                }
                .disabled(!isValid)
            }
        }
    }
    
    private var isValid: Bool {
        guard let _ = Double(amount) else { return false }
        return true
    }
    
    private func saveTips() {
        guard let amountValue = Double(amount) else { return }
        
        let tips = DailyTips(date: selectedDate, totalAmount: amountValue)
        tips.notes = notes.isEmpty ? nil : notes
        
        modelContext.insert(tips)
        
        do {
            try modelContext.save()
            DesignSystem.HapticFeedback.trigger(.success)
            dismiss()
        } catch {
            DesignSystem.HapticFeedback.trigger(.error)
            print("Failed to save tips: \(error)")
        }
    }
}

// MARK: - Date Range Picker View
struct DateRangePickerView: View {
    
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedRange: DateRange
    
    @State private var customStartDate = Date()
    @State private var customEndDate = Date()
    @State private var showingCustom = false
    
    var body: some View {
        NavigationStack {
            List {
                Section("Preset Ranges") {
                    Button {
                        selectedRange = .thisWeek
                        dismiss()
                    } label: {
                        Text("This Week")
                    }
                    
                    Button {
                        selectedRange = .lastWeek
                        dismiss()
                    } label: {
                        Text("Last Week")
                    }
                    
                    Button {
                        selectedRange = .thisMonth
                        dismiss()
                    } label: {
                        Text("This Month")
                    }
                }
                
                Section("Custom Range") {
                    DatePicker("Start Date", selection: $customStartDate, displayedComponents: .date)
                    DatePicker("End Date", selection: $customEndDate, displayedComponents: .date)
                    
                    Button("Apply Custom Range") {
                        selectedRange = DateRange.custom(start: customStartDate, end: customEndDate)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Select Date Range")
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
}
