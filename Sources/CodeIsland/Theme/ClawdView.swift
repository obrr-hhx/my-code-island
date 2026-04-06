import SwiftUI

/// Pixel art Clawd mascot with frame-based animation system
/// matching Claude Code's AnimatedClawd.tsx, extended with
/// clawd-on-desk-inspired behaviors: sleep, error, celebration,
/// sweeping, carrying, juggling, conducting, and particle effects.
///
/// Animation system:
/// - 60ms per frame, sequence-driven
/// - Click triggers JUMP_WAVE or LOOK_AROUND (random)
/// - Double-click triggers POKE, 4+ clicks triggers FLAIL
/// - Behavior-driven idle loops based on app state
/// - Particle overlay for sparkles, Zzz, smoke, stars
struct ClawdView: View {
    var pixelSize: CGFloat = 4
    var pose: ClawdPose = .default_
    var behavior: ClawdBehavior = .idle
    var animated: Bool = true
    /// When true, enables notch-interaction idle animations (peek, hang, hide).
    /// Should only be set in collapsed notch view where clipping creates the effect.
    var notchMode: Bool = false

    static let bodyColor = Color(
        red: 215.0 / 255.0,
        green: 119.0 / 255.0,
        blue: 87.0 / 255.0
    )

    // Pre-computed particle colors to avoid per-frame allocation
    private static let zzzColor = Color(hex: 0x6688AA)
    private static let sparkleYellow = Color.yellow
    private static let sparkleWhite = Color.white

    @State private var currentFrame: ClawdFrame = .idle
    @State private var sequenceFrames: [ClawdFrame] = []
    @State private var frameIndex: Int = -1
    @State private var frameTimer: Timer?
    @State private var idleTimer: Timer?
    @State private var particles: [Particle] = []
    @State private var particleFrameCount: Int = 0
    @State private var clickCount: Int = 0
    @State private var clickResetTimer: Timer?
    @State private var lastBehavior: ClawdBehavior = .idle

    private static let frameMS: TimeInterval = 0.08  // 80ms per frame (~12fps)
    // Particle updates at lower frequency to reduce Canvas redraws
    private static let particleFrameMS: TimeInterval = 0.25  // 250ms per particle tick (~4fps)

    private var viewSize: CGSize {
        CGSize(
            width: CGFloat(ClawdSprite.cols) * pixelSize + pixelSize,
            height: CGFloat(ClawdSprite.rows) * pixelSize + pixelSize
        )
    }

    var body: some View {
        ZStack {
            // Sprite layer — only redraws when currentFrame changes
            ClawdSpriteCanvas(frame: currentFrame, pixelSize: pixelSize)

            // Particle overlay — only redraws when particles change
            if !particles.isEmpty {
                ClawdParticleCanvas(
                    particles: particles,
                    particleFrameCount: particleFrameCount,
                    pixelSize: pixelSize
                )
                .allowsHitTesting(false)
            }
        }
        .frame(width: viewSize.width, height: viewSize.height)
        .clipShape(Rectangle())
        .contentShape(Rectangle())
        .onTapGesture { handleClick() }
        .onAppear {
            currentFrame = .idle
            guard animated else { return }
            startIdleBehavior()
        }
        .onDisappear { stopAll() }
        .onChange(of: pose) { _, _ in
            if frameIndex == -1 { startIdleBehavior() }
        }
        .onChange(of: behavior) { oldVal, newVal in
            onBehaviorChanged(from: oldVal, to: newVal)
        }
    }

    // MARK: - Behavior Change Handler

