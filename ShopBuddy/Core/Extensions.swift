//
//  Extensions.swift
//  ShopBuddy
//
//  Created by Dan on 1/29/26.
//

import Foundation
import SwiftUI

// MARK: - Date Extensions
extension Date {
    
    /// Get start of day
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }
    
    /// Get end of day
    var endOfDay: Date {
        var components = DateComponents()
        components.day = 1
        components.second = -1
        return Calendar.current.date(byAdding: components, to: startOfDay) ?? self
    }
    
    /// Get start of week (Monday)
    var startOfWeek: Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: self)
        return calendar.date(from: components) ?? self
    }
    
    /// Get end of week (Sunday)
    var endOfWeek: Date {
        let calendar = Calendar.current
        return calendar.date(byAdding: .day, value: 6, to: startOfWeek)?.endOfDay ?? self
    }
    
    /// Check if date is today
    var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }
    
    /// Check if date is in current week
    var isThisWeek: Bool {
        Calendar.current.isDate(self, equalTo: Date(), toGranularity: .weekOfYear)
    }
    
    /// Format as time string (e.g., "2:30 PM")
    func timeString() -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }
    
    /// Format as date string (e.g., "Jan 15, 2026")
    func dateString() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: self)
    }
    
    /// Format as full date-time string
    func dateTimeString() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }
    
    /// Format as short date (e.g., "1/15")
    func shortDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter.string(from: self)
    }
    
    /// Get day of week name
    func dayOfWeekString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: self)
    }
}

// MARK: - Double Extensions
extension Double {
    
    /// Format as currency string
    func currencyString() -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale.current
        return formatter.string(from: NSNumber(value: self)) ?? "$\(String(format: "%.2f", self))"
    }
    
    /// Format as hours string (e.g., "8.5h")
    func hoursString() -> String {
        return String(format: "%.1fh", self)
    }
    
    /// Format as percentage string
    func percentageString() -> String {
        return String(format: "%.1f%%", self)
    }
}

// MARK: - String Extensions
extension String {
    
    /// Validate PIN format (4 digits)
    var isValidPIN: Bool {
        let pattern = "^[0-9]{4}$"
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: self.utf16.count)
        return regex?.firstMatch(in: self, range: range) != nil
    }
    
    /// Capitalize first letter
    var capitalizedFirst: String {
        guard !isEmpty else { return self }
        return prefix(1).uppercased() + dropFirst()
    }
}

// MARK: - View Extensions
extension View {
    
    /// Apply glass card style
    /// Note: This depends on the GlassCard struct defined in DesignSystem.swift
    func glassCard() -> some View {
        DesignSystem.GlassCard { self }
    }
    
    /// Conditional modifier
    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - Color Extensions
extension Color {
    
    /// Stock level color based on percentage
    static func stockColor(percentage: Double) -> Color {
        if percentage >= 0.5 {
            return DesignSystem.Colors.success
        } else if percentage >= 0.25 {
            return DesignSystem.Colors.warning
        } else {
            return DesignSystem.Colors.error
        }
    }
}

// MARK: - Date Range Helper
struct DateRange {
    let start: Date
    let end: Date
    
    init(start: Date, end: Date) {
        self.start = start.startOfDay
        self.end = end.endOfDay
    }
    
    /// Check if date is in range
    func contains(_ date: Date) -> Bool {
        return date >= start && date <= end
    }
    
    /// Get all days in range
    var days: [Date] {
        var dates: [Date] = []
        var currentDate = start
        
        while currentDate <= end {
            dates.append(currentDate)
            currentDate = Calendar.current.date(byAdding: .day, value: 1, to: currentDate) ?? end
        }
        
        return dates
    }
    
    /// Format range as string
    func rangeString() -> String {
        if Calendar.current.isDate(start, inSameDayAs: end) {
            return start.dateString()
        } else {
            return "\(start.shortDateString()) - \(end.shortDateString())"
        }
    }
}

// MARK: - Preset Date Ranges
extension DateRange {
    
    static var today: DateRange {
        let now = Date()
        return DateRange(start: now.startOfDay, end: now.endOfDay)
    }
    
    static var thisWeek: DateRange {
        let now = Date()
        return DateRange(start: now.startOfWeek, end: now.endOfWeek)
    }
    
    static var lastWeek: DateRange {
        let now = Date()
        let lastWeekDate = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: now) ?? now
        return DateRange(start: lastWeekDate.startOfWeek, end: lastWeekDate.endOfWeek)
    }
    
    static var thisMonth: DateRange {
        let now = Date()
        let calendar = Calendar.current
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let endOfMonth = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: startOfMonth) ?? now
        return DateRange(start: startOfMonth, end: endOfMonth.endOfDay)
    }
    
    static func custom(start: Date, end: Date) -> DateRange {
        return DateRange(start: start, end: end)
    }
}
