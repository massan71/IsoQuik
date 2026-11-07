import AppKit
import SwiftUI

/// Shared palette and visual components for IsoQuik.
enum Theme {
    // MARK: - Colors

    static let accent = Color(red: 0.15, green: 0.55, blue: 1.00)
    static let accentDeep = Color(red: 0.04, green: 0.23, blue: 0.66)
    static let accentSoft = Color(red: 0.42, green: 0.80, blue: 1.00)
    static let bolt = Color(red: 1.00, green: 0.58, blue: 0.12)
    static let success = Color(red: 0.18, green: 0.80, blue: 0.50)
    static let danger = Color(red: 1.00, green: 0.38, blue: 0.34)
    static let warning = Color(red: 1.00, green: 0.67, blue: 0.20)

    static let textPrimary = dynamic(
        light: NSColor(calibratedRed: 0.07, green: 0.10, blue: 0.18, alpha: 1),
        dark: NSColor(calibratedWhite: 0.97, alpha: 1)
    )
    static let textSecondary = dynamic(
        light: NSColor(calibratedRed: 0.32, green: 0.37, blue: 0.47, alpha: 1),
        dark: NSColor(calibratedWhite: 0.70, alpha: 1)
    )

    static let cardFill = dynamic(
        light: NSColor.white.withAlphaComponent(0.66),
        dark: NSColor.white.withAlphaComponent(0.055)
    )
    static let cardBorder = dynamic(
        light: NSColor.black.withAlphaComponent(0.08),
        dark: NSColor.white.withAlphaComponent(0.10)
    )
    static let fieldFill = dynamic(
        light: NSColor.white.withAlphaComponent(0.50),
        dark: NSColor.white.withAlphaComponent(0.045)
    )
    static let shadow = dynamic(
        light: NSColor.black.withAlphaComponent(0.10),
        dark: NSColor.black.withAlphaComponent(0.42)
    )

    static let bgTop = dynamic(
        light: NSColor(calibratedRed: 0.96, green: 0.98, blue: 1.00, alpha: 1),
        dark: NSColor(calibratedRed: 0.035, green: 0.06, blue: 0.12, alpha: 1)
    )
    static let bgBottom = dynamic(
        light: NSColor(calibratedRed: 0.86, green: 0.91, blue: 0.99, alpha: 1),
        dark: NSColor(calibratedRed: 0.018, green: 0.032, blue: 0.075, alpha: 1)
    )
    static let glowBlue = dynamic(
        light: NSColor(calibratedRed: 0.20, green: 0.55, blue: 1.00, alpha: 0.16),
        dark: NSColor(calibratedRed: 0.16, green: 0.50, blue: 1.00, alpha: 0.26)
    )
    static let glowOrange = dynamic(
        light: NSColor(calibratedRed: 1.00, green: 0.60, blue: 0.15, alpha: 0.12),
        dark: NSColor(calibratedRed: 1.00, green: 0.55, blue: 0.10, alpha: 0.18)
    )

    // MARK: - Gradients

    static let accentGradient = LinearGradient(
        colors: [accentSoft, accent, accentDeep],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let titleGradient = LinearGradient(
        colors: [textPrimary, accent],
        startPoint: .leading,
        endPoint: .trailing
    )

    // MARK: - Helper

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark ? dark : light
        })
    }
}

// MARK: - Background

struct ThemeBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.bgTop, Theme.bgBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [Theme.glowBlue, .clear],
                center: .bottomLeading,
                startRadius: 10,
                endRadius: 780
            )
            RadialGradient(
                colors: [Theme.glowOrange, .clear],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 560
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: - Card

private struct CardModifier: ViewModifier {
    let radius: CGFloat
    let padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Theme.cardFill)
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.cardBorder, lineWidth: 1)
            }
            .shadow(color: Theme.shadow, radius: 18, x: 0, y: 10)
    }
}

extension View {
    func themeCard(radius: CGFloat = 18, padding: CGFloat = 16) -> some View {
        modifier(CardModifier(radius: radius, padding: padding))
    }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 11)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.accentGradient)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.white.opacity(0.22), lineWidth: 1)
            }
            .shadow(
                color: Theme.accent.opacity(configuration.isPressed ? 0.15 : 0.38),
                radius: configuration.isPressed ? 6 : 16,
                x: 0,
                y: configuration.isPressed ? 2 : 7
            )
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(isEnabled ? 1 : 0.42)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

struct QuietButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.fieldFill)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.cardBorder, lineWidth: 1)
            }
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

// MARK: - Labels

struct SectionHeader: View {
    let icon: String
    let title: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.system(size: 11, weight: .bold))
            .tracking(0.9)
            .textCase(.uppercase)
            .foregroundStyle(Theme.textSecondary)
    }
}

struct InfoPill: View {
    let icon: String
    let text: String
    var tint: Color = Theme.accent

    var body: some View {
        Label(text, systemImage: icon)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(tint.opacity(0.13)))
            .overlay(Capsule().strokeBorder(tint.opacity(0.28), lineWidth: 1))
            .foregroundStyle(tint)
            .lineLimit(1)
    }
}
