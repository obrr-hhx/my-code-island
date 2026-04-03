import SwiftUI

/// Pixel art Clawd mascot with frame-based animation system
/// matching Claude Code's AnimatedClawd.tsx.
///
/// Animation system:
/// - 60ms per frame, sequence-driven
/// - Click triggers JUMP_WAVE or LOOK_AROUND (random)
/// - State-driven idle behavior based on app state pose
/// - Crouch effect: offset shifts Clawd down, feet clipped
struct ClawdView: View {
    var pixelSize: CGFloat = 4
    var pose: ClawdPose = .default_
    var animated: Bool = true

    static let bodyColor = Color(
        red: 215.0 / 255.0,
        green: 119.0 / 255.0,
        blue: 87.0 / 255.0
    )

    @State private var currentFrame: ClawdFrame = .idle
    @State private var sequenceFrames: [ClawdFrame] = []
    @State private var frameIndex: Int = -1
    @State private var frameTimer: Timer?
    @State private var idleTimer: Timer?

    private static let frameMS: TimeInterval = 0.06  // 60ms per frame

    var body: some View {
        Canvas { context, size in
            let grid = ClawdSprite.grid(for: currentFrame.pose)
            let rows = grid.count
            let cols = grid[0].count
            let totalW = CGFloat(cols) * pixelSize
            let totalH = CGFloat(rows) * pixelSize
            let offsetX = (size.width - totalW) / 2
            // Crouch: offset=1 pushes down by ~3 pixels (feet get clipped by container)
            let crouchShift = CGFloat(currentFrame.offset) * pixelSize * 3
            let offsetY = (size.height - totalH) / 2 + crouchShift

            for row in 0..<rows {
                for col in 0..<grid[row].count {
                    let cell = grid[row][col]
                    guard cell != .empty else { continue }
                    let y = offsetY + CGFloat(row) * pixelSize
                    // Clip: don't draw if below the container
                    guard y < size.height else { continue }

                    let rect = CGRect(
                        x: offsetX + CGFloat(col) * pixelSize,
                        y: y,
                        width: pixelSize,
                        height: pixelSize
                    )
                    let color: Color = cell == .body ? Self.bodyColor : .black
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
        .frame(
            width: CGFloat(ClawdSprite.cols) * pixelSize + pixelSize,
            height: CGFloat(ClawdSprite.rows) * pixelSize + pixelSize
        )
        .clipShape(Rectangle())  // Clip feet during crouch
        .contentShape(Rectangle())
        .onTapGesture { playClickAnimation() }
        .onAppear {
            currentFrame = .idle
            guard animated else { return }
            startIdleBehavior()
        }
        .onDisappear { stopAll() }
        .onChange(of: pose) { _, _ in
            // When external pose changes, restart idle behavior
            if frameIndex == -1 { startIdleBehavior() }
        }
    }

    // MARK: - Click Animations (from Claude Code)

    private func playClickAnimation() {
        guard animated, frameIndex == -1 else { return }
        // Randomly pick JUMP_WAVE or LOOK_AROUND
        sequenceFrames = Bool.random() ? ClawdAnimations.jumpWave : ClawdAnimations.lookAround
        frameIndex = 0
        advanceFrame()
    }

    private func advanceFrame() {
        frameTimer?.invalidate()

        guard frameIndex >= 0, frameIndex < sequenceFrames.count else {
            // Animation done → return to idle
            frameIndex = -1
            currentFrame = .idle
            startIdleBehavior()
            return
        }

        currentFrame = sequenceFrames[frameIndex]
        frameIndex += 1

        frameTimer = Timer.scheduledTimer(withTimeInterval: Self.frameMS, repeats: false) { _ in
            advanceFrame()
        }
    }

    // MARK: - State-driven Idle Behavior

    private func startIdleBehavior() {
        idleTimer?.invalidate()

        // Periodic subtle animation based on external pose
        let interval: TimeInterval = switch pose {
        case .alert: 0.8    // Urgent — bounce frequently
        case .thinking: 2.0 // Moderate — look around
        default: 4.0        // Relaxed — occasional glance
        }

        idleTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            guard frameIndex == -1 else { return }  // Don't interrupt click animations

            let sequence: [ClawdFrame] = switch pose {
            case .alert:
                // Urgent bounce: crouch → spring with arms up
                ClawdAnimations.jumpWave
            case .thinking:
                // Look around while thinking
                ClawdAnimations.lookAround
            default:
                // Occasional random glance
                Bool.random() ? ClawdAnimations.quickGlance : ClawdAnimations.blink
            }

            sequenceFrames = sequence
            frameIndex = 0
            advanceFrame()
        }
    }

    private func stopAll() {
        frameTimer?.invalidate()
        idleTimer?.invalidate()
    }
}

// MARK: - Animation Frame

struct ClawdFrame {
    let pose: ClawdPose
    let offset: Int  // 0 = normal, 1 = crouched (shifted down)

    static let idle = ClawdFrame(pose: .default_, offset: 0)
}

// MARK: - Poses

enum ClawdPose: Equatable, CaseIterable {
    case default_
    case armsUp
    case lookLeft
    case lookRight
    case thinking
    case alert
    case happy
}

// MARK: - Animation Sequences (from Claude Code AnimatedClawd.tsx)

enum ClawdAnimations {
    /// Hold a pose for N frames.
    static func hold(_ pose: ClawdPose, offset: Int = 0, frames: Int) -> [ClawdFrame] {
        Array(repeating: ClawdFrame(pose: pose, offset: offset), count: frames)
    }

    /// Click animation: crouch → spring up with arms raised. Twice.
    static let jumpWave: [ClawdFrame] =
        hold(.default_, offset: 1, frames: 2) +  // crouch
        hold(.armsUp, frames: 3) +                // spring!
        hold(.default_, frames: 1) +
        hold(.default_, offset: 1, frames: 2) +  // crouch again
        hold(.armsUp, frames: 3) +                // spring!
        hold(.default_, frames: 1)

    /// Click animation: glance right, then left, then back.
    static let lookAround: [ClawdFrame] =
        hold(.lookRight, frames: 5) +
        hold(.lookLeft, frames: 5) +
        hold(.default_, frames: 1)

    /// Quick idle glance to one side
    static let quickGlance: [ClawdFrame] =
        hold(Bool.random() ? .lookLeft : .lookRight, frames: 4) +
        hold(.default_, frames: 1)

    /// Subtle "blink" — brief crouch
    static let blink: [ClawdFrame] =
        hold(.default_, offset: 1, frames: 1) +
        hold(.default_, frames: 1)
}

// MARK: - Sprite Data

/// Pixel grid generated from Claude Code's Unicode block art.
/// Height-doubled to correct terminal char aspect ratio.
/// Head shifted left 1 sub-pixel to align with body.
enum ClawdSprite {
    static let cols = 18
    static let rows = 12

    enum Cell {
        case empty
        case body
        case eye
    }

    static func grid(for pose: ClawdPose) -> [[Cell]] {
        let o = Cell.empty
        let B = Cell.body
        let e = Cell.eye
        switch pose {
        case .default_:
            return [
                [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o,o],
                [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o,o],
                [o,o,o,B,B,e,B,B,B,B,B,B,e,B,B,o,o,o],
                [o,o,o,B,B,e,B,B,B,B,B,B,e,B,B,o,o,o],
                [o,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,o],
                [o,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,o],
                [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o,o],
                [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o,o],
                [o,o,o,o,B,o,B,o,o,o,o,B,o,B,o,o,o,o],
                [o,o,o,o,B,o,B,o,o,o,o,B,o,B,o,o,o,o],
                [o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o],
                [o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o],
            ]
        case .armsUp, .alert, .happy:
            return [
                [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o,o],
                [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o,o],
                [o,B,B,B,B,e,B,B,B,B,B,B,e,B,B,B,B,o],
                [o,B,B,B,B,e,B,B,B,B,B,B,e,B,B,B,B,o],
                [o,o,B,B,B,B,B,B,B,B,B,B,B,B,B,B,o,o],
                [o,o,B,B,B,B,B,B,B,B,B,B,B,B,B,B,o,o],
                [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o,o],
                [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o,o],
                [o,o,o,o,B,o,B,o,o,o,o,B,o,B,o,o,o,o],
                [o,o,o,o,B,o,B,o,o,o,o,B,o,B,o,o,o,o],
                [o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o],
                [o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o],
            ]
        case .lookLeft, .thinking:
            // Eyes shift left together: col 4 and col 11 (gap=7, same as default)
            return [
                [o,o,o,B,e,B,B,B,B,B,B,e,B,B,B,o,o,o],
                [o,o,o,B,e,B,B,B,B,B,B,e,B,B,B,o,o,o],
                [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o,o],
                [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o,o],
                [o,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,o],
                [o,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,o],
                [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o,o],
                [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o,o],
                [o,o,o,o,B,o,B,o,o,o,o,B,o,B,o,o,o,o],
                [o,o,o,o,B,o,B,o,o,o,o,B,o,B,o,o,o,o],
                [o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o],
                [o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o],
            ]
        case .lookRight:
            // Eyes shift right together: col 6 and col 13 (gap=7, same as default)
            return [
                [o,o,o,B,B,B,e,B,B,B,B,B,B,e,B,o,o,o],
                [o,o,o,B,B,B,e,B,B,B,B,B,B,e,B,o,o,o],
                [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o,o],
                [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o,o],
                [o,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,o],
                [o,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,o],
                [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o,o],
                [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o,o],
                [o,o,o,o,B,o,B,o,o,o,o,B,o,B,o,o,o,o],
                [o,o,o,o,B,o,B,o,o,o,o,B,o,B,o,o,o,o],
                [o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o],
                [o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o],
            ]
        }
    }
}
