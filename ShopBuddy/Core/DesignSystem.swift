import SwiftUI

#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

/// Central design system for ShopBuddy
enum DesignSystem {
    
    // MARK: - Colors
    enum Colors {
        #if os(macOS)
        static var background: Color { Color(nsColor: .windowBackgroundColor) }
        static var surface: Color { Color(nsColor: .controlBackgroundColor) }
        static var surfaceElevated: Color { Color(nsColor: .underPageBackgroundColor) }
        static var primary: Color { Color.primary }
        static var secondary: Color { Color.secondary }
        static var tertiary: Color { Color.secondary.opacity(0.72) }
        static var accent: Color { Color.accentColor }
        static var success: Color { Color(red: 0.16, green: 0.66, blue: 0.33) }
        static var warning: Color { Color(red: 0.86, green: 0.49, blue: 0.11) }
        static var error: Color { Color(red: 0.78, green: 0.24, blue: 0.24) }
        static var glassStroke: Color { Color.primary.opacity(0.14) }
        #else
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
        #endif
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
    
    // MARK: - Haptic Types
    enum HapticType {
        case success
        case error
        case warning
        case light
        case medium
        case heavy
        case selection
    }
    
    // MARK: - Haptic System
    enum HapticFeedback {
        static func trigger(_ type: HapticType) {
            #if canImport(UIKit)
            switch type {
            case .success:
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            case .error:
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            case .warning:
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            case .light:
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            case .medium:
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            case .heavy:
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            case .selection:
                UISelectionFeedbackGenerator().selectionChanged()
            }
            #endif
        }
    }
    
    // MARK: - Components
    struct LiquidBackdrop: View {
        var body: some View {
            ZStack {
                LinearGradient(
                    colors: [
                        Colors.background.opacity(0.95),
                        Colors.surface.opacity(0.85)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(Colors.accent.opacity(0.16))
                    .frame(width: 360, height: 360)
                    .blur(radius: 100)
                    .offset(x: -150, y: -180)

                Circle()
                    .fill(Colors.success.opacity(0.1))
                    .frame(width: 320, height: 320)
                    .blur(radius: 90)
                    .offset(x: 170, y: 210)
            }
        }
    }

    struct GlassCard<Content: View>: View {
        let content: Content
        
        init(@ViewBuilder content: () -> Content) {
            self.content = content()
        }
        
        var body: some View {
            content
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                        .stroke(DesignSystem.Colors.glassStroke, lineWidth: 1)
                )
        }
    }
}

// MARK: - Button Styles
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
                if isPressed {
                    DesignSystem.HapticFeedback.trigger(.light)
                }
            }
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignSystem.Typography.callout)
            .foregroundColor(DesignSystem.Colors.primary)
            .padding(.horizontal, DesignSystem.Spacing.grid_2)
            .padding(.vertical, DesignSystem.Spacing.grid_1)
            .background(DesignSystem.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                    .stroke(DesignSystem.Colors.glassStroke, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    DesignSystem.HapticFeedback.trigger(.light)
                }
            }
    }
}

// MARK: - Empty State View
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?
    
    init(
        icon: String,
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }
    
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.grid_3) {
            Spacer()
            
            Image(systemName: icon)
                .font(.system(size: 60))
                .foregroundColor(DesignSystem.Colors.secondary)
            
            VStack(spacing: DesignSystem.Spacing.grid_1) {
                Text(title)
                    .font(DesignSystem.Typography.title3)
                    .foregroundColor(DesignSystem.Colors.primary)
                
                Text(message)
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.secondary)
                    .multilineTextAlignment(.center)
            }
            
            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    Text(actionTitle)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, DesignSystem.Spacing.grid_4)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(DesignSystem.Spacing.grid_4)
    }
}
