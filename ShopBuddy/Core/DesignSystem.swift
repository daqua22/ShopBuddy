import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// Central design system for ShopBuddy
enum DesignSystem {
    
    // MARK: - Colors
    enum Colors {
        static let background = Color.black
        static let surface = Color(white: 0.1)
        static let surfaceElevated = Color(white: 0.15)
        static let primary = Color.white
        static let secondary = Color.gray
        static let tertiary = Color(white: 0.4)
        static let accent = Color.blue
        static let success = Color.green
        static let warning = Color.orange
        static let error = Color.red
        static let glassStroke = Color.white.opacity(0.15)
    }
    
    // MARK: - Spacing
    enum Spacing {
        static let grid_1: CGFloat = 8
        static let grid_2: CGFloat = 16
        static let grid_3: CGFloat = 24
        static let grid_4: CGFloat = 32
    }
    
    // MARK: - Corner Radius
    enum CornerRadius {
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let small: CGFloat = 8
    }
    
    // MARK: - Typography
    enum Typography {
        static let largeTitle = Font.system(.largeTitle, design: .rounded).bold()
        static let title = Font.system(.title, design: .rounded).bold()
        static let title2 = Font.system(.title2, design: .rounded).weight(.semibold)
        static let title3 = Font.system(.title3, design: .rounded).weight(.semibold)
        static let headline = Font.system(.headline, design: .rounded).weight(.semibold)
        static let body = Font.system(.body, design: .rounded)
        static let callout = Font.system(.callout, design: .rounded)
        static let subheadline = Font.system(.subheadline, design: .rounded)
        static let footnote = Font.system(.footnote, design: .rounded)
        static let caption = Font.system(.caption, design: .rounded)
    }
    
    // MARK: - Haptic System
    enum HapticFeedback {
        static func success() {
            #if canImport(UIKit)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
        }
        
        static func error() {
            #if canImport(UIKit)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            #endif
        }
        
        static func selection() {
            #if canImport(UIKit)
            UISelectionFeedbackGenerator().selectionChanged()
            #endif
        }
    }
    
    // MARK: - Components
    struct GlassCard<Content: View>: View {
        let content: Content
        init(@ViewBuilder content: () -> Content) { self.content = content() }
        var body: some View {
            content
                .padding(DesignSystem.Spacing.grid_2)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                        .stroke(DesignSystem.Colors.glassStroke, lineWidth: 1)
                )
        }
    }
} // <-- NOW THE ENUM CLOSES HERE

// MARK: - Button Styles (Must be outside for easier usage)
struct PrimaryButtonStyle: ButtonStyle {
    var isDestructive: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignSystem.Typography.headline)
            .foregroundColor(.white)
            .padding(.horizontal, DesignSystem.Spacing.grid_3)
            .padding(.vertical, DesignSystem.Spacing.grid_2)
            .background(isDestructive ? DesignSystem.Colors.error : DesignSystem.Colors.accent)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed { DesignSystem.HapticFeedbackDesignSystem.HapticFeedback.trigger(.light) }
            }
    }
}
