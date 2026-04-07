import SwiftUI

/// Available color themes.
enum AppTheme: String, CaseIterable {
    case retro = "Retro"
    case cyberpunk = "Cyber"
    case solarized = "Solar"
    case dracula = "Dracula"
    case nord = "Nord"

    var colors: ThemeColors {
        switch self {
        case .retro:
            return ThemeColors(
                accent: 0x06B6D4, background: 0x0A0A0A, panelBg: 0x111111,
                cardBg: 0x1A1A1A, border: 0x333333,
                textPrimary: 0xE5E5E5, textSecondary: 0x888888, textMuted: 0x555555
            )
        case .cyberpunk:
            return ThemeColors(
                accent: 0xFF00FF, background: 0x0D0221, panelBg: 0x150535,
                cardBg: 0x1A0A3E, border: 0x6B21A8,
                textPrimary: 0x00FFFF, textSecondary: 0xFF6BFF, textMuted: 0x7C3AED
            )
        case .solarized:
            return ThemeColors(
                accent: 0x268BD2, background: 0x002B36, panelBg: 0x073642,
                cardBg: 0x073642, border: 0x586E75,
                textPrimary: 0xFDF6E3, textSecondary: 0x93A1A1, textMuted: 0x657B83
            )
        case .dracula:
            return ThemeColors(
                accent: 0xBD93F9, background: 0x282A36, panelBg: 0x21222C,
                cardBg: 0x44475A, border: 0x6272A4,
                textPrimary: 0xF8F8F2, textSecondary: 0xBFBFBF, textMuted: 0x6272A4
            )
        case .nord:
            return ThemeColors(
                accent: 0x88C0D0, background: 0x2E3440, panelBg: 0x3B4252,
                cardBg: 0x434C5E, border: 0x4C566A,
                textPrimary: 0xECEFF4, textSecondary: 0xD8DEE9, textMuted: 0x4C566A
            )
        }
    }
}

struct ThemeColors {
    let accent: UInt
    let background: UInt
    let panelBg: UInt
    let cardBg: UInt
    let border: UInt
    let textPrimary: UInt
    let textSecondary: UInt
    let textMuted: UInt
}

/// 8-bit retro theme colors and styling constants.
/// Colors adapt based on the active AppTheme.
enum RetroTheme {

    /// Current active theme. Change this to switch all colors.
    nonisolated(unsafe) static var activeTheme: AppTheme = .retro

    // MARK: - Agent Colors (fixed across themes)

    /// Claude Code accent color (burnt orange/coral)
    static let claudeOrange = Color(hex: 0xD97757)
    /// Codex green
    static let codexGreen = Color(hex: 0x22C55E)
    /// Gemini blue
    static let geminiBlue = Color(hex: 0x3B82F6)
    /// Cursor purple
    static let cursorPurple = Color(hex: 0xA855F7)
    /// OpenCode amber
    static let openCodeAmber = Color(hex: 0xF59E0B)

    // MARK: - Theme-adaptive UI Colors

    // These use nonisolated(unsafe) so they can be used in SwiftUI default params.
    // Safe because activeTheme is only mutated on MainActor and SwiftUI views run on MainActor.
    nonisolated(unsafe) static var cyan: Color { Color(hex: activeTheme.colors.accent) }
    nonisolated(unsafe) static var background: Color { Color(hex: activeTheme.colors.background) }
    nonisolated(unsafe) static var panelBg: Color { Color(hex: activeTheme.colors.panelBg) }
    nonisolated(unsafe) static var cardBg: Color { Color(hex: activeTheme.colors.cardBg) }
    nonisolated(unsafe) static var border: Color { Color(hex: activeTheme.colors.border) }
    nonisolated(unsafe) static var textPrimary: Color { Color(hex: activeTheme.colors.textPrimary) }
    nonisolated(unsafe) static var textSecondary: Color { Color(hex: activeTheme.colors.textSecondary) }
    nonisolated(unsafe) static var textMuted: Color { Color(hex: activeTheme.colors.textMuted) }

    // MARK: - Status Colors

    nonisolated(unsafe) static var statusIdle: Color { Color(hex: activeTheme.colors.textMuted) }
    nonisolated(unsafe) static var statusThinking: Color { cyan }
    nonisolated(unsafe) static var statusToolUse: Color { codexGreen }
    nonisolated(unsafe) static var statusWaiting: Color { claudeOrange }
    static let statusStopped = Color(hex: 0xEF4444)

    // MARK: - Pixel Font

    /// Monospace font that approximates pixel/8-bit aesthetic.
    /// Uses Menlo as it's available on all Macs and has a good pixel feel at small sizes.
    static func pixelFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    // MARK: - Animation Constants

    /// Character scatter refresh interval
    static let scatterInterval: TimeInterval = 0.15
    /// Breathing pulse period
    static let breathingPeriod: TimeInterval = 2.0
    /// Glitch frame duration
    static let glitchFrameDuration: TimeInterval = 0.03
    /// Glitch random frames before reveal
    static let glitchFrameCount = 4

    // MARK: - Scatter Characters

    static let scatterChars: [Character] = ["0", "1", "+", "-", "*", ":", ".", "█", "▓", "░"]
}

// MARK: - Color Hex Extension

extension Color {
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: opacity
        )
    }
}

// MARK: - View Modifiers

/// Pixel-perfect border style mimicking retro UI.
struct PixelBorder: ViewModifier {
    var color: Color = RetroTheme.border
    var cornerRadius: CGFloat = 4

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(color, lineWidth: 1)
            )
    }
}

/// Subtle scanline overlay for CRT effect.
struct ScanlineOverlay: ViewModifier {
    var opacity: Double = 0.03

    func body(content: Content) -> some View {
        content.overlay(
            Canvas { context, size in
                for y in stride(from: 0, to: size.height, by: 2) {
                    let rect = CGRect(x: 0, y: y, width: size.width, height: 1)
                    context.fill(Path(rect), with: .color(.black.opacity(opacity)))
                }
            }
            .allowsHitTesting(false)
        )
    }
}

/// Glow effect behind text or icons.
struct PixelGlow: ViewModifier {
    var color: Color
    var radius: CGFloat = 6

    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(0.6), radius: radius)
            .shadow(color: color.opacity(0.3), radius: radius * 2)
    }
}

extension View {
    func pixelBorder(color: Color = RetroTheme.border, cornerRadius: CGFloat = 4) -> some View {
        modifier(PixelBorder(color: color, cornerRadius: cornerRadius))
    }

    func scanlines(opacity: Double = 0.03) -> some View {
        modifier(ScanlineOverlay(opacity: opacity))
    }

    func pixelGlow(_ color: Color, radius: CGFloat = 6) -> some View {
        modifier(PixelGlow(color: color, radius: radius))
    }
}