    private func onBehaviorChanged(from old: ClawdBehavior, to new: ClawdBehavior) {
        guard animated else { return }

        switch new {
        case .sleeping:
            playSequence(ClawdAnimations.sleepTransition, thenLoop: .sleeping)
        case .error:
            playSequence(ClawdAnimations.errorShake)
            spawnParticleBurst(.smoke, count: 6)
        case .celebrating:
            playSequence(ClawdAnimations.celebration)
            spawnParticleBurst(.sparkle, count: 10)
        case .sweeping:
            playSequence(ClawdAnimations.sweep)
        case .carrying:
            playSequence(ClawdAnimations.carry)
        case .juggling:
            playSequence(ClawdAnimations.juggle, looping: true)
            spawnJugglingStars()
        case .conducting:
            playSequence(ClawdAnimations.conduct, looping: true)
        case .idle:
            if old == .sleeping {
                playSequence(ClawdAnimations.wakeUp)
            } else {
                frameIndex = -1
                currentFrame = .idle
                startIdleBehavior()
            }
        default:
            // thinking, toolUse — handled by idle behavior
            if frameIndex == -1 { startIdleBehavior() }
        }
    }

    // MARK: - Click Detection (debounced multi-click)

    private func handleClick() {
        guard animated, frameIndex == -1 || clickCount > 0 else { return }
        clickCount += 1
        clickResetTimer?.invalidate()
        clickResetTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { _ in
            Task { @MainActor in
                let count = clickCount
                clickCount = 0
                if count >= 4 {
                    playSequence(ClawdAnimations.flail)
                    spawnParticleBurst(.sparkle, count: 8)
                } else if count >= 2 {
                    playSequence(ClawdAnimations.poke)
                    ChiptuneEngine.shared.playPoke()
                } else {
                    playClickAnimation()
                }
            }
        }
    }

    private func playClickAnimation() {
        guard animated, frameIndex == -1 else { return }
        sequenceFrames = Bool.random() ? ClawdAnimations.jumpWave : ClawdAnimations.lookAround
        frameIndex = 0
        advanceFrame()
    }

    // MARK: - Sequence Playback

    @State private var isLooping: Bool = false
    @State private var loopHoldPose: ClawdPose?

    private func playSequence(_ sequence: [ClawdFrame], looping: Bool = false, thenLoop holdPose: ClawdPose? = nil) {
        frameTimer?.invalidate()
        idleTimer?.invalidate()
        isLooping = looping
        loopHoldPose = holdPose
        sequenceFrames = sequence
        frameIndex = 0
        advanceFrame()
    }

