import SwiftUI

/// Displays a single Claude Code session with 8-bit retro styling.
/// Tap to expand for full details; collapsed shows only essentials.
struct SessionCardView: View {
    let session: TrackedSession
    let appState: AppState
    @State private var isExpanded = false
    @State private var isHovering = false

    private var isVoiceActive: Bool {
        VoiceInputService.shared.isListening && VoiceInputService.shared.targetSession?.id == session.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // === Collapsed: always visible ===
            collapsedRow

            // === Expanded: details ===
            if isExpanded {
                expandedDetails
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isExpanded ? RetroTheme.cardBg : (isHovering ? RetroTheme.cardBg : RetroTheme.cardBg.opacity(0.5)))
        )
        .pixelBorder(
            color: isExpanded ? statusColor.opacity(0.4) : (isHovering ? statusColor.opacity(0.3) : RetroTheme.border.opacity(0.2)),
            cornerRadius: 6
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovering = hovering
            }
        }
    }

    // MARK: - Collapsed Row (compact summary)

    private var collapsedRow: some View {
        HStack(spacing: 8) {
            // Status dot
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
                .shadow(color: statusColor.opacity(0.8), radius: 3)

            // Agent badge
            Text(agentBadgeLabel)
                .font(RetroTheme.pixelFont(size: 7, weight: .bold))
                .foregroundStyle(agentBadgeColor)
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 2).fill(agentBadgeColor.opacity(0.15)))

            // Project name
            Text(session.projectName.uppercased())
                .font(RetroTheme.pixelFont(size: 11, weight: .bold))
                .foregroundStyle(RetroTheme.textPrimary)
                .lineLimit(1)

            Spacer()

            // Status text
            Text(statusText)
                .font(RetroTheme.pixelFont(size: 8))
                .foregroundStyle(statusColor.opacity(0.8))

            // Elapsed time
            Text(session.session.elapsed)
                .font(RetroTheme.pixelFont(size: 8))
                .foregroundStyle(RetroTheme.textMuted)

            // Expand indicator
            Text(isExpanded ? "▾" : "▸")
                .font(RetroTheme.pixelFont(size: 8))
                .foregroundStyle(RetroTheme.textMuted)

            // Dead indicator
            if !session.isAlive {
                Text("✕")
                    .font(RetroTheme.pixelFont(size: 9, weight: .bold))
                    .foregroundStyle(.red)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        }
    }

    // MARK: - Expanded Details

    private var expandedDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thin divider
            Rectangle()
                .fill(RetroTheme.border.opacity(0.3))
                .frame(height: 1)
                .padding(.top, 6)

            // Row 1: Terminal + current tool + mode
            HStack(spacing: 6) {
                // Terminal badge
                label(session.terminalName, color: RetroTheme.codexGreen)

                if let tool = session.currentTool {
                    label(tool, color: RetroTheme.statusToolUse)
                }

                Spacer()

                // Permission mode toggle
                Button {
                    let modes = PermissionMode.allCases
                    let current = appState.effectivePermissionMode(for: session)
                    if let idx = modes.firstIndex(of: current) {
                        let next = modes[(idx + 1) % modes.count]
                        session.permissionModeOverride = (next == appState.permissionMode) ? nil : next
                    }
                } label: {
                    label(sessionModeLabel, color: sessionModeColor)
                }
                .buttonStyle(.plain)
            }

            // Row 2: Analytics
            if session.toolCallCount > 0 {
                HStack(spacing: 8) {
                    statItem("\(session.toolCallCount)", label: "calls", color: RetroTheme.cyan)

                    if session.errorCount > 0 {
                        statItem("\(session.errorCount)", label: "errors", color: .red)
                    }

                    if session.compactCount > 0 {
                        statItem("\(session.compactCount)", label: "compacts", color: RetroTheme.claudeOrange)
                    }

                    if session.permissionRequestCount > 0 {
                        statItem("\(session.permissionRequestCount)", label: "perms", color: RetroTheme.statusWaiting)
                    }

                    Spacer()
                }
            }

            // Row 3: Top tools breakdown
            if !session.topTools.isEmpty {
                HStack(spacing: 4) {
                    Text("TOP:")
                        .font(RetroTheme.pixelFont(size: 7))
                        .foregroundStyle(RetroTheme.textMuted)
                    ForEach(session.topTools, id: \.name) { tool in
                        HStack(spacing: 2) {
                            Text(tool.name)
                                .font(RetroTheme.pixelFont(size: 7, weight: .bold))
                                .foregroundStyle(RetroTheme.textSecondary)
                            Text("×\(tool.count)")
                                .font(RetroTheme.pixelFont(size: 7))
                                .foregroundStyle(RetroTheme.textMuted)
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 2).fill(RetroTheme.background.opacity(0.5)))
                    }
                }
            }

            // Row 4: Active subagents within this session
            if !session.activeSubagents.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("SUBAGENTS (\(session.activeSubagents.count))")
                        .font(RetroTheme.pixelFont(size: 7))
                        .foregroundStyle(RetroTheme.textMuted)
                    HStack(spacing: 4) {
                        ForEach(session.activeSubagents) { sub in
                            HStack(spacing: 2) {
                                Circle()
                                    .fill(RetroTheme.statusThinking)
                                    .frame(width: 4, height: 4)
                                Text(sub.agentType)
                                    .font(RetroTheme.pixelFont(size: 7, weight: .bold))
                                    .foregroundStyle(RetroTheme.textSecondary)
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 2).fill(RetroTheme.cyan.opacity(0.08)))
                            .pixelBorder(color: RetroTheme.cyan.opacity(0.2), cornerRadius: 2)
                        }
                    }
                }
            }

            // Row 5: Sibling agents in same project + file conflicts
            if let siblings = siblingAgents, !siblings.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text("ALSO IN PROJECT:")
                            .font(RetroTheme.pixelFont(size: 7))
                            .foregroundStyle(RetroTheme.textMuted)
                        ForEach(siblings) { sibling in
                            HStack(spacing: 2) {
                                Circle()
                                    .fill(siblingDotColor(sibling.status))
                                    .frame(width: 4, height: 4)
                                Text(siblingBadge(sibling))
                                    .font(RetroTheme.pixelFont(size: 6, weight: .bold))
                                    .foregroundStyle(RetroTheme.textMuted)
                                if let tool = sibling.currentTool {
                                    Text(tool)
                                        .font(RetroTheme.pixelFont(size: 6))
                                        .foregroundStyle(RetroTheme.textMuted.opacity(0.7))
                                }
                            }
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 2).fill(RetroTheme.background.opacity(0.5)))
                        }
                    }

                    // File conflicts with siblings
                    let conflicts = sessionFileConflicts
                    if !conflicts.isEmpty {
                        ForEach(conflicts, id: \.self) { file in
                            HStack(spacing: 3) {
                                Text("⚠")
                                    .font(RetroTheme.pixelFont(size: 7))
                                    .foregroundStyle(RetroTheme.claudeOrange)
                                Text(file)
                                    .font(RetroTheme.pixelFont(size: 7))
                                    .foregroundStyle(RetroTheme.claudeOrange.opacity(0.8))
                            }
                        }
                    }
                }
            }

            // Row 5: Actions
            HStack(spacing: 6) {
                // Jump to terminal
                actionButton("TERMINAL", icon: "▶") {
                    TerminalJumper.jump(to: session)
                }

                // Voice input
                actionButton(isVoiceActive ? "STOP MIC" : "VOICE", icon: isVoiceActive ? "◉" : "◎", active: isVoiceActive) {
                    TerminalJumper.jump(to: session)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        VoiceInputService.shared.targetSession = session
                        VoiceInputService.shared.toggleListening()
                    }
                }

                Spacer()

                // CWD
                Text(session.session.cwd)
                    .font(RetroTheme.pixelFont(size: 7))
                    .foregroundStyle(RetroTheme.textMuted)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        }
    }

    // MARK: - Helper Views

    private func label(_ text: String, color: Color) -> some View {
        Text(text)
            .font(RetroTheme.pixelFont(size: 7, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 2).fill(color.opacity(0.12)))
            .pixelBorder(color: color.opacity(0.3), cornerRadius: 2)
    }

    private func statItem(_ value: String, label: String, color: Color) -> some View {
        HStack(spacing: 2) {
            Text(value)
                .font(RetroTheme.pixelFont(size: 9, weight: .bold))
                .foregroundStyle(color)
            Text(label)
                .font(RetroTheme.pixelFont(size: 7))
                .foregroundStyle(RetroTheme.textMuted)
        }
    }

    private func actionButton(_ text: String, icon: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text(icon)
                    .font(RetroTheme.pixelFont(size: 8))
                Text(text)
                    .font(RetroTheme.pixelFont(size: 7, weight: .bold))
            }
            .foregroundStyle(active ? RetroTheme.claudeOrange : RetroTheme.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 3).fill(RetroTheme.background.opacity(0.5)))
            .pixelBorder(color: (active ? RetroTheme.claudeOrange : RetroTheme.border).opacity(0.3), cornerRadius: 3)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Computed Properties

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

    /// Other sessions in the same project directory (excluding self).
    private var siblingAgents: [TrackedSession]? {
        let siblings = appState.sessions.filter {
            $0.id != session.id && $0.session.cwd == session.session.cwd && $0.isAlive
        }
        return siblings.isEmpty ? nil : siblings
    }

    /// Files being edited by both this session and sibling sessions.
    private var sessionFileConflicts: [String] {
        guard let siblings = siblingAgents else { return [] }
        let siblingFiles = Set(siblings.flatMap(\.activeFiles))
        return session.activeFiles.intersection(siblingFiles).map { ($0 as NSString).lastPathComponent }
    }

    private func siblingDotColor(_ status: SessionStatus) -> Color {
        switch status {
        case .idle: return RetroTheme.statusIdle
        case .running(let tool): return tool != nil ? RetroTheme.statusToolUse : RetroTheme.statusThinking
        case .waitingPermission: return RetroTheme.statusWaiting
        }
    }

    private func siblingBadge(_ sibling: TrackedSession) -> String {
        switch sibling.session.agentType {
        case .claude: return "CC"
        case .codex: return "CX"
        case .droid: return "DR"
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
            if let tool { return tool.uppercased() }
            return "RUNNING"
        case .waitingPermission: return "WAITING"
        }
    }
}
