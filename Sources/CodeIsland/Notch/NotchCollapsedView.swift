import SwiftUI

/// Collapsed notch view with content placed in the visible "wings"
/// on either side of the physical notch cutout.
///
/// Layout:
///   [  Clawd + label  |  notch (hidden)  |  status dots  ]
///   |<-- left wing -->|<--- 179pt gap -->|<- right wing ->|
///
/// Clawd pose changes based on app state:
///   idle       → default_ (relaxed, occasionally looking around)
///   thinking   → thinking (eyes darting)
///   tool use   → lookRight (watching)
///   permission → alert (arms up, bouncing!)
struct NotchCollapsedView: View {
    let appState: AppState
    let notchGeometry: NotchGeometry
    @State private var pulsePhase: Bool = false

    private var clawdPose: ClawdPose {
        // Permission takes highest priority
        if !appState.pendingPermissions.isEmpty {
            return .alert
        }
        let statuses = appState.sessions.map(\.status)
        if statuses.contains(.waitingPermission) {
            return .alert
        }

        // Map behavior to pose
        switch appState.clawdBehavior {
        case .sleeping: return .sleeping
        case .error: return .error
        case .celebrating: return .happy
        case .sweeping: return .sweeping
        case .carrying: return .carrying
        case .juggling: return .juggling
        case .conducting: return .conducting
        case .toolUse: return .lookRight
        case .thinking: return .thinking
        case .idle: return .default_
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // === LEFT WING: Clawd + label ===
            // Clip horizontally for notch-peek, allow hat overflow above notch
            leftWing
                .frame(width: notchGeometry.leftWidth, height: notchGeometry.height)
                .clipped()

            // === NOTCH GAP: invisible, skip this area ===
            Color.clear
                .frame(width: notchGeometry.notchWidth, height: notchGeometry.height)

            // === RIGHT WING: status dots ===
            rightWing
                .frame(width: notchGeometry.rightWidth, height: notchGeometry.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 16,
                bottomTrailingRadius: 16,
                topTrailingRadius: 0
            )
            .fill(.black)
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                pulsePhase = true
            }
        }
    }

    // MARK: - Left Wing

    private var leftWing: some View {
        HStack(spacing: 6) {
            ZStack {
                ClawdView(pixelSize: 2.5, pose: clawdPose, behavior: appState.clawdBehavior, animated: true, notchMode: true, skin: appState.clawdSkin)
                    .frame(width: 32, height: 26)

                // Error flash overlay
                if appState.clawdBehavior == .error {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.red.opacity(pulsePhase ? 0.3 : 0.0))
                        .frame(width: 32, height: 26)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: 32, height: 26)

            // Thin separator
            RoundedRectangle(cornerRadius: 1)
                .fill(RetroTheme.textMuted.opacity(0.25))
                .frame(width: 1, height: 14)

            // Label or mini status
            if appState.sessions.isEmpty {
                Text("CI")
                    .font(RetroTheme.pixelFont(size: 10, weight: .bold))
                    .foregroundStyle(RetroTheme.cyan.opacity(0.6))
            } else {
                Text("\(appState.sessions.count)")
                    .font(RetroTheme.pixelFont(size: 11, weight: .bold))
                    .foregroundStyle(RetroTheme.textPrimary)
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
    }

    // MARK: - Right Wing

    private var rightWing: some View {
        HStack(spacing: 5) {
            if !appState.pendingPermissions.isEmpty {
                // Permission badge
                HStack(spacing: 2) {
                    Text("!")
                        .font(RetroTheme.pixelFont(size: 9, weight: .bold))
                    Text("\(appState.pendingPermissions.count)")
                        .font(RetroTheme.pixelFont(size: 9, weight: .bold))
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(RetroTheme.claudeOrange)
                )
                .pixelGlow(RetroTheme.claudeOrange, radius: 3)
                .scaleEffect(pulsePhase ? 1.1 : 1.0)
            } else {
                // Session status dots
                ForEach(appState.sessions.prefix(4)) { session in
                    statusDot(for: session)
                }
            }
        }
        .padding(.leading, 4)
        .padding(.trailing, 10)
    }

    @ViewBuilder
    private func statusDot(for session: TrackedSession) -> some View {
        let color = colorForStatus(session.status)
        ZStack {
            Circle()
                .fill(color.opacity(0.2))
                .frame(width: 12, height: 12)
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .shadow(color: color.opacity(0.8), radius: 3)
        }
    }

    private func colorForStatus(_ status: SessionStatus) -> Color {
        switch status {
        case .idle: return RetroTheme.statusIdle
        case .running(let tool): return tool != nil ? RetroTheme.statusToolUse : RetroTheme.statusThinking
        case .waitingPermission: return RetroTheme.statusWaiting
        }
    }
}
