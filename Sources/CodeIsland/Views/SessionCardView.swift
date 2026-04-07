import SwiftUI

/// Displays a single Claude Code session with 8-bit retro styling.
struct SessionCardView: View {
    let session: TrackedSession
    let appState: AppState
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
                HStack(spacing: 4) {
                    // Agent type badge
                    Text(agentBadgeLabel)
                        .font(RetroTheme.pixelFont(size: 7, weight: .bold))
                        .foregroundStyle(agentBadgeColor)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 2)
                                .fill(agentBadgeColor.opacity(0.15))
                        )

                    // Terminal badge
                    Text(session.terminalName)
                        .font(RetroTheme.pixelFont(size: 6, weight: .bold))
                        .foregroundStyle(RetroTheme.codexGreen)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 2)
                                .fill(RetroTheme.codexGreen.opacity(0.15))
                        )

                    Text(session.projectName.uppercased())
                        .font(RetroTheme.pixelFont(size: 11, weight: .bold))
                        .foregroundStyle(RetroTheme.textPrimary)
                        .lineLimit(1)
                }

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

            // Analytics mini-stats (only when hovering)
            if isHovering && session.toolCallCount > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    // Tool calls + errors
                    HStack(spacing: 3) {
                        Text("\(session.toolCallCount)")
                            .font(RetroTheme.pixelFont(size: 8, weight: .bold))
                            .foregroundStyle(RetroTheme.cyan)
                        Text("calls")
                            .font(RetroTheme.pixelFont(size: 7))
                            .foregroundStyle(RetroTheme.textMuted)
                        if session.errorCount > 0 {
                            Text("\(session.errorCount)err")
                                .font(RetroTheme.pixelFont(size: 7, weight: .bold))
                                .foregroundStyle(Color.red.opacity(0.8))
                        }
                    }
                    // Top tool
                    if let top = session.topTools.first {
                        Text("\(top.name)×\(top.count)")
                            .font(RetroTheme.pixelFont(size: 7))
                            .foregroundStyle(RetroTheme.textMuted)
                    }
                    // Compact count
                    if session.compactCount > 0 {
                        Text("⟳\(session.compactCount)")
                            .font(RetroTheme.pixelFont(size: 7))
                            .foregroundStyle(RetroTheme.claudeOrange.opacity(0.6))
                    }
                }
                .transition(.opacity)
            }

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

            // Per-session permission mode toggle
            Button {
                let modes = PermissionMode.allCases
                let current = appState.effectivePermissionMode(for: session)
                if let idx = modes.firstIndex(of: current) {
                    let next = modes[(idx + 1) % modes.count]
                    // If cycling back to global default, clear override
                    session.permissionModeOverride = (next == appState.permissionMode) ? nil : next
                }
            } label: {
                Text(sessionModeLabel)
                    .font(RetroTheme.pixelFont(size: 6, weight: .bold))
                    .foregroundStyle(sessionModeColor)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 2)
                            .fill(sessionModeColor.opacity(0.12))
                    )
                    .pixelBorder(color: sessionModeColor.opacity(0.3), cornerRadius: 2)
            }
            .buttonStyle(.plain)

            // Mic button for voice input
            Button {
                TerminalJumper.jump(to: session)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    VoiceInputService.shared.targetSession = session
                    VoiceInputService.shared.toggleListening()
                }
            } label: {
                Text(VoiceInputService.shared.isListening && VoiceInputService.shared.targetSession?.id == session.id ? "◉" : "◎")
                    .font(RetroTheme.pixelFont(size: 11, weight: .bold))
                    .foregroundStyle(VoiceInputService.shared.isListening && VoiceInputService.shared.targetSession?.id == session.id ? RetroTheme.claudeOrange : RetroTheme.textMuted)
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(RetroTheme.cardBg)
                    )
                    .pixelBorder(color: VoiceInputService.shared.isListening && VoiceInputService.shared.targetSession?.id == session.id ? RetroTheme.claudeOrange.opacity(0.3) : RetroTheme.border.opacity(0.3), cornerRadius: 3)
            }
            .buttonStyle(.plain)

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

    private var agentBadgeLabel: String {
        switch session.session.agentType {
        case .claude: return "CC"
        case .codex: return "CX"
        case .droid: return "DR"
        }
    }

    private var agentBadgeColor: Color {
        switch session.session.agentType {
        case .claude: return RetroTheme.cyan
        case .codex: return RetroTheme.codexGreen
        case .droid: return RetroTheme.cursorPurple
        }
    }

    private var sessionModeLabel: String {
        let mode = appState.effectivePermissionMode(for: session)
        let isOverride = session.permissionModeOverride != nil
        switch mode {
        case .observe: return isOverride ? "OBS" : "obs"
        case .alwaysAllow: return isOverride ? "AUTO" : "auto"
        case .manual: return isOverride ? "MAN" : "man"
        }
    }

    private var sessionModeColor: Color {
        switch appState.effectivePermissionMode(for: session) {
        case .observe: return RetroTheme.cyan
        case .alwaysAllow: return RetroTheme.codexGreen
        case .manual: return RetroTheme.claudeOrange
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
