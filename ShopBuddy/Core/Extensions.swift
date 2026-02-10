//
//  Extensions.swift
//  ShopBuddy
//
//  Created by Dan on 1/29/26.
//

import Foundation
import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - App Commands
extension Notification.Name {
    static let shopBuddyInventoryAddCategoryCommand = Notification.Name("shopbuddy.inventory.addCategory")
    static let shopBuddyInventoryAddLocationCommand = Notification.Name("shopbuddy.inventory.addLocation")
    static let shopBuddyInventoryAddItemCommand = Notification.Name("shopbuddy.inventory.addItem")
    static let shopBuddyInventoryFocusSearchCommand = Notification.Name("shopbuddy.inventory.focusSearch")
    static let shopBuddyInventoryDeleteSelectionCommand = Notification.Name("shopbuddy.inventory.deleteSelection")
}

private enum Formatters {
    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    static let date: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()

    static let dateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter
    }()

    static let dayOfWeek: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter
    }()

    static let currency: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale.current
        return formatter
    }()
}

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
        Formatters.time.string(from: self)
    }
    
    /// Format as date string (e.g., "Jan 15, 2026")
    func dateString() -> String {
        Formatters.date.string(from: self)
    }
    
    /// Format as full date-time string
    func dateTimeString() -> String {
        Formatters.dateTime.string(from: self)
    }
    
    /// Format as short date (e.g., "1/15")
    func shortDateString() -> String {
        Formatters.shortDate.string(from: self)
    }
    
    /// Get day of week name
    func dayOfWeekString() -> String {
        Formatters.dayOfWeek.string(from: self)
    }
}

// MARK: - Double Extensions
extension Double {
    
    /// Format as currency string
    func currencyString() -> String {
        Formatters.currency.string(from: NSNumber(value: self)) ?? "$\(String(format: "%.2f", self))"
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
        count == 4 && allSatisfy(\.isNumber)
    }
    
    /// Capitalize first letter
    var capitalizedFirst: String {
        guard !isEmpty else { return self }
        return prefix(1).uppercased() + dropFirst()
    }
}

