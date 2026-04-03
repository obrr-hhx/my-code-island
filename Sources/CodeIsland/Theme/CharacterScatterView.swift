import SwiftUI

/// Animated background of randomly flickering ASCII characters.
/// Creates the signature 8-bit "breathing" scatter effect.
struct CharacterScatterView: View {
    var cellSize: CGFloat = 12
    var baseOpacity: Double = 0.06
    var accentColor: Color = RetroTheme.cyan

    @State private var grid: [[ScatterCell]] = []
    @State private var timer: Timer?
    @State private var cols = 0
    @State private var rows = 0

    var body: some View {
        Canvas { context, size in
            let w = Int(size.width / cellSize)
            let h = Int(size.height / cellSize)

            for row in 0..<min(h, grid.count) {
                for col in 0..<min(w, grid[row].count) {
                    let cell = grid[row][col]
                    let x = CGFloat(col) * cellSize
                    let y = CGFloat(row) * cellSize

                    // Radial fade from bottom-right corner
                    let maxDist = sqrt(size.width * size.width + size.height * size.height) * 0.6
                    let dx = size.width - x
                    let dy = size.height - y
                    let dist = sqrt(dx * dx + dy * dy)
                    let radialFade = max(0, 1.0 - dist / maxDist)

                    let alpha = baseOpacity + cell.brightness * 0.12 + radialFade * 0.08

                    // Blend toward accent color near corner
                    let color = radialFade > 0.3
                        ? accentColor.opacity(alpha)
                        : RetroTheme.textMuted.opacity(alpha)

                    let text = Text(String(cell.char))
                        .font(.system(size: cellSize * 0.75, design: .monospaced))
                        .foregroundStyle(color)

                    context.draw(
                        context.resolve(text),
                        at: CGPoint(x: x + cellSize / 2, y: y + cellSize / 2)
                    )
                }
            }
        }
        .onAppear { startAnimation() }
        .onDisappear { timer?.invalidate() }
    }

    private func startAnimation() {
        // Initialize grid
        cols = 40
        rows = 35
        grid = (0..<rows).map { _ in
            (0..<cols).map { _ in ScatterCell.random() }
        }

        // Breathing: shuffle ~5% of cells periodically
        timer = Timer.scheduledTimer(withTimeInterval: RetroTheme.scatterInterval, repeats: true) { _ in
            var newGrid = grid
            let shuffleCount = max(1, (cols * rows) / 20)
            for _ in 0..<shuffleCount {
                let r = Int.random(in: 0..<rows)
                let c = Int.random(in: 0..<cols)
                newGrid[r][c] = ScatterCell.random()
            }
            grid = newGrid
        }
    }
}

private struct ScatterCell {
    var char: Character
    var brightness: Double

    static func random() -> ScatterCell {
        ScatterCell(
            char: RetroTheme.scatterChars.randomElement() ?? ".",
            brightness: Double.random(in: 0...1)
        )
    }
}
