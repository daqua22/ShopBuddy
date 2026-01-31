//
//  PayrollView.swift
//  ShopBuddy
//
//  Created by Dan on 1/29/26.
//

import SwiftUI
import SwiftData

struct PayrollView: View {
    
    @Environment(\.modelContext) private var modelContext
    
    @Query(sort: \PayrollPeriod.startDate, order: .reverse) private var payrollPeriods: [PayrollPeriod]
    @Query(filter: #Predicate<Employee> { $0.isActive }) private var employees: [Employee]
    @Query private var allTips: [DailyTips]
    
    @State private var showingCreatePayroll = false
    @State private var selectedPeriod: PayrollPeriod?
    
    var body: some View {
        ScrollView {
            VStack(spacing: DesignSystem.Spacing.grid_3) {
                if payrollPeriods.isEmpty {
                    EmptyStateView(
                        icon: "banknote",
                        title: "No Payroll Periods",
                        message: "Create your first payroll period to calculate employee compensation",
                        actionTitle: "Create Payroll",
                        action: { showingCreatePayroll = true }
                    )
                } else {
                    payrollPeriodsList
                }
            }
            .padding(DesignSystem.Spacing.grid_2)
        }
        .background(DesignSystem.Colors.background.ignoresSafeArea())
        .navigationTitle("Payroll")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingCreatePayroll = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingCreatePayroll) {
            CreatePayrollView()
        }
        .sheet(item: $selectedPeriod) { period in
            PayrollDetailView(period: period)
        }
    }
    
    private var payrollPeriodsList: some View {
        VStack(spacing: DesignSystem.Spacing.grid_2) {
            ForEach(payrollPeriods) { period in
                PayrollPeriodCard(period: period) {
                    selectedPeriod = period
                }
            }
        }
    }
}

// MARK: - Payroll Period Card
struct PayrollPeriodCard: View {
    
    let period: PayrollPeriod
    let onTap: () -> Void
    
    @Query(filter: #Predicate<Employee> { $0.isActive }) private var employees: [Employee]
    @Query private var allTips: [DailyTips]
    
    private var totalPayroll: Double {
        calculateTotalPayroll()
    }
    
    var body: some View {
        Button {
            onTap()
        } label: {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.grid_2) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(DateRange(start: period.startDate, end: period.endDate).rangeString())
                            .font(DesignSystem.Typography.headline)
                            .foregroundColor(DesignSystem.Colors.primary)
                        
                        HStack(spacing: DesignSystem.Spacing.grid_1) {
                            if period.includeTips {
                                Label("Tips Included", systemImage: "checkmark.circle.fill")
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundColor(DesignSystem.Colors.success)
                            }
                            
                            if period.isPaid {
                                Label("Paid", systemImage: "checkmark.circle.fill")
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundColor(DesignSystem.Colors.success)
                            } else {
                                Label("Unpaid", systemImage: "clock")
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundColor(DesignSystem.Colors.warning)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(totalPayroll.currencyString())
                            .font(DesignSystem.Typography.title2)
                            .foregroundColor(DesignSystem.Colors.primary)
                        
                        Text("Total")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondary)
                    }
                }
                
                Divider()
                
                HStack {
                    Text("\(employees.count) employees")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondary)
                    
                    Spacer()
                    
                    Text("View Details")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.accent)
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(DesignSystem.Colors.accent)
                }
            }
            .padding(DesignSystem.Spacing.grid_2)
        }
        .glassCard()
    }
    
    // Optimized calculation
    private func calculateTotalPayroll() -> Double {
        let dateRange = DateRange(start: period.startDate, end: period.endDate)
        var total = 0.0
        
        // 1. Calculate Global Tips and Global Hours once (Optimization)
        var totalTips = 0.0
        var totalTipHours = 0.0
        
        if period.includeTips {
            let tipsInRange = allTips.filter { dateRange.contains($0.date) }
            totalTips = tipsInRange.reduce(0) { $0 + $1.totalAmount }
            
            // Calculate total tip-eligible hours across ALL employees
            for emp in employees {
                let empShifts = emp.shifts.filter { shift in
                    guard shift.isComplete, shift.includeTips else { return false }
                    return dateRange.contains(shift.clockInTime)
                }
                totalTipHours += empShifts.reduce(0) { $0 + $1.hoursWorked }
            }
        }
        
        // 2. Calculate per employee
        for employee in employees {
            let shifts = employee.shifts.filter { shift in
                guard shift.isComplete else { return false }
                return dateRange.contains(shift.clockInTime)
            }
            
            let hours = shifts.reduce(0) { $0 + $1.hoursWorked }
            
            if let wage = employee.hourlyWage {
                total += hours * wage
            }
            
            if period.includeTips && totalTipHours > 0 {
                let tipHours = shifts.filter { $0.includeTips }.reduce(0) { $0 + $1.hoursWorked }
                let tipShare = (tipHours / totalTipHours) * totalTips
                total += tipShare
            }
        }
        
        return total
    }
}

// MARK: - Create Payroll View
struct CreatePayrollView: View {
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var startDate = Date().startOfWeek
    @State private var endDate = Date().endOfWeek
    @State private var includeTips = true
    @State private var notes = ""
    
