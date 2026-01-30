//
//  Models.swift
//  ShopBuddy
//
//  Created by Dan on 1/29/26.
//

import Foundation
import SwiftData

// MARK: - Employee Role
enum EmployeeRole: String, Codable, CaseIterable {
    case manager = "Manager"
    case shiftLead = "Shift Lead"
    case employee = "Employee"
    
    var sortOrder: Int {
        switch self {
        case .manager: return 0
        case .shiftLead: return 1
        case .employee: return 2
        }
    }
}

// MARK: - Employee
@Model
final class Employee {
    var id: UUID
    var name: String
    var pin: String // 4-digit PIN
    var roleRaw: String
    var hourlyWage: Double?
    var createdAt: Date
    var isActive: Bool
    
    @Relationship(deleteRule: .cascade, inverse: \Shift.employee)
    var shifts: [Shift]
    
    var role: EmployeeRole {
        get { EmployeeRole(rawValue: roleRaw) ?? .employee }
        set { roleRaw = newValue.rawValue }
    }
    
    init(
        name: String,
        pin: String,
        role: EmployeeRole,
        hourlyWage: Double? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.pin = pin
        self.roleRaw = role.rawValue
        self.hourlyWage = hourlyWage
        self.createdAt = Date()
        self.isActive = true
        self.shifts = []
    }
    
    /// Get currently active shift
    var currentShift: Shift? {
        shifts.first(where: { $0.clockOutTime == nil })
    }
    
    /// Check if employee is currently clocked in
    var isClockedIn: Bool {
        currentShift != nil
    }
}

// MARK: - Shift
@Model
final class Shift {
    var id: UUID
    var clockInTime: Date
    var clockOutTime: Date?
    var manuallyAdded: Bool
    var includeTips: Bool
    var notes: String?
    
    var employee: Employee?
    
    init(
        employee: Employee,
        clockInTime: Date = Date(),
        clockOutTime: Date? = nil,
        manuallyAdded: Bool = false,
        includeTips: Bool = true,
        notes: String? = nil
    ) {
        self.id = UUID()
        self.clockInTime = clockInTime
        self.clockOutTime = clockOutTime
        self.manuallyAdded = manuallyAdded
        self.includeTips = includeTips
        self.notes = notes
        self.employee = employee
    }
    
    /// Calculate hours worked
    var hoursWorked: Double {
        let endTime = clockOutTime ?? Date()
        let interval = endTime.timeIntervalSince(clockInTime)
        return interval / 3600.0 // Convert seconds to hours
    }
    
    /// Check if shift is complete
    var isComplete: Bool {
        clockOutTime != nil
    }
    
    /// Format duration as string
    var durationString: String {
        let hours = Int(hoursWorked)
        let minutes = Int((hoursWorked - Double(hours)) * 60)
        return String(format: "%dh %dm", hours, minutes)
    }
}

// MARK: - Inventory Category Type
enum InventoryCategoryType: String, Codable, CaseIterable {
    case monthly = "Monthly"
    case weekly = "Weekly"
    case quarterly = "Quarterly"
    case daily = "Daily"
    case asNeeded = "As Needed"
    
    var sortOrder: Int {
        switch self {
        case .daily: return 0
        case .weekly: return 1
        case .monthly: return 2
        case .quarterly: return 3
        case .asNeeded: return 4
        }
    }
}

// MARK: - Inventory Item
@Model
final class InventoryItem {
    var id: UUID
    var name: String
    var categoryRaw: String // Main category (Monthly, Weekly, etc.)
    var subcategory: String // Location (Bar fridge, Back shelf, etc.)
    var stockLevel: Double
    var parLevel: Double // Minimum stock level before alert
    var unitType: String // e.g., "kg", "L", "units", "boxes"
    var lastRestocked: Date?
    var notes: String?
    var createdAt: Date
    
    var category: InventoryCategoryType {
        get { InventoryCategoryType(rawValue: categoryRaw) ?? .asNeeded }
        set { categoryRaw = newValue.rawValue }
    }
    
