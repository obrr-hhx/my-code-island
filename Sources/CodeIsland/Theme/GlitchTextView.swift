import SwiftUI

/// Text that appears character-by-character with a randomized "glitch" effect.
/// Each character shows several random characters before settling on the final one.
struct GlitchTextView: View {
    let text: String
    var font: Font = RetroTheme.pixelFont(size: 12, weight: .bold)
    var color: Color = RetroTheme.textPrimary
    var glitchColor: Color = RetroTheme.cyan
    var speed: TimeInterval = 0.03

    @State private var displayedChars: [GlitchChar] = []
    @State private var revealIndex = 0
    @State private var timer: Timer?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(displayedChars.enumerated()), id: \.offset) { idx, gc in
                Text(String(gc.displayed))
                    .font(font)
                    .foregroundStyle(gc.isRevealed ? color : glitchColor.opacity(0.7))
            }
        }
        .onAppear { startGlitch() }
        .onDisappear { timer?.invalidate() }
        .onChange(of: text) { _, _ in startGlitch() }
    }

    private func startGlitch() {
        timer?.invalidate()
        let chars = Array(text)
        displayedChars = chars.map { GlitchChar(target: $0, displayed: " ", isRevealed: false) }
        revealIndex = 0

        var frameCount = 0
        timer = Timer.scheduledTimer(withTimeInterval: speed, repeats: true) { t in
            frameCount += 1

            // Update not-yet-revealed characters with random glitch
            var updated = displayedChars
            for i in revealIndex..<updated.count {
                updated[i].displayed = RetroTheme.scatterChars.randomElement() ?? "?"
            }

            // Reveal one character every N frames
            if frameCount % (RetroTheme.glitchFrameCount + 1) == 0 && revealIndex < chars.count {
                updated[revealIndex].displayed = chars[revealIndex]
                updated[revealIndex].isRevealed = true
                revealIndex += 1
            }

            displayedChars = updated

            // Done
            if revealIndex >= chars.count {
                t.invalidate()
            }
        }
    }
}

private struct GlitchChar {
    let target: Character
    var displayed: Character
    var isRevealed: Bool
}
