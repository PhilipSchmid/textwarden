//
//  LiquidGlassModifier.swift
//  TextWarden
//
//  Liquid Glass-inspired styling for macOS 26+ appearance
//  Provides backward-compatible frosted glass effect for all macOS versions
//

import SwiftUI

// MARK: - Liquid Glass Style

/// Style options for the Liquid Glass effect
enum LiquidGlassStyle {
    case regular
    case prominent
    case subtle
}

/// Tint color options for the Liquid Glass effect
enum LiquidGlassTint {
    case blue // Grammar errors - primary
    case purple // Style suggestions
    case clear // Neutral/no tint

    var hue: Double {
        switch self {
        case .blue: 215.0 / 360.0
        case .purple: 280.0 / 360.0
        case .clear: 0
        }
    }
}

// MARK: - Liquid Glass View Modifier

/// Backward-compatible Liquid Glass effect modifier
/// Uses .ultraThinMaterial with subtle gradients and inner highlights
/// to approximate macOS 26 Liquid Glass appearance
struct LiquidGlassModifier: ViewModifier {
    let style: LiquidGlassStyle
    let tint: LiquidGlassTint
    let cornerRadius: CGFloat
    let opacity: Double
    @Environment(\.colorScheme) var colorScheme

    init(
        style: LiquidGlassStyle = .regular,
        tint: LiquidGlassTint = .clear,
        cornerRadius: CGFloat = 16,
        opacity: Double = 1.0
    ) {
        self.style = style
        self.tint = tint
        self.cornerRadius = cornerRadius
        self.opacity = opacity
    }

    /// Cached boolean for dark mode to ensure consistency within a single render pass
    private var isDark: Bool {
        colorScheme == .dark
    }

    func body(content: Content) -> some View {
        // Capture isDark at the start of body to ensure consistency
        let darkMode = isDark

        content
            .background(glassBackgroundView(isDark: darkMode))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(glassOverlayView(isDark: darkMode))
            .shadow(color: shadowColorForMode(isDark: darkMode), radius: shadowRadiusValue, x: 0, y: shadowYValue)
            // Animate color scheme changes smoothly
            .animation(.easeInOut(duration: 0.25), value: colorScheme)
    }

    // MARK: - Shadow values (not dependent on color scheme for consistency)

    private var shadowRadiusValue: CGFloat {
        switch style {
        case .regular: 16
        case .prominent: 20
        case .subtle: 10
        }
    }

    private var shadowYValue: CGFloat {
        switch style {
        case .regular: 6
        case .prominent: 8
        case .subtle: 4
        }
    }

    private func shadowColorForMode(isDark: Bool) -> Color {
        let hue = tint == .clear ? 0.0 : tint.hue
        if tint != .clear {
            return Color(hue: hue, saturation: 0.4, brightness: 0.3).opacity(isDark ? 0.4 : 0.2)
        }
        return Color.black.opacity(isDark ? 0.4 : 0.15)
    }

    // MARK: - Glass Background (parameterized for consistency)

    @ViewBuilder
    private func glassBackgroundView(isDark: Bool) -> some View {
        ZStack {
            // Base material layer - ultra thin for translucency
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(materialOpacityForMode(isDark: isDark))

            // Tinted gradient overlay
            if tint != .clear {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(tintGradientForMode(isDark: isDark))
                    .opacity(tintOpacityForMode(isDark: isDark))
            }

            // Inner highlight gradient (top edge glow - Liquid Glass signature)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(innerHighlightGradientForMode(isDark: isDark))
                .opacity(highlightOpacityValue)
        }
        .opacity(opacity)
    }

    // MARK: - Glass Overlay (Border & Edge Highlight)

    private func glassOverlayView(isDark: Bool) -> some View {
        ZStack {
            // Subtle border
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(borderGradientForMode(isDark: isDark), lineWidth: borderWidthValue)

            // Top edge highlight line (Liquid Glass signature element)
            topEdgeHighlightView(isDark: isDark)
        }
    }

