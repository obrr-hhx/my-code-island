import SwiftUI

/// Expanded notch panel with full 8-bit retro aesthetic.
/// The top portion overlaps the notch (black, blending with it),
/// and the actual content starts BELOW the notch height.
struct NotchExpandedView: View {
    let appState: AppState
    let panelController: NotchPanelController

    private let notchHeight: CGFloat = 32
    @State private var showIdleSessions = false
    @State private var showSettings = false

    private var runningSessions: [TrackedSession] {
        appState.sessions.filter { $0.status != .idle }
    }
    private var idleSessions: [TrackedSession] {
        appState.sessions.filter { $0.status == .idle }
    }

    var body: some View {
        ZStack {
            // Background
            RetroTheme.background.opacity(0.95)

            // Dot wave background
            DotWaveView(gridSpacing: 20, dotColor: RetroTheme.cyan, baseOpacity: 0.01)
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                // Top spacer: black zone that blends with the notch
                Color.black
                    .frame(height: notchHeight)

                // Header bar — starts right below the notch
                headerBar

                // Pixel divider
                pixelDivider

                if showSettings {
                    SettingsView(appState: appState) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showSettings = false
                        }
                    }
                } else {
                    // Voice listening bar
                    if VoiceInputService.shared.isListening {
                        voiceListeningBar
                    }

                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 8) {
                            // Permission prompts (urgent, shown first)
                            ForEach(appState.pendingPermissions) { request in
                                PermissionPromptView(request: request, appState: appState)
                                    .transition(.asymmetric(
                                        insertion: .move(edge: .top).combined(with: .opacity),
                                        removal: .opacity
                                    ))
                            }

                            // AskUserQuestion prompts
                            ForEach(appState.pendingQuestions) { question in
                                UserQuestionView(question: question, appState: appState)
                                    .transition(.asymmetric(
                                        insertion: .move(edge: .top).combined(with: .opacity),
                                        removal: .opacity
                                    ))
                            }

                            // Multi-agent orchestration (when multiple sessions in same project)
                            if !appState.multiAgentProjects.isEmpty {
                                orchestrationSection
                            }

                            // File conflict warnings
                            ForEach(appState.fileConflicts, id: \.file) { conflict in
                                HStack(spacing: 4) {
                                    Text("⚠")
                                        .font(RetroTheme.pixelFont(size: 9))
                                        .foregroundStyle(RetroTheme.claudeOrange)
                                    Text("CONFLICT:")
                                        .font(RetroTheme.pixelFont(size: 8, weight: .bold))
                                        .foregroundStyle(RetroTheme.claudeOrange)
                                    Text(conflict.file)
                                        .font(RetroTheme.pixelFont(size: 8))
                                        .foregroundStyle(RetroTheme.textPrimary)
                                    Text("(\(conflict.sessions.count) agents)")
                                        .font(RetroTheme.pixelFont(size: 7))
                                        .foregroundStyle(RetroTheme.textMuted)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(RetroTheme.claudeOrange.opacity(0.08))
                                )
                                .pixelBorder(color: RetroTheme.claudeOrange.opacity(0.3), cornerRadius: 4)
                            }

                            // Running sessions (always visible)
                            ForEach(runningSessions) { session in
                                SessionCardView(session: session, appState: appState)
                            }

                            // Idle sessions (collapsed)
                            if !idleSessions.isEmpty {
                                idleSessionsSection
                            }

                            if appState.sessions.isEmpty && appState.pendingPermissions.isEmpty && appState.pendingQuestions.isEmpty {
                                emptyState
                            }
                        }
                        .padding(10)
                    }
                }
            }
        }
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 20,
                bottomTrailingRadius: 20,
                topTrailingRadius: 0
            )
        )
        .overlay(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 20,
                bottomTrailingRadius: 20,
                topTrailingRadius: 0
            )
            .strokeBorder(RetroTheme.border.opacity(0.3), lineWidth: 1)
        )
        .scanlines(opacity: 0.015)
    }

    // MARK: - Components

    private var headerBar: some View {
        HStack(spacing: 6) {
            // Clawd mascot icon
            ClawdView(pixelSize: 2, pose: .default_, behavior: appState.clawdBehavior, animated: true, skin: appState.clawdSkin)
                .frame(width: 26, height: 22)

            GlitchTextView(
                text: "CODE ISLAND",
                font: RetroTheme.pixelFont(size: 11, weight: .bold),
                color: RetroTheme.cyan,
                glitchColor: RetroTheme.textMuted
            )

            Spacer()

            // Permission mode toggle
            Button {
                let modes = PermissionMode.allCases
                if let idx = modes.firstIndex(of: appState.permissionMode) {
                    appState.permissionMode = modes[(idx + 1) % modes.count]
                }
            } label: {
                Text(modeLabel)
                    .font(RetroTheme.pixelFont(size: 8, weight: .bold))
                    .foregroundStyle(modeColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(modeColor.opacity(0.12))
                    )
                    .pixelBorder(color: modeColor.opacity(0.3), cornerRadius: 3)
            }
            .buttonStyle(.plain)

            // Settings button
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showSettings.toggle()
                }
            } label: {
                Text("⚙")
                    .font(RetroTheme.pixelFont(size: 10, weight: .bold))
                    .foregroundStyle(showSettings ? RetroTheme.cyan : RetroTheme.textSecondary)
                    .padding(4)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(showSettings ? RetroTheme.cyan.opacity(0.12) : RetroTheme.cardBg)
                    )
                    .pixelBorder(color: showSettings ? RetroTheme.cyan.opacity(0.3) : RetroTheme.border, cornerRadius: 3)
            }
            .buttonStyle(.plain)

            // Collapse button
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    appState.isExpanded = false
                }
            } label: {
                Text("▲")
                    .font(RetroTheme.pixelFont(size: 9, weight: .bold))
                    .foregroundStyle(RetroTheme.textSecondary)
                    .padding(4)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(RetroTheme.cardBg)
                    )
                    .pixelBorder(color: RetroTheme.border, cornerRadius: 3)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var pixelDivider: some View {
        HStack(spacing: 2) {
            ForEach(0..<60, id: \.self) { i in
                Rectangle()
                    .fill(i % 2 == 0 ? RetroTheme.border : Color.clear)
                    .frame(width: 3, height: 1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
    }

    private var modeLabel: String {
        switch appState.permissionMode {
        case .observe: return "OBSERVE"
        case .alwaysAllow: return "AUTO ✓"
        case .manual: return "MANUAL"
        }
    }

    private var modeColor: Color {
        switch appState.permissionMode {
        case .observe: return RetroTheme.cyan
        case .alwaysAllow: return RetroTheme.codexGreen
        case .manual: return RetroTheme.claudeOrange
        }
    }

    private var orchestrationSection: some View {
        VStack(spacing: 6) {
            ForEach(appState.multiAgentProjects, id: \.project) { project in
                VStack(alignment: .leading, spacing: 4) {
                    // Project header
                    HStack(spacing: 4) {
                        Text("⚡")
                            .font(RetroTheme.pixelFont(size: 9))
                        Text(project.project.uppercased())
                            .font(RetroTheme.pixelFont(size: 9, weight: .bold))
                            .foregroundStyle(RetroTheme.cyan)
                        Text("— \(project.sessions.count) AGENTS")
                            .font(RetroTheme.pixelFont(size: 8))
                            .foregroundStyle(RetroTheme.textMuted)
                        Spacer()
                    }

                    // Agent status bar — compact row of dots showing each session's state
                    HStack(spacing: 3) {
                        ForEach(project.sessions) { session in
                            HStack(spacing: 2) {
                                Circle()
                                    .fill(dotColor(for: session.status))
                                    .frame(width: 5, height: 5)
                                Text(session.session.agentType == .codex ? "CX" : session.session.agentType == .droid ? "DR" : "CC")
                                    .font(RetroTheme.pixelFont(size: 6, weight: .bold))
                                    .foregroundStyle(RetroTheme.textMuted)
                                if let tool = session.currentTool {
                                    Text(tool)
                                        .font(RetroTheme.pixelFont(size: 6))
                                        .foregroundStyle(RetroTheme.textMuted.opacity(0.7))
                                }
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(RetroTheme.cardBg)
                            )
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(RetroTheme.cyan.opacity(0.04))
                )
                .pixelBorder(color: RetroTheme.cyan.opacity(0.2), cornerRadius: 6)
            }
        }
    }

    private func dotColor(for status: SessionStatus) -> Color {
        switch status {
        case .idle: return RetroTheme.statusIdle
        case .running(let tool): return tool != nil ? RetroTheme.statusToolUse : RetroTheme.statusThinking
        case .waitingPermission: return RetroTheme.statusWaiting
        }
    }

    private var idleSessionsSection: some View {
        VStack(spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showIdleSessions.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Text(showIdleSessions ? "▾" : "▸")
                        .font(RetroTheme.pixelFont(size: 9, weight: .bold))
                        .foregroundStyle(RetroTheme.textMuted)
                    Text("\(idleSessions.count) IDLE SESSION\(idleSessions.count == 1 ? "" : "S")")
                        .font(RetroTheme.pixelFont(size: 9))
                        .foregroundStyle(RetroTheme.textMuted)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(RetroTheme.cardBg.opacity(0.3))
                )
            }
            .buttonStyle(.plain)

            if showIdleSessions {
                ForEach(idleSessions) { session in
                    SessionCardView(session: session, appState: appState)
                        .opacity(0.6)
                }
            }
        }
    }

    private var voiceListeningBar: some View {
        HStack(spacing: 8) {
            // Pulsing mic indicator
            Circle()
                .fill(RetroTheme.claudeOrange)
                .frame(width: 8, height: 8)
                .shadow(color: RetroTheme.claudeOrange.opacity(0.8), radius: 4)

            Text(VoiceInputService.shared.currentTranscript.isEmpty ? "LISTENING..." : VoiceInputService.shared.currentTranscript)
                .font(RetroTheme.pixelFont(size: 9))
                .foregroundStyle(RetroTheme.claudeOrange)
                .lineLimit(2)

            Spacer()

            Button {
                VoiceInputService.shared.stopListening()
            } label: {
                Text("■")
                    .font(RetroTheme.pixelFont(size: 9, weight: .bold))
                    .foregroundStyle(RetroTheme.claudeOrange)
                    .padding(4)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(RetroTheme.claudeOrange.opacity(0.1))
                    )
                    .pixelBorder(color: RetroTheme.claudeOrange.opacity(0.3), cornerRadius: 3)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(RetroTheme.claudeOrange.opacity(0.05))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("░░░░░░░░")
                .font(RetroTheme.pixelFont(size: 14))
                .foregroundStyle(RetroTheme.textMuted.opacity(0.3))

            GlitchTextView(
                text: "NO ACTIVE SESSIONS",
                font: RetroTheme.pixelFont(size: 11, weight: .medium),
                color: RetroTheme.textMuted,
                glitchColor: RetroTheme.cyan.opacity(0.5)
            )

            Text("start claude code or codex to see activity")
                .font(RetroTheme.pixelFont(size: 9))
                .foregroundStyle(RetroTheme.textMuted.opacity(0.5))
        }
        .padding(.vertical, 30)
    }
}
