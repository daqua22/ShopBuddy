//
//  ReportsView.swift
//  ShopBuddy
//
//  Created by Dan on 1/29/26.
//

import SwiftUI
import SwiftData
import Charts

struct ReportsView: View {
    
    @Environment(\.modelContext) private var modelContext
    
    @Query(filter: #Predicate<Employee> { $0.isActive }) private var employees: [Employee]
    @Query private var checklists: [ChecklistTemplate]
    @Query(sort: \InventoryItem.name) private var inventoryItems: [InventoryItem]
    
    @State private var selectedDateRange = DateRange.thisWeek
    @State private var showingDateRangePicker = false
    
    var body: some View {
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.grid_3) {
                    // Date range selector
                    dateRangeSelector
                    
                    // Labor cost report
                    laborCostCard
                    
                    // Checklist completion
                    checklistCompletionCard
                    
                    // Inventory alerts
                    inventoryAlertsCard
                    
                    // Employee hours breakdown
                    employeeHoursCard
                }
                .padding(DesignSystem.Spacing.grid_2)
            }
            .background(DesignSystem.Colors.background.ignoresSafeArea())
            .navigationTitle("Reports")
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
    
    private var laborCostCard: some View {
        let data = calculateLaborCost()
        
        return VStack(alignment: .leading, spacing: DesignSystem.Spacing.grid_2) {
            Text("Labor Cost")
                .font(DesignSystem.Typography.title3)
                .foregroundColor(DesignSystem.Colors.primary)
            
            HStack(spacing: DesignSystem.Spacing.grid_3) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total Hours")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondary)
                    Text(data.totalHours.hoursString())
                        .font(DesignSystem.Typography.title2)
                        .foregroundColor(DesignSystem.Colors.primary)
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total Cost")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondary)
                    Text(data.totalCost.currencyString())
                        .font(DesignSystem.Typography.title2)
                        .foregroundColor(DesignSystem.Colors.warning)
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Avg. Rate")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondary)
                    Text(data.avgRate.currencyString())
                        .font(DesignSystem.Typography.title2)
                        .foregroundColor(DesignSystem.Colors.accent)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(DesignSystem.Spacing.grid_2)
        .glassCard()
    }
    
    private var checklistCompletionCard: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.grid_2) {
            Text("Checklist Completion")
                .font(DesignSystem.Typography.title3)
                .foregroundColor(DesignSystem.Colors.primary)
            
            if checklists.isEmpty {
                Text("No checklists available")
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.secondary)
            } else {
                VStack(spacing: DesignSystem.Spacing.grid_2) {
                    ForEach(checklists) { checklist in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(checklist.title)
                                    .font(DesignSystem.Typography.body)
                                    .foregroundColor(DesignSystem.Colors.primary)
                                
                                Text("\(checklist.tasks.filter { $0.isCompleted }.count) of \(checklist.tasks.count) tasks")
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundColor(DesignSystem.Colors.secondary)
                            }
                            
                            Spacer()
                            
                            ZStack {
                                Circle()
                                    .stroke(DesignSystem.Colors.surface, lineWidth: 4)
                                    .frame(width: 50, height: 50)
                                
                                Circle()
                                    .trim(from: 0, to: checklist.completionPercentage / 100)
                                    .stroke(DesignSystem.Colors.accent, lineWidth: 4)
                                    .frame(width: 50, height: 50)
                                    .rotationEffect(.degrees(-90))
                                
                                Text("\(Int(checklist.completionPercentage))%")
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundColor(DesignSystem.Colors.primary)
                            }
                        }
                    }
                }
            }
        }
        .padding(DesignSystem.Spacing.grid_2)
        .glassCard()
    }
    
    private var inventoryAlertsCard: some View {
        let belowParItems = inventoryItems.filter { $0.isBelowPar }
        
        return VStack(alignment: .leading, spacing: DesignSystem.Spacing.grid_2) {
            HStack {
                Text("Inventory Alerts")
                    .font(DesignSystem.Typography.title3)
                    .foregroundColor(DesignSystem.Colors.primary)
                
                Spacer()
                
                if !belowParItems.isEmpty {
                    Text("\(belowParItems.count)")
                        .font(DesignSystem.Typography.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(DesignSystem.Colors.error)
                        .cornerRadius(DesignSystem.CornerRadius.small)
                }
            }
            
            if belowParItems.isEmpty {
                Text("All items are at or above PAR level")
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.success)
            } else {
                VStack(spacing: DesignSystem.Spacing.grid_1) {
                    ForEach(belowParItems.prefix(5)) { item in
                        HStack {
                            Circle()
                                .fill(Color.stockColor(percentage: item.stockPercentage))
                                .frame(width: 8, height: 8)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(DesignSystem.Typography.body)
                                    .foregroundColor(DesignSystem.Colors.primary)
                                
                                Text("\(item.stockLevel, specifier: "%.1f") / \(item.parLevel, specifier: "%.1f") \(item.unitType)")
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundColor(DesignSystem.Colors.secondary)
                            }
                            
                            Spacer()
                        }
                    }
                    
                    if belowParItems.count > 5 {
                        Text("+ \(belowParItems.count - 5) more items")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondary)
                    }
                }
            }
        }
        .padding(DesignSystem.Spacing.grid_2)
        .glassCard()
    }
    
    private var employeeHoursCard: some View {
        let hoursData = calculateEmployeeHours()
        
        return VStack(alignment: .leading, spacing: DesignSystem.Spacing.grid_2) {
            Text("Employee Hours")
                .font(DesignSystem.Typography.title3)
                .foregroundColor(DesignSystem.Colors.primary)
            
            if hoursData.isEmpty {
                Text("No shifts recorded in this period")
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.secondary)
            } else {
                VStack(spacing: DesignSystem.Spacing.grid_1) {
                    ForEach(hoursData, id: \.employee.id) { data in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(data.employee.name)
                                    .font(DesignSystem.Typography.body)
                                    .foregroundColor(DesignSystem.Colors.primary)
                                
                                if let wage = data.employee.hourlyWage {
                                    Text(wage.currencyString() + "/hr")
                                        .font(DesignSystem.Typography.caption)
                                        .foregroundColor(DesignSystem.Colors.secondary)
                                }
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(data.hours.hoursString())
                                    .font(DesignSystem.Typography.headline)
                                    .foregroundColor(DesignSystem.Colors.primary)
                                
                                if let cost = data.cost {
                                    Text(cost.currencyString())
                                        .font(DesignSystem.Typography.caption)
                                        .foregroundColor(DesignSystem.Colors.warning)
                                }
                            }
                        }
                        .padding(.vertical, DesignSystem.Spacing.grid_1)
                    }
                }
            }
        }
        .padding(DesignSystem.Spacing.grid_2)
        .glassCard()
    }
    
    private func calculateLaborCost() -> (totalHours: Double, totalCost: Double, avgRate: Double) {
        var totalHours = 0.0
        var totalCost = 0.0
        var employeesWithWage = 0
        
        for employee in employees {
            let shifts = employee.shifts.filter { shift in
                guard shift.isComplete else { return false }
                return selectedDateRange.contains(shift.clockInTime)
            }
            
            let hours = shifts.reduce(0) { $0 + $1.hoursWorked }
            totalHours += hours
            
            if let wage = employee.hourlyWage {
                totalCost += hours * wage
                employeesWithWage += 1
            }
        }
        
        let avgRate = employeesWithWage > 0 ? totalCost / totalHours : 0
        
        return (totalHours: totalHours, totalCost: totalCost, avgRate: avgRate)
    }
    
    private func calculateEmployeeHours() -> [(employee: Employee, hours: Double, cost: Double?)] {
        var data: [(employee: Employee, hours: Double, cost: Double?)] = []
        
        for employee in employees {
            let shifts = employee.shifts.filter { shift in
                guard shift.isComplete else { return false }
                return selectedDateRange.contains(shift.clockInTime)
            }
            
            let hours = shifts.reduce(0) { $0 + $1.hoursWorked }
            
            if hours > 0 {
                let cost = employee.hourlyWage.map { $0 * hours }
                data.append((employee: employee, hours: hours, cost: cost))
            }
        }
        
        return data.sorted { $0.hours > $1.hours }
    }
}