    private func topEdgeHighlightView(isDark: Bool) -> some View {
        GeometryReader { geometry in
            Path { path in
                let rect = geometry.frame(in: .local)
                let inset: CGFloat = cornerRadius * 0.8
                path.move(to: CGPoint(x: inset, y: 1))
                path.addLine(to: CGPoint(x: rect.width - inset, y: 1))
            }
            .stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0),
                        Color.white.opacity(isDark ? 0.25 : 0.4),
                        Color.white.opacity(0),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                lineWidth: 1
            )
        }
    }

    // MARK: - Computed Properties (parameterized for consistency)

    private func materialOpacityForMode(isDark: Bool) -> Double {
        switch style {
        case .regular: isDark ? 0.85 : 0.9
        case .prominent: isDark ? 0.95 : 0.95
        case .subtle: isDark ? 0.7 : 0.8
        }
    }

    private func tintGradientForMode(isDark: Bool) -> LinearGradient {
        let hue = tint.hue
        let baseSaturation = isDark ? 0.25 : 0.15
        let baseBrightness = isDark ? 0.15 : 0.95

        return LinearGradient(
            colors: [
                Color(hue: hue, saturation: baseSaturation, brightness: baseBrightness),
                Color(hue: hue, saturation: baseSaturation * 1.2, brightness: baseBrightness * (isDark ? 0.85 : 0.98)),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func tintOpacityForMode(isDark: Bool) -> Double {
        switch style {
        case .regular: isDark ? 0.4 : 0.35
        case .prominent: isDark ? 0.5 : 0.45
        case .subtle: isDark ? 0.25 : 0.2
        }
    }

    private func innerHighlightGradientForMode(isDark: Bool) -> LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(isDark ? 0.08 : 0.15),
                Color.clear,
            ],
            startPoint: .top,
            endPoint: .center
        )
    }

    private var highlightOpacityValue: Double {
        switch style {
        case .regular: 1.0
        case .prominent: 1.2
        case .subtle: 0.7
        }
    }

    private func borderGradientForMode(isDark: Bool) -> LinearGradient {
        let hue = tint == .clear ? 0.0 : tint.hue
        let hasTint = tint != .clear

        if isDark {
            return LinearGradient(
                colors: [
                    hasTint
                        ? Color(hue: hue, saturation: 0.3, brightness: 0.4).opacity(0.5)
                        : Color.white.opacity(0.15),
                    hasTint
                        ? Color(hue: hue, saturation: 0.25, brightness: 0.3).opacity(0.3)
                        : Color.white.opacity(0.08),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                colors: [
                    hasTint
                        ? Color(hue: hue, saturation: 0.25, brightness: 0.75).opacity(0.4)
                        : Color.black.opacity(0.08),
                    hasTint
                        ? Color(hue: hue, saturation: 0.2, brightness: 0.85).opacity(0.25)
                        : Color.black.opacity(0.05),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var borderWidthValue: CGFloat {
        switch style {
        case .regular: 1.0
        case .prominent: 1.5
        case .subtle: 0.5
        }
    }
}

// MARK: - View Extension

extension View {
    /// Apply Liquid Glass effect to the view
    /// - Parameters:
    ///   - style: The intensity of the glass effect
    ///   - tint: Optional color tint for the glass
    ///   - cornerRadius: Corner radius for the glass shape
    ///   - opacity: Overall opacity of the glass effect
    func liquidGlass(
        style: LiquidGlassStyle = .regular,
        tint: LiquidGlassTint = .clear,
        cornerRadius: CGFloat = 16,
        opacity: Double = 1.0
    ) -> some View {
        modifier(LiquidGlassModifier(
            style: style,
            tint: tint,
            cornerRadius: cornerRadius,
            opacity: opacity
        ))
    }
}

// MARK: - Glass Button Style

/// Button style that applies Liquid Glass effect
struct LiquidGlassButtonStyle: ButtonStyle {
    let tint: LiquidGlassTint
    let isProminent: Bool
    @Environment(\.colorScheme) var colorScheme

    init(tint: LiquidGlassTint = .clear, isProminent: Bool = false) {
        self.tint = tint
        self.isProminent = isProminent
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(buttonBackground(isPressed: configuration.isPressed))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(borderColor, lineWidth: 1)
            )
            .shadow(
                color: shadowColor.opacity(configuration.isPressed ? 0.1 : 0.2),
                radius: configuration.isPressed ? 2 : 4,
                y: configuration.isPressed ? 1 : 2
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }

    @ViewBuilder
    private func buttonBackground(isPressed: Bool) -> some View {
        if isProminent {
            // Prominent buttons use solid tint color
            let hue = tint.hue
            LinearGradient(
                colors: [
                    Color(hue: hue, saturation: 0.7, brightness: colorScheme == .dark ? 0.6 : 0.55),
                    Color(hue: hue, saturation: 0.75, brightness: colorScheme == .dark ? 0.5 : 0.48),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .opacity(isPressed ? 0.9 : 1.0)
        } else {
            // Regular buttons use glass effect
            ZStack {
                if colorScheme == .dark {
                    Color(hue: tint.hue, saturation: 0.3, brightness: 0.2)
                        .opacity(isPressed ? 0.8 : 0.6)
                } else {
                    Color(hue: tint.hue, saturation: 0.2, brightness: 0.95)
                        .opacity(isPressed ? 0.9 : 0.7)
                }
            }
        }
    }

    private var borderColor: Color {
        let hue = tint.hue
        if colorScheme == .dark {
            return Color(hue: hue, saturation: 0.4, brightness: 0.4).opacity(0.5)
        } else {
            return Color(hue: hue, saturation: 0.3, brightness: 0.7).opacity(0.4)
        }
    }

    private var shadowColor: Color {
        Color(hue: tint.hue, saturation: 0.5, brightness: 0.3)
    }
}

extension ButtonStyle where Self == LiquidGlassButtonStyle {
    static func liquidGlass(tint: LiquidGlassTint = .clear, isProminent: Bool = false) -> LiquidGlassButtonStyle {
        LiquidGlassButtonStyle(tint: tint, isProminent: isProminent)
    }
}
