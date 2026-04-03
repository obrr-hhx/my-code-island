import SwiftUI

/// 8-bit retro theme colors and styling constants.
enum RetroTheme {

    // MARK: - Agent Colors

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

    // MARK: - UI Colors

    /// Primary cyan highlight
    static let cyan = Color(hex: 0x06B6D4)
    /// Dark background
    static let background = Color(hex: 0x0A0A0A)
    /// Panel background (slightly lighter)
    static let panelBg = Color(hex: 0x111111)
    /// Card background
    static let cardBg = Color(hex: 0x1A1A1A)
    /// Subtle border
    static let border = Color(hex: 0x333333)
    /// Primary text
    static let textPrimary = Color(hex: 0xE5E5E5)
    /// Secondary text
    static let textSecondary = Color(hex: 0x888888)
    /// Muted text
    static let textMuted = Color(hex: 0x555555)

    // MARK: - Status Colors

    static let statusIdle = Color(hex: 0x555555)
    static let statusThinking = cyan
    static let statusToolUse = codexGreen
    static let statusWaiting = claudeOrange
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