// MARK: - PIN Dot Indicator
struct PINDotIndicator: View {
    let enteredCount: Int
    var totalCount: Int = 4

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.grid_2) {
            ForEach(0..<totalCount, id: \.self) { index in
                ZStack {
                    Circle()
                        .fill(index < enteredCount ? DesignSystem.Colors.accent : DesignSystem.Colors.surface)
                        .frame(width: 24, height: 24)
                    Circle()
                        .stroke(DesignSystem.Colors.primary.opacity(0.3), lineWidth: 2)
                    if index < enteredCount {
                        Circle()
                            .fill(DesignSystem.Colors.primary.opacity(0.95))
                            .frame(width: 8, height: 8)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("PIN entry")
        .accessibilityValue("\(enteredCount) of \(totalCount) digits entered")
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

    /// Constrain content width for readable layouts on larger devices (iPad/landscape).
    func readableContent(maxWidth: CGFloat = 760) -> some View {
        frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    /// Apply the shared liquid backdrop.
    func liquidBackground() -> some View {
        background(DesignSystem.LiquidBackdrop().ignoresSafeArea())
    }

    /// Apply list chrome for the liquid style.
    func liquidListChrome() -> some View {
        #if os(macOS)
        return AnyView(
            scrollContentBackground(.hidden)
                .background(DesignSystem.LiquidBackdrop().ignoresSafeArea())
                .listRowSeparatorTint(DesignSystem.Colors.glassStroke.opacity(0.45))
                .contentMargins(.top, DesignSystem.Spacing.grid_1, for: .scrollContent)
                .contentMargins(.horizontal, DesignSystem.Spacing.grid_1, for: .scrollContent)
                .safeAreaPadding(.horizontal, DesignSystem.Spacing.grid_1)
                .safeAreaPadding(.vertical, DesignSystem.Spacing.grid_1)
                .environment(\.defaultMinListRowHeight, 42)
        )
        #else
        return AnyView(
            scrollContentBackground(.hidden)
                .background(DesignSystem.LiquidBackdrop().ignoresSafeArea())
                .listRowSeparatorTint(DesignSystem.Colors.glassStroke.opacity(0.45))
                .contentMargins(.top, DesignSystem.Spacing.grid_1, for: .scrollContent)
        )
        #endif
    }

    /// Apply form chrome for consistent modal/detail editing experiences.
    func liquidFormChrome() -> some View {
        #if os(macOS)
        return AnyView(
            scrollContentBackground(.hidden)
                .background(DesignSystem.LiquidBackdrop().ignoresSafeArea())
                .listRowBackground(DesignSystem.Colors.surfaceElevated.opacity(0.34))
                .listRowSeparatorTint(DesignSystem.Colors.glassStroke.opacity(0.45))
                .contentMargins(.top, DesignSystem.Spacing.grid_1, for: .scrollContent)
                .contentMargins(.horizontal, DesignSystem.Spacing.grid_1, for: .scrollContent)
                .safeAreaPadding(.horizontal, DesignSystem.Spacing.grid_2)
                .safeAreaPadding(.vertical, DesignSystem.Spacing.grid_1)
                .environment(\.defaultMinListRowHeight, 42)
        )
        #else
        return AnyView(
            scrollContentBackground(.hidden)
                .background(DesignSystem.LiquidBackdrop().ignoresSafeArea())
                .listRowBackground(DesignSystem.Colors.surfaceElevated.opacity(0.34))
                .listRowSeparatorTint(DesignSystem.Colors.glassStroke.opacity(0.45))
                .contentMargins(.top, DesignSystem.Spacing.grid_1, for: .scrollContent)
        )
        #endif
    }

    /// Standardized safe-area spacing for macOS pages.
    func macPagePadding(
        horizontal: CGFloat = DesignSystem.Spacing.grid_2,
        vertical: CGFloat = DesignSystem.Spacing.grid_1
    ) -> some View {
        #if os(macOS)
        return AnyView(
            safeAreaPadding(.horizontal, horizontal)
                .safeAreaPadding(.vertical, vertical)
        )
        #else
        return AnyView(self)
        #endif
    }

    /// Standardized card-like section wrapper for macOS.
    func macSectionCardPadding() -> some View {
        #if os(macOS)
        return AnyView(
            padding(DesignSystem.Spacing.grid_2)
                .glassCard()
        )
        #else
        return AnyView(self)
        #endif
    }
}

#if os(macOS)
/// Resizes a sheet to a percentage of its parent window so it adapts between
/// regular windowed mode and fullscreen mode.
struct MacAdaptiveSheetSizer: NSViewRepresentable {
    let widthRatio: CGFloat
    let heightRatio: CGFloat
    let minWidth: CGFloat
    let minHeight: CGFloat
    let maxWidth: CGFloat
    let maxHeight: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            context.coordinator.bind(view: view, config: self)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.bind(view: nsView, config: self)
        }
    }

    final class Coordinator {
        private weak var sheetWindow: NSWindow?
        private weak var parentWindow: NSWindow?
        private var resizeObserver: NSObjectProtocol?

        deinit {
            if let resizeObserver {
                NotificationCenter.default.removeObserver(resizeObserver)
            }
        }

        func bind(view: NSView, config: MacAdaptiveSheetSizer) {
            guard let sheet = view.window else { return }
            sheetWindow = sheet

            let currentParent = sheet.sheetParent
            if parentWindow !== currentParent {
                if let resizeObserver {
                    NotificationCenter.default.removeObserver(resizeObserver)
                    self.resizeObserver = nil
                }
                parentWindow = currentParent

                if let parent = currentParent {
                    resizeObserver = NotificationCenter.default.addObserver(
                        forName: NSWindow.didResizeNotification,
                        object: parent,
                        queue: .main
                    ) { [weak self] _ in
                        self?.apply(config: config)
                    }
                }
            }

            apply(config: config)
        }

        private func apply(config: MacAdaptiveSheetSizer) {
            guard let sheet = sheetWindow else { return }

            let referenceSize: CGSize
            if let parent = parentWindow {
                referenceSize = parent.contentLayoutRect.size
            } else if let screenSize = sheet.screen?.visibleFrame.size {
                referenceSize = screenSize
            } else {
                return
            }

            let targetWidth = min(max(referenceSize.width * config.widthRatio, config.minWidth), config.maxWidth)
            let targetHeight = min(max(referenceSize.height * config.heightRatio, config.minHeight), config.maxHeight)
            let targetSize = NSSize(width: targetWidth, height: targetHeight)

            sheet.minSize = NSSize(width: config.minWidth, height: config.minHeight)
            if abs(sheet.frame.width - targetSize.width) > 1 || abs(sheet.frame.height - targetSize.height) > 1 {
                sheet.setContentSize(targetSize)
            }
        }
    }
}
#endif

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

// MARK: - QR Renderer
final class QRCodeRenderer {
    static let shared = QRCodeRenderer()

    private let context = CIContext(options: [CIContextOption.useSoftwareRenderer: false])
    private let cache = NSCache<NSString, CachedCGImage>()

    private init() {
        cache.countLimit = 256
    }

    func makeImage(from payload: String, scale: CGFloat = 10) -> Image? {
        let cacheKey = "\(payload)|\(scale)" as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return Image(decorative: cached.image, scale: 1)
        }

        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }
        let transformed = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else {
            return nil
        }

        cache.setObject(CachedCGImage(cgImage), forKey: cacheKey)
        return Image(decorative: cgImage, scale: 1)
    }
}

private final class CachedCGImage {
    let image: CGImage

    init(_ image: CGImage) {
        self.image = image
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
