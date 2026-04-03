import SwiftUI

/// Displays a single Claude Code session with 8-bit retro styling.
struct SessionCardView: View {
    let session: TrackedSession
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            // Status indicator with glow
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 16, height: 16)
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                    .shadow(color: statusColor.opacity(0.8), radius: 4)
            }

            // Project info
            VStack(alignment: .leading, spacing: 3) {
                Text(session.projectName.uppercased())
                    .font(RetroTheme.pixelFont(size: 11, weight: .bold))
                    .foregroundStyle(RetroTheme.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    // Status pixel indicator
                    Text("►")
                        .font(RetroTheme.pixelFont(size: 7))
                        .foregroundStyle(statusColor)

                    Text(statusText)
                        .font(RetroTheme.pixelFont(size: 9))
                        .foregroundStyle(statusColor.opacity(0.8))

                    if let tool = session.currentTool {
                        Text("·")
                            .foregroundStyle(RetroTheme.textMuted)
                        Text(tool)
                            .font(RetroTheme.pixelFont(size: 9))
                            .foregroundStyle(RetroTheme.textMuted)
                    }
                }
            }

            Spacer()

            // Elapsed time in retro box
            VStack(spacing: 1) {
                Text(session.session.elapsed)
                    .font(RetroTheme.pixelFont(size: 9))
                    .foregroundStyle(RetroTheme.textMuted)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(RetroTheme.background.opacity(0.5))
            )
            .pixelBorder(color: RetroTheme.border.opacity(0.3), cornerRadius: 3)

            // Dead session indicator
            if !session.isAlive {
                Text("✕")
                    .font(RetroTheme.pixelFont(size: 10, weight: .bold))
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovering ? RetroTheme.cardBg : RetroTheme.cardBg.opacity(0.5))
        )
        .pixelBorder(
            color: isHovering ? statusColor.opacity(0.3) : RetroTheme.border.opacity(0.2),
            cornerRadius: 6
        )
        .onTapGesture {
            TerminalJumper.jump(to: session)
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovering = hovering
            }
        }
    }

    private var statusColor: Color {
        switch session.status {
        case .idle: return RetroTheme.statusIdle
        case .running(let tool): return tool != nil ? RetroTheme.statusToolUse : RetroTheme.statusThinking
        case .waitingPermission: return RetroTheme.statusWaiting
        }
    }

    private var statusText: String {
        switch session.status {
        case .idle: return "IDLE"
        case .running(let tool):
            if let tool { return "RUNNING \(tool.uppercased())" }
            return "RUNNING..."
        case .waitingPermission: return "AWAITING APPROVAL"
        }
    }
}