    private func advanceFrame() {
        frameTimer?.invalidate()

        guard frameIndex >= 0, frameIndex < sequenceFrames.count else {
            if isLooping {
                // Restart the loop
                frameIndex = 0
                advanceFrame()
                return
            }
            if let holdPose = loopHoldPose {
                // Hold this pose indefinitely (sleeping)
                frameIndex = -1
                currentFrame = ClawdFrame(pose: holdPose, offset: 0)
                startParticleLoop(for: holdPose)
                return
            }
            // Animation done → return to idle
            frameIndex = -1
            isLooping = false
            loopHoldPose = nil
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

    @State private var idleCycleCount: Int = 0

    private static let notchAnimations: [[ClawdFrame]] = [
        ClawdAnimations.notchPeek,
        ClawdAnimations.notchHang,
        ClawdAnimations.notchPeekUp,
        ClawdAnimations.notchShyHide,
    ]

    private func startIdleBehavior() {
        idleTimer?.invalidate()
        idleCycleCount = 0

        let interval: TimeInterval = switch pose {
        case .alert: 1.5
        case .thinking: 3.0
        default: 6.0
        }

        idleTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            guard frameIndex == -1 else { return }

            idleCycleCount += 1

            // In notch mode + idle: every ~3rd cycle, play a notch interaction
            if notchMode && pose == .default_ && idleCycleCount % 3 == 0 {
                let notchAnim = Self.notchAnimations[idleCycleCount / 3 % Self.notchAnimations.count]
                sequenceFrames = notchAnim
                frameIndex = 0
                advanceFrame()
                return
            }

            let sequence: [ClawdFrame] = switch pose {
            case .alert:
                ClawdAnimations.jumpWave
            case .thinking:
                ClawdAnimations.lookAround
            default:
                Bool.random() ? ClawdAnimations.quickGlance : ClawdAnimations.blink
            }

            sequenceFrames = sequence
            frameIndex = 0
            advanceFrame()
        }
    }

    // MARK: - Particle System

    @State private var particleTimer: Timer?

    /// Update particles in-place to minimize array allocations.
    private func updateParticles() {
        particleFrameCount += 1

        // Update positions in-place, remove dead particles
        var i = 0
        while i < particles.count {
            particles[i].x += particles[i].vx
            particles[i].y += particles[i].vy
            particles[i].life -= 1
            if particles[i].life <= 0 {
                particles.remove(at: i)
            } else {
                i += 1
            }
        }

        // Spawn Zzz periodically while sleeping (~every 5s at 250ms tick)
        if behavior == .sleeping && particleFrameCount % 20 == 0 {
            spawnParticle(.zzz, x: pixelSize * 14, y: pixelSize * 1,
                          vx: CGFloat.random(in: 0.3...0.6),
                          vy: CGFloat.random(in: -0.8...(-0.4)),
                          life: 25)
        }

        // Stop particle timer when all particles are gone and no spawning needed
        if particles.isEmpty && behavior != .sleeping {
            particleTimer?.invalidate()
            particleTimer = nil
        }
    }

    /// Ensure particle update timer is running.
    private func ensureParticleTimer() {
        guard particleTimer == nil else { return }
        particleTimer = Timer.scheduledTimer(withTimeInterval: Self.particleFrameMS, repeats: true) { _ in
            updateParticles()
        }
    }

    private func spawnParticleBurst(_ kind: ParticleKind, count: Int) {
        let centerX = CGFloat(ClawdSprite.cols) * pixelSize / 2
        let centerY = CGFloat(ClawdSprite.rows) * pixelSize / 2
        for _ in 0..<count {
            spawnParticle(
                kind,
                x: centerX + CGFloat.random(in: -pixelSize * 4...pixelSize * 4),
                y: centerY + CGFloat.random(in: -pixelSize * 3...pixelSize * 3),
                vx: CGFloat.random(in: -0.6...0.6),
                vy: CGFloat.random(in: -0.8...(-0.1)),
                life: Int.random(in: 12...25)
            )
        }
        ensureParticleTimer()
    }

    private func spawnJugglingStars() {
        let topY = pixelSize * 0.5
        for i in 0..<3 {
            let x = pixelSize * CGFloat(4 + i * 5)
            spawnParticle(.star, x: x, y: topY,
                          vx: CGFloat.random(in: -0.3...0.3),
                          vy: CGFloat.random(in: -0.5...0.5),
                          life: 120)
        }
        ensureParticleTimer()
    }

    private func startParticleLoop(for pose: ClawdPose) {
        ensureParticleTimer()
    }

    private func spawnParticle(_ kind: ParticleKind, x: CGFloat, y: CGFloat,
                               vx: CGFloat, vy: CGFloat, life: Int) {
        guard particles.count < 15 else { return }
        particles.append(Particle(x: x, y: y, vx: vx, vy: vy, life: life, maxLife: life, kind: kind))
    }

    private func stopAll() {
        frameTimer?.invalidate()
        idleTimer?.invalidate()
        clickResetTimer?.invalidate()
        particleTimer?.invalidate()
        particleTimer = nil
        particles.removeAll()
    }
}

// MARK: - Sprite Canvas (isolated redraws)

/// Separate view so it only redraws when the frame actually changes.
private struct ClawdSpriteCanvas: View, Equatable {
    let frame: ClawdFrame
    let pixelSize: CGFloat

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.frame == rhs.frame && lhs.pixelSize == rhs.pixelSize
    }

