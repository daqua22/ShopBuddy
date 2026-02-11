//
//  ReportsView.swift
//  ShopBuddy
//
//  Created by Dan on 1/29/26.
//

import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

struct ReportsView: View {
    @Query(sort: \Employee.name) private var employees: [Employee]
    @Query private var checklists: [ChecklistTemplate]
    @Query(
        filter: #Predicate<InventoryItem> { $0.stockLevel < $0.parLevel },
        sort: \InventoryItem.name
    )
    private var belowParInventoryItems: [InventoryItem]
    @Query(filter: #Predicate<Shift> { $0.clockOutTime != nil })
    private var completedShifts: [Shift]
    
    @State private var selectedDateRange = DateRange.thisWeek
    @State private var showingDateRangePicker = false
    @State private var reportSearchText = ""
    
    var body: some View {
        let laborMetrics = calculateLaborMetrics()

        return Group {
            #if os(macOS)
            macReportsContent(laborMetrics: laborMetrics, belowParItems: belowParInventoryItems)
            #else
            iosReportsContent(laborMetrics: laborMetrics, belowParItems: belowParInventoryItems)
            #endif
        }
        .liquidBackground()
        .navigationTitle("Reports")
        #if os(macOS)
        .searchable(text: $reportSearchText, prompt: "Search labor, checklists, inventory, or employee hours")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showingDateRangePicker = true
                } label: {
                    Label(selectedDateRange.rangeString(), systemImage: "calendar")
                }
                .help("Choose report date range")

                if !reportSearchText.isEmpty {
                    Button {
                        reportSearchText = ""
                    } label: {
                        Label("Clear Search", systemImage: "xmark.circle")
                    }
                    .help("Clear report search")
                }
            }
        }
        #endif
        .sheet(isPresented: $showingDateRangePicker) {
            DateRangePickerView(selectedRange: $selectedDateRange)
                .frame(minWidth: 380, minHeight: 320)
        }
    }

    private func iosReportsContent(laborMetrics: LaborMetrics, belowParItems: [InventoryItem]) -> some View {
        ScrollView {
            VStack(spacing: DesignSystem.Spacing.grid_3) {
                // Date range selector
                dateRangeSelector
                
                // Est. labor cost report
                laborEstimateCard(metrics: laborMetrics)
                
                // Checklist completion
                checklistCompletionCard
                
                // Inventory alerts
                inventoryAlertsCard(belowParItems: belowParItems)
                
                // Employee hours breakdown
                employeeHoursCard(hoursData: laborMetrics.perEmployee)
            }
            .padding(DesignSystem.Spacing.grid_2)
            .readableContent()
        }
    }

    #if os(macOS)
    private func macReportsContent(laborMetrics: LaborMetrics, belowParItems: [InventoryItem]) -> some View {
        let filteredChecklistRows = filteredChecklists
        let filteredAlerts = filteredInventoryAlerts(items: belowParItems)
        let filteredHours = filteredEmployeeHours(rows: laborMetrics.perEmployee)

        return ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.grid_2) {
                HStack(spacing: 12) {
                    Text(reportSearchText.isEmpty ? "Operations Snapshot" : "Filtered Snapshot")
                        .font(DesignSystem.Typography.headline)
                    Spacer()
                    reportPill(title: "Low Stock", value: "\(filteredAlerts.count)", color: DesignSystem.Colors.warning)
                    Divider().frame(height: 24)
                    reportPill(title: "Shifts", value: "\(filteredHours.count)", color: DesignSystem.Colors.primary)
                }
                .padding(.horizontal, DesignSystem.Spacing.grid_1)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 280), spacing: DesignSystem.Spacing.grid_2, alignment: .top)],
                    spacing: DesignSystem.Spacing.grid_2
                ) {
                    reportTile(title: "Date Range", systemImage: "calendar") {
                        dateRangeSelector
                    }

                    reportTile(title: "Labor Snapshot", systemImage: "chart.bar.fill") {
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .top, spacing: DesignSystem.Spacing.grid_2) {
                                laborSnapshotValue(title: "Total Hours", value: laborMetrics.totalHours.hoursString(), color: DesignSystem.Colors.primary)
                                laborSnapshotValue(title: "Est. Cost", value: laborMetrics.estimatedCost.currencyString(), color: DesignSystem.Colors.warning)
                                laborSnapshotValue(title: "Avg Rate (est.)", value: laborMetrics.avgRate.currencyString(), color: DesignSystem.Colors.accent)
                            }
                            VStack(alignment: .leading, spacing: DesignSystem.Spacing.grid_1) {
                                laborSnapshotValue(title: "Total Hours", value: laborMetrics.totalHours.hoursString(), color: DesignSystem.Colors.primary)
                                laborSnapshotValue(title: "Est. Cost", value: laborMetrics.estimatedCost.currencyString(), color: DesignSystem.Colors.warning)
                                laborSnapshotValue(title: "Avg Rate (est.)", value: laborMetrics.avgRate.currencyString(), color: DesignSystem.Colors.accent)
                            }
                        }
                    }

                    reportTile(title: "Checklist Completion", systemImage: "checklist", trailingValue: "\(filteredChecklistRows.count)") {
                        if filteredChecklistRows.isEmpty {
                            macEmptyTile(
                                title: reportSearchText.isEmpty ? "No Checklists" : "No Matching Checklists",
                                subtitle: reportSearchText.isEmpty ? "Create checklist templates to track daily work." : "Try a different search term.",
                                actionTitle: reportSearchText.isEmpty ? nil : "Clear Search"
                            ) {
                                reportSearchText = ""
                            }
                        } else {
                            VStack(spacing: 10) {
                                ForEach(filteredChecklistRows.prefix(6)) { checklist in
                                    HStack(spacing: 10) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(checklist.title)
                                                .foregroundColor(DesignSystem.Colors.primary)
                                            Text("\(checklist.tasks.filter { $0.isCompleted }.count) of \(checklist.tasks.count) tasks")
                                                .font(DesignSystem.Typography.caption)
                                                .foregroundColor(DesignSystem.Colors.secondary)
                                        }

                                        Spacer()

                                        ProgressView(value: checklist.completionPercentage, total: 100)
                                            .frame(width: 100)
                                        Text("\(Int(checklist.completionPercentage))%")
                                            .font(DesignSystem.Typography.caption)
                                            .foregroundColor(DesignSystem.Colors.secondary)
                                            .monospacedDigit()
                                    }
                                    .contextMenu {
                                        Button {
                                            copyToClipboard(checklist.title)
                                        } label: {
                                            Label("Copy Checklist Name", systemImage: "doc.on.doc")
                                        }
                                    }
                                }
                            }
                        }
                    }

                    reportTile(title: "Inventory Alerts", systemImage: "exclamationmark.triangle.fill", trailingValue: "\(filteredAlerts.count)") {
                        if filteredAlerts.isEmpty {
                            macEmptyTile(
                                title: reportSearchText.isEmpty ? "No Inventory Alerts" : "No Matching Alerts",
                                subtitle: reportSearchText.isEmpty ? "All items are currently at or above PAR level." : "Try searching for another item or vendor.",
                                actionTitle: reportSearchText.isEmpty ? nil : "Clear Search"
                            ) {
                                reportSearchText = ""
                            }
                        } else {
                            VStack(spacing: 10) {
                                ForEach(filteredAlerts.prefix(8)) { item in
                                    HStack(spacing: 10) {
                                        Circle()
                                            .fill(Color.stockColor(percentage: item.stockPercentage))
                                            .frame(width: 8, height: 8)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.name)
                                                .foregroundColor(DesignSystem.Colors.primary)
                                            if let vendor = item.vendor, !vendor.isEmpty {
                                                Text(vendor)
                                                    .font(DesignSystem.Typography.caption)
                                                    .foregroundColor(DesignSystem.Colors.secondary)
                                            }
                                        }
                                        Spacer()
                                        Text("\(item.stockLevel, specifier: "%.1f") / \(item.parLevel, specifier: "%.1f") \(item.unitType)")
                                            .font(DesignSystem.Typography.caption)
                                            .foregroundColor(DesignSystem.Colors.secondary)
                                    }
                                    .contextMenu {
                                        Button {
                                            copyToClipboard(item.name)
                                        } label: {
                                            Label("Copy Item Name", systemImage: "doc.on.doc")
                                        }
                                        if let vendor = item.vendor, !vendor.isEmpty {
                                            Button {
                                                copyToClipboard(vendor)
                                            } label: {
                                                Label("Copy Vendor", systemImage: "shippingbox")
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    reportTile(title: "Employee Hours", systemImage: "person.3.fill", trailingValue: "\(filteredHours.count)") {
                        if filteredHours.isEmpty {
                            macEmptyTile(
                                title: reportSearchText.isEmpty ? "No Employee Hours" : "No Matching Employees",
                                subtitle: reportSearchText.isEmpty ? "No completed shifts were recorded in this range." : "Try a different search term.",
                                actionTitle: reportSearchText.isEmpty ? nil : "Clear Search"
                            ) {
                                reportSearchText = ""
                            }
                        } else {
                            VStack(spacing: 10) {
                                ForEach(filteredHours, id: \.employee.id) { data in
                                    HStack(spacing: 10) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(data.employee.name)
                                                .foregroundColor(DesignSystem.Colors.primary)
                                            if let wage = data.employee.hourlyWage {
                                                Text("\(wage.currencyString())/hr")
                                                    .font(DesignSystem.Typography.caption)
                                                    .foregroundColor(DesignSystem.Colors.secondary)
                                            }
                                        }
                                        Spacer()
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text(data.hours.hoursString())
                                                .foregroundColor(DesignSystem.Colors.primary)
                                            if let cost = data.cost {
                                                Text(cost.currencyString())
                                                    .font(DesignSystem.Typography.caption)
                                                    .foregroundColor(DesignSystem.Colors.warning)
                                            }
                                        }
                                    }
                                    .contextMenu {
                                        Button {
                                            copyToClipboard(data.employee.name)
                                        } label: {
                                            Label("Copy Employee Name", systemImage: "doc.on.doc")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(DesignSystem.Spacing.grid_2)
            .readableContent(maxWidth: 1200)
        }
        .safeAreaPadding(.top, DesignSystem.Spacing.grid_1)
    }

    private func reportPill(title: String, value: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondary)
            Text(value)
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

    @ViewBuilder
    private func reportTile<Content: View>(
        title: String,
        systemImage: String,
        trailingValue: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.grid_2) {
            HStack(spacing: 10) {
                Label(title, systemImage: systemImage)
                    .font(DesignSystem.Typography.headline)
                    .foregroundColor(DesignSystem.Colors.primary)
                Spacer()
                if let trailingValue {
                    Text(trailingValue)
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondary)
                        .monospacedDigit()
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(DesignSystem.Colors.surface.opacity(0.8))
                        )
                }
            }

            content()
        }
        .padding(DesignSystem.Spacing.grid_2)
        .glassCard()
    }

    private func macEmptyTile(
        title: String,
        subtitle: String,
        actionTitle: String?,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(DesignSystem.Typography.body)
                .foregroundColor(DesignSystem.Colors.primary)
            Text(subtitle)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondary)
            if let actionTitle {
                Button(actionTitle, action: action)
                    .buttonStyle(.link)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var filteredChecklists: [ChecklistTemplate] {
        let query = reportSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return checklists }

        return checklists.filter { checklist in
            reportRowMatches(query: query, fields: [
                checklist.title,
                "\(checklist.tasks.filter { $0.isCompleted }.count)",
                "\(checklist.tasks.count)"
            ])
        }
    }

    private func filteredInventoryAlerts(items: [InventoryItem]) -> [InventoryItem] {
        let query = reportSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return items }

        return items.filter { item in
            reportRowMatches(query: query, fields: [
                item.name,
                item.vendor ?? "",
                item.unitType
            ])
        }
    }

    private func filteredEmployeeHours(rows: [(employee: Employee, hours: Double, cost: Double?)]) -> [(employee: Employee, hours: Double, cost: Double?)] {
        let query = reportSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return rows }

        return rows.filter { row in
            reportRowMatches(query: query, fields: [
                row.employee.name,
                row.employee.role.rawValue
            ])
        }
    }

    private func reportRowMatches(query: String, fields: [String]) -> Bool {
        let normalizedQuery = query.lowercased()
        return fields.contains { $0.lowercased().contains(normalizedQuery) }
    }

    private func copyToClipboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func laborSnapshotValue(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondary)
            Text(value)
                .font(DesignSystem.Typography.headline)
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
    #endif
    
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
    
    private func laborEstimateCard(metrics: LaborMetrics) -> some View {
        return VStack(alignment: .leading, spacing: DesignSystem.Spacing.grid_2) {
            Text("Est. Labor Cost")
                .font(DesignSystem.Typography.title3)
                .foregroundColor(DesignSystem.Colors.primary)
            
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DesignSystem.Spacing.grid_3) {
                    laborMetricColumn(
                        title: "Total Hours",
                        value: metrics.totalHours.hoursString(),
                        valueColor: DesignSystem.Colors.primary
                    )
                    
                    Divider()
                    
                    laborMetricColumn(
                        title: "Est. Cost",
                        value: metrics.estimatedCost.currencyString(),
                        valueColor: DesignSystem.Colors.warning
                    )
                    
                    Divider()
                    
                    laborMetricColumn(
                        title: "Avg. Rate (est.)",
                        value: metrics.avgRate.currencyString(),
                        valueColor: DesignSystem.Colors.accent
                    )
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.grid_2) {
                    laborMetricColumn(
                        title: "Total Hours",
                        value: metrics.totalHours.hoursString(),
                        valueColor: DesignSystem.Colors.primary
                    )
                    laborMetricColumn(
                        title: "Est. Cost",
                        value: metrics.estimatedCost.currencyString(),
                        valueColor: DesignSystem.Colors.warning
                    )
                    laborMetricColumn(
                        title: "Avg. Rate (est.)",
                        value: metrics.avgRate.currencyString(),
                        valueColor: DesignSystem.Colors.accent
                    )
                }
            }
        }
        .frame(maxWidth: .infinity)
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
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(DesignSystem.Spacing.grid_2)
        .glassCard()
    }
    
    private func inventoryAlertsCard(belowParItems: [InventoryItem]) -> some View {
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
        .frame(maxWidth: .infinity)
        .padding(DesignSystem.Spacing.grid_2)
        .glassCard()
    }
    
    private func employeeHoursCard(hoursData: [(employee: Employee, hours: Double, cost: Double?)]) -> some View {
        return VStack(alignment: .leading, spacing: DesignSystem.Spacing.grid_2) {
            // Frame for full width consistency with other cards
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
        .frame(maxWidth: .infinity)
        .padding(DesignSystem.Spacing.grid_2)
        .glassCard()
    }
    
    private struct LaborMetrics {
        let totalHours: Double
        let estimatedCost: Double
        let avgRate: Double
        let perEmployee: [(employee: Employee, hours: Double, cost: Double?)]
    }

    private func laborMetricColumn(title: String, value: String, valueColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondary)
            Text(value)
                .font(DesignSystem.Typography.title2)
                .foregroundColor(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private func calculateLaborMetrics() -> LaborMetrics {
        var hoursByEmployeeID: [UUID: Double] = [:]
        hoursByEmployeeID.reserveCapacity(employees.count)

        for shift in completedShifts {
            guard let employeeID = shift.employee?.id else { continue }
            let hours = shift.hoursWorked(in: selectedDateRange)
            guard hours > 0 else { continue }
            hoursByEmployeeID[employeeID, default: 0] += hours
        }

        var totalHours = 0.0
        var totalCost = 0.0
        var perEmployee: [(employee: Employee, hours: Double, cost: Double?)] = []
        
        for employee in employees {
            let hours = hoursByEmployeeID[employee.id] ?? 0
            totalHours += hours
            
            if let wage = employee.hourlyWage {
                totalCost += hours * wage
                if hours > 0 {
                    perEmployee.append((employee: employee, hours: hours, cost: hours * wage))
                }
            } else if hours > 0 {
                perEmployee.append((employee: employee, hours: hours, cost: nil))
            }
        }
        
        let avgRate = totalHours > 0 ? totalCost / totalHours : 0
        let sortedEmployeeData = perEmployee.sorted { $0.hours > $1.hours }
        return LaborMetrics(totalHours: totalHours, estimatedCost: totalCost, avgRate: avgRate, perEmployee: sortedEmployeeData)
    }
}