    var body: some View {
        Form {
            Section("Payroll Period") {
                DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                DatePicker("End Date", selection: $endDate, displayedComponents: .date)
            }
            
            Section("Settings") {
                Toggle("Include Tips", isOn: $includeTips)
            }
            
            Section("Notes") {
                TextField("Notes (optional)", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
            }
        }
        .scrollContentBackground(.hidden)
        .background(DesignSystem.Colors.background)
        .navigationTitle("Create Payroll")
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
                Button("Create") {
                    createPayroll()
                }
                .disabled(!isValid)
            }
        }
    }
    
    private var isValid: Bool {
        startDate <= endDate
    }
    
    private func createPayroll() {
        let period = PayrollPeriod(
            startDate: startDate,
            endDate: endDate,
            includeTips: includeTips
        )
        period.notes = notes.isEmpty ? nil : notes
        
        modelContext.insert(period)
        
        do {
            try modelContext.save()
            DesignSystem.HapticFeedback.trigger(.success)
            dismiss()
        } catch {
            DesignSystem.HapticFeedback.trigger(.error)
            print("Failed to create payroll: \(error)")
        }
    }
}

// MARK: - Payroll Detail View
struct PayrollDetailView: View {
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @Bindable var period: PayrollPeriod
    
    @Query(filter: #Predicate<Employee> { $0.isActive }) private var employees: [Employee]
    @Query private var allTips: [DailyTips]
    
    private var payrollData: [PayrollEmployeeData] {
        calculatePayrollData()
    }
    
    var body: some View {
        List {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Period")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondary)
                        Text(DateRange(start: period.startDate, end: period.endDate).rangeString())
                            .font(DesignSystem.Typography.body)
                            .foregroundColor(DesignSystem.Colors.primary)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Total")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondary)
                        Text(payrollData.reduce(0) { $0 + $1.total }.currencyString())
                            .font(DesignSystem.Typography.title3)
                            .foregroundColor(DesignSystem.Colors.primary)
                    }
                }
            }
            
            Section("Employee Breakdown") {
                ForEach(payrollData, id: \.employee.id) { data in
                    PayrollEmployeeRow(data: data)
                }
            }
            
            Section {
                Toggle("Mark as Paid", isOn: $period.isPaid)
                    .onChange(of: period.isPaid) { _, _ in
                        saveChanges()
                    }
            }
        }
        .scrollContentBackground(.hidden)
        .background(DesignSystem.Colors.background)
        .navigationTitle("Payroll Details")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }
    
    // Optimized calculation method
    private func calculatePayrollData() -> [PayrollEmployeeData] {
        let dateRange = DateRange(start: period.startDate, end: period.endDate)
        var data: [PayrollEmployeeData] = []
        
        // 1. Calculate Globals FIRST (Optimization)
        let tipsInRange = allTips.filter { dateRange.contains($0.date) }
        let totalTips = period.includeTips ? tipsInRange.reduce(0) { $0 + $1.totalAmount } : 0
        
        var totalTipHours = 0.0
        if period.includeTips {
            // Calculate total hours for tip distribution pool
            for emp in employees {
                let empShifts = emp.shifts.filter { shift in
                    guard shift.isComplete, shift.includeTips else { return false }
                    return dateRange.contains(shift.clockInTime)
                }
                totalTipHours += empShifts.reduce(0) { $0 + $1.hoursWorked }
            }
        }
        
        // 2. Loop through employees only once
        for employee in employees {
            let shifts = employee.shifts.filter { shift in
                guard shift.isComplete else { return false }
                return dateRange.contains(shift.clockInTime)
            }
            
            let hours = shifts.reduce(0) { $0 + $1.hoursWorked }
            
            if hours > 0 {
                let wages = (employee.hourlyWage ?? 0) * hours
                
                // Calculate tip share based on pre-calculated totals
                let tipHours = period.includeTips ? shifts.filter { $0.includeTips }.reduce(0) { $0 + $1.hoursWorked } : 0
                let tipShare = totalTipHours > 0 ? (tipHours / totalTipHours) * totalTips : 0
                
                data.append(PayrollEmployeeData(
                    employee: employee,
                    hours: hours,
                    rate: employee.hourlyWage ?? 0,
                    wages: wages,
                    tips: tipShare,
                    total: wages + tipShare
                ))
            }
        }
        
        return data.sorted { $0.total > $1.total }
    }
    
    private func saveChanges() {
        do {
            try modelContext.save()
            DesignSystem.HapticFeedback.trigger(.success)
        } catch {
            print("Failed to save changes: \(error)")
            DesignSystem.HapticFeedback.trigger(.error)
        }
    }
}

// MARK: - Payroll Employee Data
// KEPT AT FILE LEVEL TO FIX SCOPE ERRORS
struct PayrollEmployeeData {
    let employee: Employee
    let hours: Double
    let rate: Double
    let wages: Double
    let tips: Double
    let total: Double
}

// MARK: - Payroll Employee Row
struct PayrollEmployeeRow: View {
    
    let data: PayrollEmployeeData
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.grid_1) {
            HStack {
                Text(data.employee.name)
                    .font(DesignSystem.Typography.headline)
                    .foregroundColor(DesignSystem.Colors.primary)
                
                Spacer()
                
                Text(data.total.currencyString())
                    .font(DesignSystem.Typography.headline)
                    .foregroundColor(DesignSystem.Colors.primary)
            }
            
            HStack(spacing: DesignSystem.Spacing.grid_2) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hours")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondary)
                    Text(data.hours.hoursString())
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.primary)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rate")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondary)
                    Text(data.rate.currencyString() + "/hr")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.primary)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wages")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondary)
                    Text(data.wages.currencyString())
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.primary)
                }
                
                if data.tips > 0 {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tips")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondary)
                        Text(data.tips.currencyString())
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.success)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
