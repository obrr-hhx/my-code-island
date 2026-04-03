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
        if !appState.pendingPermissions.isEmpty {
            return .alert
        }
        let statuses = appState.sessions.map(\.status)
        if statuses.contains(.waitingPermission) {
            return .alert
        }
        if statuses.contains(where: { if case .running(let t) = $0 { return t != nil }; return false }) {
            return .lookRight  // tool running
        }
        if statuses.contains(where: { if case .running = $0 { return true }; return false }) {
            return .thinking  // running but no specific tool
        }
        return .default_
    }

    var body: some View {
        HStack(spacing: 0) {
            // === LEFT WING: Clawd + label ===
            leftWing
                .frame(width: notchGeometry.leftWidth, height: notchGeometry.height)

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
            ClawdView(pixelSize: 2.5, pose: clawdPose, animated: true)
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
