//
//  PaySummaryView.swift
//  ShopBuddy
//
//  Created by Dan on 1/29/26.
//

import SwiftUI
import SwiftData

struct PaySummaryView: View {
    
    @Environment(\.modelContext) private var modelContext
    
    @Query(sort: \PayPeriod.startDate, order: .reverse) private var payPeriods: [PayPeriod]
    @Query(filter: #Predicate<Employee> { $0.isActive }) private var employees: [Employee]
    @Query private var allTips: [DailyTips]
    
    @State private var showingCreatePeriod = false
    @State private var selectedPeriod: PayPeriod?
    
    var body: some View {
        ScrollView {
            VStack(spacing: DesignSystem.Spacing.grid_3) {
                if payPeriods.isEmpty {
                    EmptyStateView(
                        icon: "banknote",
                        title: "No Pay Periods",
                        message: "Create a pay period to preview estimated pay",
                        actionTitle: "New Period",
                        action: { showingCreatePeriod = true }
                    )
                } else {
                    payPeriodsList
                }

                disclaimerFooter
            }
            .padding(DesignSystem.Spacing.grid_2)
        }
        .background(DesignSystem.Colors.background.ignoresSafeArea())
        .navigationTitle("Pay Summary")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingCreatePeriod = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingCreatePeriod) {
            NavigationStack {
                CreatePayPeriodView()
            }
            .frame(minWidth: 480, idealWidth: 520, minHeight: 520, idealHeight: 560)
        }
        .sheet(item: $selectedPeriod) { period in
            NavigationStack {
                PayPeriodDetailView(period: period)
            }
            .frame(minWidth: 480, idealWidth: 520, minHeight: 520, idealHeight: 560)
        }
    }
    
    private var payPeriodsList: some View {
        VStack(spacing: DesignSystem.Spacing.grid_2) {
            ForEach(payPeriods) { period in
                PayPeriodCard(period: period) {
                    selectedPeriod = period
                }
            }
        }
    }

    private var disclaimerFooter: some View {
        Text("Estimates based on logged hours and rates. For internal reference only — not a payroll document.")
            .font(DesignSystem.Typography.caption)
            .foregroundColor(DesignSystem.Colors.tertiary)
            .multilineTextAlignment(.center)
            .padding(.top, DesignSystem.Spacing.grid_2)
    }
}

// MARK: - Pay Period Card
struct PayPeriodCard: View {
    
    let period: PayPeriod
    let onTap: () -> Void
    
    @Query(filter: #Predicate<Employee> { $0.isActive }) private var employees: [Employee]
    @Query private var allTips: [DailyTips]
    
    private var estimatedTotal: Double {
        calculatePayEstimate()
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
                                Label("Tips Included", systemImage: "dollarsign.circle")
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundColor(DesignSystem.Colors.success)
                            }
                            
                            if period.isReviewed {
                                Label("Reviewed", systemImage: "eye.fill")
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundColor(DesignSystem.Colors.accent)
                            } else {
                                Label("Pending Review", systemImage: "clock")
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundColor(DesignSystem.Colors.secondary)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(estimatedTotal.currencyString())
                            .font(DesignSystem.Typography.title2)
                            .foregroundColor(DesignSystem.Colors.primary)
                        
                        Text("Est. Total")
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
    private func calculatePayEstimate() -> Double {
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

// MARK: - Create Pay Period View
struct CreatePayPeriodView: View {
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var startDate = Date().startOfWeek
    @State private var endDate = Date().endOfWeek
    @State private var includeTips = true
    @State private var notes = ""
    
    var body: some View {
        Form {
            Section("Date Range") {
                DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                DatePicker("End Date", selection: $endDate, displayedComponents: .date)
            }
            
            Section("Options") {
                Toggle("Include Tips", isOn: $includeTips)
            }
            
            Section("Notes") {
                TextField("Notes (optional)", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("New Pay Period")
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
                    createPeriod()
                }
                .disabled(!isValid)
            }
        }
    }
    
    private var isValid: Bool {
        startDate <= endDate
    }
    
    private func createPeriod() {
        let period = PayPeriod(
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
            print("Failed to create pay period: \(error)")
        }
    }
}

// MARK: - Pay Period Detail View
struct PayPeriodDetailView: View {
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @Bindable var period: PayPeriod
    
    @Query(filter: #Predicate<Employee> { $0.isActive }) private var employees: [Employee]
    @Query private var allTips: [DailyTips]
    
    private var estimateData: [PayEstimateData] {
        calculatePayEstimateData()
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
                        Text("Est. Total")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondary)
                        Text(estimateData.reduce(0) { $0 + $1.estimatedTotal }.currencyString())
                            .font(DesignSystem.Typography.title3)
                            .foregroundColor(DesignSystem.Colors.primary)
                    }
                }
            }
            
            Section("Employee Breakdown") {
                ForEach(estimateData, id: \.employee.id) { data in
                    PayEstimateRow(data: data)
                }
            }
            
            Section {
                Toggle("Mark as Reviewed", isOn: $period.isReviewed)
                    .onChange(of: period.isReviewed) { _, _ in
                        saveChanges()
                    }
            }

            Section {
                Text("Estimates based on logged hours and rates. For internal reference only — not a payroll document.")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.tertiary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Pay Preview")
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
    private func calculatePayEstimateData() -> [PayEstimateData] {
        let dateRange = DateRange(start: period.startDate, end: period.endDate)
        var data: [PayEstimateData] = []
        
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
                let estimatedPay = (employee.hourlyWage ?? 0) * hours
                
                // Calculate tip share based on pre-calculated totals
                let tipHours = period.includeTips ? shifts.filter { $0.includeTips }.reduce(0) { $0 + $1.hoursWorked } : 0
                let tipShare = totalTipHours > 0 ? (tipHours / totalTipHours) * totalTips : 0
                
                data.append(PayEstimateData(
                    employee: employee,
                    hours: hours,
                    rate: employee.hourlyWage ?? 0,
                    estimatedPay: estimatedPay,
                    tips: tipShare,
                    estimatedTotal: estimatedPay + tipShare
                ))
            }
        }
        
        return data.sorted { $0.estimatedTotal > $1.estimatedTotal }
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

// MARK: - Pay Estimate Data
// KEPT AT FILE LEVEL TO FIX SCOPE ERRORS
struct PayEstimateData {
    let employee: Employee
    let hours: Double
    let rate: Double
    let estimatedPay: Double
    let tips: Double
    let estimatedTotal: Double
}

// MARK: - Pay Estimate Row
struct PayEstimateRow: View {
    
    let data: PayEstimateData
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.grid_1) {
            HStack {
                Text(data.employee.name)
                    .font(DesignSystem.Typography.headline)
                    .foregroundColor(DesignSystem.Colors.primary)
                
                Spacer()
                
                Text(data.estimatedTotal.currencyString())
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
                    Text("Est. Pay")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondary)
                    Text(data.estimatedPay.currencyString())
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
