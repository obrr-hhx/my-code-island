import SwiftUI

/// Animated sine-wave dot grid background.
/// Creates a flowing particle effect reminiscent of retro visualizers.
struct DotWaveView: View {
    var gridSpacing: CGFloat = 22
    var dotColor: Color = RetroTheme.cyan
    var baseOpacity: Double = 0.02

    @State private var time: Double = 0
    @State private var timer: Timer?

    var body: some View {
        Canvas { context, size in
            let cols = Int(size.width / gridSpacing)
            let rows = Int(size.height / gridSpacing)

            for row in 0..<rows {
                for col in 0..<cols {
                    let x = CGFloat(col) * gridSpacing + gridSpacing / 2
                    let y = CGFloat(row) * gridSpacing + gridSpacing / 2

                    // Dual sine wave displacement
                    let wave1 = sin(Double(x) * 0.008 + time)
                    let wave2 = sin(Double(x) * 0.005 - time * 0.7)
                    let amplitude = (wave1 + wave2) / 2.0  // -1 to 1
                    let normalizedAmp = (amplitude + 1.0) / 2.0  // 0 to 1

                    let yOffset = amplitude * 3.0
                    let radius = 0.5 + normalizedAmp * 1.2
                    let opacity = baseOpacity + normalizedAmp * 0.06

                    let center = CGPoint(x: x, y: y + yOffset)
                    let rect = CGRect(
                        x: center.x - radius,
                        y: center.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(dotColor.opacity(opacity))
                    )
                }
            }
        }
        .onAppear {
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
                time += 0.05
            }
        }
        .onDisappear {
            timer?.invalidate()
        }
    }
}