    init(
        name: String,
        category: InventoryCategoryType,
        subcategory: String,
        stockLevel: Double,
        parLevel: Double,
        unitType: String,
        notes: String? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.categoryRaw = category.rawValue
        self.subcategory = subcategory
        self.stockLevel = stockLevel
        self.parLevel = parLevel
        self.unitType = unitType
        self.notes = notes
        self.createdAt = Date()
        self.lastRestocked = Date()
    }
    
    /// Check if stock is below PAR level
    var isBelowPar: Bool {
        stockLevel < parLevel
    }
    
    /// Calculate stock percentage
    var stockPercentage: Double {
        guard parLevel > 0 else { return 1.0 }
        return min(stockLevel / parLevel, 1.0)
    }
}

// MARK: - Checklist Task
@Model
final class ChecklistTask {
    var id: UUID
    var title: String
    var isCompleted: Bool
    var completedBy: String? // Employee name
    var completedAt: Date?
    var sortOrder: Int
    
    var template: ChecklistTemplate?
    
    init(title: String, sortOrder: Int = 0) {
        self.id = UUID()
        self.title = title
        self.isCompleted = false
        self.sortOrder = sortOrder
    }
    
    func markComplete(by employeeName: String) {
        self.isCompleted = true
        self.completedBy = employeeName
        self.completedAt = Date()
    }
    
    func reset() {
        self.isCompleted = false
        self.completedBy = nil
        self.completedAt = nil
    }
}

// MARK: - Checklist Template
@Model
final class ChecklistTemplate {
    var id: UUID
    var title: String
    var createdAt: Date
    var lastResetDate: Date?
    
    @Relationship(deleteRule: .cascade, inverse: \ChecklistTask.template)
    var tasks: [ChecklistTask]
    
    init(title: String) {
        self.id = UUID()
        self.title = title
        self.createdAt = Date()
        self.tasks = []
    }
    
    /// Calculate completion percentage
    var completionPercentage: Double {
        guard !tasks.isEmpty else { return 0 }
        let completed = tasks.filter { $0.isCompleted }.count
        return Double(completed) / Double(tasks.count) * 100
    }
    
    /// Reset all tasks
    func resetAllTasks() {
        tasks.forEach { $0.reset() }
        lastResetDate = Date()
    }
}

// MARK: - Daily Tips
@Model
final class DailyTips {
    var id: UUID
    var date: Date
    var totalAmount: Double
    var isPaid: Bool
    var paidDate: Date?
    var notes: String?
    
    init(date: Date, totalAmount: Double) {
        self.id = UUID()
        self.date = Calendar.current.startOfDay(for: date)
        self.totalAmount = totalAmount
        self.isPaid = false
    }
    
    func markAsPaid() {
        self.isPaid = true
        self.paidDate = Date()
    }
}

// MARK: - Payroll Period
@Model
final class PayrollPeriod {
    var id: UUID
    var startDate: Date
    var endDate: Date
    var createdAt: Date
    var includeTips: Bool
    var isPaid: Bool
    var notes: String?
    
    init(startDate: Date, endDate: Date, includeTips: Bool = true) {
        self.id = UUID()
        self.startDate = Calendar.current.startOfDay(for: startDate)
        self.endDate = Calendar.current.startOfDay(for: endDate)
        self.createdAt = Date()
        self.includeTips = includeTips
        self.isPaid = false
    }
}

// MARK: - App Settings
@Model
final class AppSettings {
    var id: UUID
    var allowEmployeeInventoryEdit: Bool
    var createdAt: Date
    
    // Inventory notification settings
    var inventoryReminderEnabled: Bool
    var inventoryReminderType: String // "specific_day", "last_monday", "every_saturday", etc.
    var inventoryReminderDay: Int? // Day of month for "specific_day"
    
    init() {
        self.id = UUID()
        self.allowEmployeeInventoryEdit = false
        self.inventoryReminderEnabled = false
        self.inventoryReminderType = "specific_day"
        self.inventoryReminderDay = 1
        self.createdAt = Date()
    }
}