    var body: some View {
        Canvas { context, size in
            let grid = ClawdSprite.grid(for: frame.pose)
            let rows = grid.count
            let cols = grid[0].count
            let totalW = CGFloat(cols) * pixelSize
            let totalH = CGFloat(rows) * pixelSize
            let offsetX = (size.width - totalW) / 2 + frame.xShift
            let crouchShift = CGFloat(frame.offset) * pixelSize * 3
            let offsetY = (size.height - totalH) / 2 + crouchShift + frame.yShift

            for row in 0..<rows {
                for col in 0..<grid[row].count {
                    let cell = grid[row][col]
                    guard cell != .empty else { continue }
                    let y = offsetY + CGFloat(row) * pixelSize
                    guard y < size.height else { continue }

                    let rect = CGRect(
                        x: offsetX + CGFloat(col) * pixelSize,
                        y: y,
                        width: pixelSize,
                        height: pixelSize
                    )
                    let color: Color = cell == .body ? ClawdView.bodyColor : .black
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
    }
}

// MARK: - Particle Canvas (isolated redraws)

/// Separate view so particle updates don't force sprite redraw.
private struct ClawdParticleCanvas: View {
    let particles: [Particle]
    let particleFrameCount: Int
    let pixelSize: CGFloat

    // Pre-resolved shading to avoid creating Color objects per-draw
    private static let zzzShading: GraphicsContext.Shading = .color(Color(hex: 0x6688AA))
    private static let smokeShading: GraphicsContext.Shading = .color(.gray)

    var body: some View {
        Canvas { context, size in
            let px = pixelSize
            for particle in particles {
                let alpha = Double(particle.life) / Double(particle.maxLife)

                switch particle.kind {
                case .sparkle:
                    let isLarge = particleFrameCount % 2 == 0
                    let s = isLarge ? px * 2 : px
                    let color: Color = isLarge ? .yellow : .white
                    let rect = CGRect(x: particle.x, y: particle.y, width: s, height: s)
                    context.opacity = alpha
                    context.fill(Path(rect), with: .color(color))
                    context.opacity = 1

                case .zzz:
                    let z: [(CGFloat, CGFloat)] = [(0,0),(1,0),(2,0), (1,1), (0,2),(1,2),(2,2)]
                    context.opacity = alpha * 0.8
                    for (dx, dy) in z {
                        let rect = CGRect(
                            x: particle.x + dx * px,
                            y: particle.y + dy * px,
                            width: px,
                            height: px
                        )
                        context.fill(Path(rect), with: Self.zzzShading)
                    }
                    context.opacity = 1

                case .smoke:
                    let rect = CGRect(x: particle.x, y: particle.y, width: px * 2, height: px * 2)
                    context.opacity = alpha * 0.5
                    context.fill(Path(rect), with: Self.smokeShading)
                    context.opacity = 1

                case .star:
                    if particleFrameCount % 2 == 0 {
                        let rect = CGRect(x: particle.x, y: particle.y, width: px, height: px)
                        context.opacity = alpha
                        context.fill(Path(rect), with: .color(.white))
                        context.opacity = 1
                    }
                }
            }
        }
    }
}

// MARK: - Particle Types

struct Particle {
    var x: CGFloat
    var y: CGFloat
    var vx: CGFloat
    var vy: CGFloat
    var life: Int
    var maxLife: Int
    var kind: ParticleKind
}

enum ParticleKind {
    case sparkle
    case zzz
    case smoke
    case star
}

// MARK: - Animation Frame

struct ClawdFrame: Equatable {
    let pose: ClawdPose
    let offset: Int       // 0 = normal, 1 = crouched (shifted down)
    var xShift: CGFloat   // horizontal pixel shift (positive = right, toward notch)
    var yShift: CGFloat   // vertical pixel shift (positive = down, below panel)

    static let idle = ClawdFrame(pose: .default_, offset: 0, xShift: 0, yShift: 0)

    init(pose: ClawdPose, offset: Int, xShift: CGFloat = 0, yShift: CGFloat = 0) {
        self.pose = pose
        self.offset = offset
        self.xShift = xShift
        self.yShift = yShift
    }
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
    // New poses
    case sleeping
    case yawning
    case dozing
    case error
    case sweeping
    case carrying
    case juggling
    case conducting
    case flailing
    case poked
    // Notch-interaction poses (collapsed mode only)
    case peekSide     // looking sideways, half-hidden behind notch edge
    case hanging      // arms up gripping edge, body below
    case peekUp       // just eyes peeking up from bottom edge
    case climbing     // pulling self up, arms on edge
}

// MARK: - Animation Sequences

enum ClawdAnimations {
    static func hold(_ pose: ClawdPose, offset: Int = 0, frames: Int) -> [ClawdFrame] {
        Array(repeating: ClawdFrame(pose: pose, offset: offset), count: frames)
    }

    // === Original animations ===

    static let jumpWave: [ClawdFrame] =
        hold(.default_, offset: 1, frames: 2) +
        hold(.armsUp, frames: 3) +
        hold(.default_, frames: 1) +
        hold(.default_, offset: 1, frames: 2) +
        hold(.armsUp, frames: 3) +
        hold(.default_, frames: 1)

    static let lookAround: [ClawdFrame] =
        hold(.lookRight, frames: 5) +
        hold(.lookLeft, frames: 5) +
        hold(.default_, frames: 1)

    static let quickGlance: [ClawdFrame] =
        hold(Bool.random() ? .lookLeft : .lookRight, frames: 4) +
        hold(.default_, frames: 1)

    static let blink: [ClawdFrame] =
        hold(.default_, offset: 1, frames: 1) +
        hold(.default_, frames: 1)

    // === New animations ===

    /// Sleep transition: yawn → doze → sleep
    static let sleepTransition: [ClawdFrame] =
        hold(.default_, frames: 3) +
        hold(.yawning, frames: 8) +
        hold(.dozing, frames: 6) +
        hold(.sleeping, frames: 1)

    /// Wake up: reverse of sleep
    static let wakeUp: [ClawdFrame] =
        hold(.dozing, frames: 4) +
        hold(.yawning, frames: 4) +
        hold(.default_, offset: 1, frames: 2) +
        hold(.armsUp, frames: 3) +
        hold(.default_, frames: 1)

    /// Error: rapid shake
    static let errorShake: [ClawdFrame] =
        hold(.error, frames: 2) +
        hold(.lookLeft, frames: 1) +
        hold(.error, frames: 1) +
        hold(.lookRight, frames: 1) +
        hold(.error, frames: 1) +
        hold(.lookLeft, frames: 1) +
        hold(.error, frames: 2)

    /// Celebration: double jump with happy face
    static let celebration: [ClawdFrame] =
        hold(.default_, offset: 1, frames: 2) +
        hold(.happy, frames: 4) +
        hold(.default_, offset: 1, frames: 1) +
        hold(.happy, frames: 4) +
        hold(.default_, frames: 1)

    /// Sweep cycle
    static let sweep: [ClawdFrame] =
        hold(.sweeping, frames: 4) +
        hold(.default_, frames: 2) +
        hold(.sweeping, frames: 4)

    /// Carry one-shot
    static let carry: [ClawdFrame] =
        hold(.default_, offset: 1, frames: 2) +
        hold(.carrying, frames: 8) +
        hold(.default_, offset: 1, frames: 2) +
        hold(.default_, frames: 1)

    /// Juggle cycle (looped)
    static let juggle: [ClawdFrame] =
        hold(.juggling, frames: 3) +
        hold(.armsUp, frames: 3)

    /// Conduct cycle (looped)
    static let conduct: [ClawdFrame] =
        hold(.conducting, frames: 4) +
        hold(.armsUp, frames: 2) +
        hold(.conducting, frames: 4)

    /// Poke reaction (double-click)
    static let poke: [ClawdFrame] =
        hold(.poked, offset: 1, frames: 3) +
        hold(.default_, offset: 1, frames: 2) +
        hold(.armsUp, frames: 3) +
        hold(.default_, frames: 1)

    /// Flail (rapid clicks)
    static let flail: [ClawdFrame] =
        hold(.flailing, frames: 2) +
        hold(.armsUp, frames: 1) +
        hold(.flailing, frames: 2) +
        hold(.lookLeft, frames: 1) +
        hold(.flailing, frames: 2) +
        hold(.lookRight, frames: 1) +
        hold(.default_, frames: 1)

    // === Notch interaction animations ===
    // These use xShift/yShift to slide Clawd behind the physical notch cutout.
    // The clipping in the collapsed view makes parts of Clawd disappear
    // behind the notch edge, creating the illusion of hiding behind hardware.

    /// Helper: frames with position shift.
    static func shifted(_ pose: ClawdPose, offset: Int = 0, x: CGFloat = 0, y: CGFloat = 0, frames: Int) -> [ClawdFrame] {
        Array(repeating: ClawdFrame(pose: pose, offset: offset, xShift: x, yShift: y), count: frames)
    }

    /// Helper: smooth slide between two x positions over N frames.
    static func slideX(_ pose: ClawdPose, from startX: CGFloat, to endX: CGFloat, y: CGFloat = 0, frames: Int) -> [ClawdFrame] {
        (0..<frames).map { i in
            let t = CGFloat(i) / CGFloat(max(frames - 1, 1))
            let x = startX + (endX - startX) * t
            return ClawdFrame(pose: pose, offset: 0, xShift: x, yShift: y)
        }
    }

    /// Helper: smooth slide between two y positions over N frames.
    static func slideY(_ pose: ClawdPose, x: CGFloat = 0, from startY: CGFloat, to endY: CGFloat, frames: Int) -> [ClawdFrame] {
        (0..<frames).map { i in
            let t = CGFloat(i) / CGFloat(max(frames - 1, 1))
            let y = startY + (endY - startY) * t
            return ClawdFrame(pose: pose, offset: 0, xShift: x, yShift: y)
        }
    }

    /// Peek behind notch: Clawd slides right behind the notch edge,
    /// pauses (half-hidden), peeks with one eye, then slides back.
    static let notchPeek: [ClawdFrame] =
        slideX(.lookRight, from: 0, to: 20, frames: 8) +   // slide right toward notch
        shifted(.peekSide, x: 20, frames: 6) +              // peek from behind edge
        shifted(.peekSide, x: 18, frames: 4) +              // slight pull-back (curiosity)
        shifted(.peekSide, x: 20, frames: 4) +              // peek again
        slideX(.lookRight, from: 20, to: 0, frames: 8) +    // slide back
        hold(.default_, frames: 1)

    /// Hang from notch bottom: Clawd drops below the panel,
    /// only hands grip the bottom edge. Then climbs back up.
    static let notchHang: [ClawdFrame] =
        hold(.default_, offset: 1, frames: 2) +             // crouch (prepare to drop)
        slideY(.hanging, from: 0, to: 18, frames: 6) +      // slide down
        shifted(.hanging, y: 18, frames: 8) +                // dangle (only hands visible)
        shifted(.hanging, y: 16, frames: 3) +                // pull up slightly
        shifted(.hanging, y: 18, frames: 3) +                // slip back
        slideY(.climbing, from: 18, to: 8, frames: 5) +     // climb up halfway
        slideY(.climbing, from: 8, to: 0, frames: 5) +      // climb back to top
        hold(.default_, offset: 1, frames: 2) +             // land crouch
        hold(.default_, frames: 1)

    /// Peek up from below: Clawd drops out of sight, then just the top
    /// of head with eyes peeks up from the bottom edge.
    static let notchPeekUp: [ClawdFrame] =
        slideY(.default_, from: 0, to: 28, frames: 6) +     // drop below panel
        shifted(.default_, y: 28, frames: 6) +               // hidden (pause)
        slideY(.peekUp, from: 28, to: 18, frames: 5) +      // eyes peek up
        shifted(.peekUp, y: 18, frames: 8) +                 // hold peek (looking around)
        shifted(.peekUp, y: 20, frames: 3) +                 // duck slightly
        shifted(.peekUp, y: 18, frames: 3) +                 // peek again
        slideY(.default_, from: 18, to: 0, frames: 6) +     // climb back up
        hold(.default_, frames: 1)

    /// Quick shy hide: Clawd notices something, ducks behind notch edge
    /// briefly, then comes back looking the other way.
    static let notchShyHide: [ClawdFrame] =
        hold(.lookRight, frames: 3) +                        // notice something!
        slideX(.default_, from: 0, to: 24, frames: 5) +     // quick hide behind notch
        shifted(.default_, x: 24, frames: 10) +              // hiding (fully behind notch)
        shifted(.peekSide, x: 22, frames: 5) +              // careful peek
        slideX(.lookLeft, from: 22, to: 0, frames: 6) +     // scurry back
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
        case .armsUp, .alert, .happy, .juggling:
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

        // === New poses ===

        case .sleeping:
            // Eyes as horizontal slits (closed/squinting) — 2px wide line per eye
            return [
                [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o,o],
                [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o,o],
                [o,o,o,B,e,e,B,B,B,B,B,e,e,B,B,o,o,o],
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

        case .yawning:
            // Half-closed eyes (only row 2), mouth gap at row 5 center
            return [
                [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o,o],
                [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o,o],
                [o,o,o,B,B,e,B,B,B,B,B,B,e,B,B,o,o,o],
                [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o,o],
                [o,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,o],
                [o,B,B,B,B,B,B,B,o,o,B,B,B,B,B,B,o,o],
                [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o,o],
                [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o,o],
                [o,o,o,o,B,o,B,o,o,o,o,B,o,B,o,o,o,o],
                [o,o,o,o,B,o,B,o,o,o,o,B,o,B,o,o,o,o],
                [o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o],
                [o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o],
            ]

        case .dozing:
            // Sleeping but shifted right 1 col (head tilt), slit eyes
            return [
                [o,o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o],
                [o,o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o],
                [o,o,o,o,B,e,e,B,B,B,B,B,e,e,B,B,o,o],
                [o,o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o],
                [o,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,o],
                [o,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,o],
                [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o,o],
                [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o,o],
                [o,o,o,o,B,o,B,o,o,o,o,B,o,B,o,o,o,o],
                [o,o,o,o,B,o,B,o,o,o,o,B,o,B,o,o,o,o],
                [o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o],
                [o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o],
            ]

        case .error:
            // Wide 2×2 eyes, small mouth
            return [
                [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o,o],
                [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o,o],
                [o,o,o,B,e,e,B,B,B,B,B,e,e,B,B,o,o,o],
                [o,o,o,B,e,e,B,B,B,B,B,e,e,B,B,o,o,o],
                [o,B,B,B,B,B,B,B,e,e,B,B,B,B,B,B,B,o],
                [o,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,o],
                [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o,o],
                [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o,o],
                [o,o,o,o,B,o,B,o,o,o,o,B,o,B,o,o,o,o],
                [o,o,o,o,B,o,B,o,o,o,o,B,o,B,o,o,o,o],
                [o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o],
                [o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o],
            ]

        case .sweeping:
            // Head shifted right 1px, broom extends right
            return [
                [o,o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o],
                [o,o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o],
                [o,o,o,o,B,B,e,B,B,B,B,B,B,e,B,B,o,o],
                [o,o,o,o,B,B,e,B,B,B,B,B,B,e,B,B,o,o],
                [o,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,o],
                [o,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,o],
                [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,B,B,o],
                [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,e,e,o],
                [o,o,o,o,B,o,B,o,o,o,o,B,o,B,o,o,o,o],
                [o,o,o,o,B,o,B,o,o,o,o,B,o,B,o,o,o,o],
                [o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o],
                [o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o],
            ]

        case .carrying:
            // Arms down, holding a box below body
            return [
                [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o,o],
                [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o,o],
                [o,o,o,B,B,e,B,B,B,B,B,B,e,B,B,o,o,o],
                [o,o,o,B,B,e,B,B,B,B,B,B,e,B,B,o,o,o],
                [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o,o],
                [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o,o],
                [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o,o],
                [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o,o],
                [o,o,o,o,o,o,o,e,e,e,e,o,o,o,o,o,o,o],
                [o,o,o,o,o,o,o,e,e,e,e,o,o,o,o,o,o,o],
                [o,o,o,o,B,o,B,o,o,o,o,B,o,B,o,o,o,o],
                [o,o,o,o,B,o,B,o,o,o,o,B,o,B,o,o,o,o],
            ]

        case .conducting:
            // Left arm up, right arm extended with baton
            return [
                [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o,o],
                [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o,o],
                [o,B,B,B,B,e,B,B,B,B,B,B,e,B,B,o,o,o],
                [o,B,B,B,B,e,B,B,B,B,B,B,e,B,B,o,o,o],
                [o,o,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,o],
                [o,o,B,B,B,B,B,B,B,B,B,B,B,B,B,B,e,o],
                [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o,o],
                [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o,o],
                [o,o,o,o,B,o,B,o,o,o,o,B,o,B,o,o,o,o],
                [o,o,o,o,B,o,B,o,o,o,o,B,o,B,o,o,o,o],
                [o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o],
                [o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o],
            ]

        case .flailing:
            // Arms spread wide
            return [
                [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o,o],
                [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o,o],
                [o,B,o,B,B,e,B,B,B,B,B,B,e,B,B,o,B,o],
                [o,B,o,B,B,e,B,B,B,B,B,B,e,B,B,o,B,o],
                [o,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,o],
                [o,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,o],
                [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o,o],
                [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o,o],
                [o,o,o,o,B,o,B,o,o,o,o,B,o,B,o,o,o,o],
                [o,o,o,o,B,o,B,o,o,o,o,B,o,B,o,o,o,o],
                [o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o],
                [o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o],
            ]

        case .poked:
            // Vertically squished — content starts at row 2
            return [
                [o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o],
                [o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o],
                [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o,o],
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

        // === Notch interaction poses ===

        case .peekSide:
            // Looking right, body shifted right — only left portion visible
            // Eyes looking right (curious peek around the notch edge)
            return [
                [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o,o],
                [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o,o],
                [o,o,o,B,B,B,e,B,B,B,B,B,B,e,B,o,o,o],
                [o,o,o,B,B,B,e,B,B,B,B,B,B,e,B,o,o,o],
                [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,B,B,o],
                [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,B,B,o],
                [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o,o],
                [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o,o],
                [o,o,o,o,B,o,B,o,o,o,o,B,o,B,o,o,o,o],
                [o,o,o,o,B,o,B,o,o,o,o,B,o,B,o,o,o,o],
                [o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o],
                [o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o],
            ]

        case .hanging:
            // Arms up gripping the edge, body hangs below
            // Only the top portion (arms + head top) is meant to be visible
            return [
                [o,B,B,o,o,o,o,o,o,o,o,o,o,o,o,B,B,o],
                [o,B,B,o,o,o,o,o,o,o,o,o,o,o,o,B,B,o],
                [o,o,B,B,B,B,B,B,B,B,B,B,B,B,B,B,o,o],
                [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o,o],
                [o,o,o,B,B,e,B,B,B,B,B,B,e,B,B,o,o,o],
                [o,o,o,B,B,e,B,B,B,B,B,B,e,B,B,o,o,o],
                [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o,o],
                [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o,o],
                [o,o,o,o,B,o,B,o,o,o,o,B,o,B,o,o,o,o],
                [o,o,o,o,B,o,B,o,o,o,o,B,o,B,o,o,o,o],
                [o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o],
                [o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o],
            ]

        case .peekUp:
            // Just top of head with eyes — the rest is below the edge
            // Content concentrated in top rows
            return [
                [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o,o],
                [o,o,o,B,B,e,B,B,B,B,B,B,e,B,B,o,o,o],
                [o,o,o,B,B,e,B,B,B,B,B,B,e,B,B,o,o,o],
                [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o,o],
                [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o,o],
                [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o,o],
                [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o,o],
                [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o,o],
                [o,o,o,o,B,o,B,o,o,o,o,B,o,B,o,o,o,o],
                [o,o,o,o,B,o,B,o,o,o,o,B,o,B,o,o,o,o],
                [o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o],
                [o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o],
            ]

        case .climbing:
            // Pulling self up — arms on edge, head peeking over
            return [
                [o,B,B,o,o,o,o,o,o,o,o,o,o,o,o,B,B,o],
                [o,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,o],
                [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o,o],
                [o,o,o,B,B,e,B,B,B,B,B,B,e,B,B,o,o,o],
                [o,o,o,B,B,e,B,B,B,B,B,B,e,B,B,o,o,o],
                [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o,o],
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
