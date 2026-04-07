import AppKit
import Foundation

/// A subagent spawned within a Claude Code session (via Task tool).
struct Subagent: Identifiable, Equatable {
    let id: String        // agent_id from hook
    let agentType: String // "Explore", "Plan", "Bash", etc.
    let startedAt: Date
}

/// Represents a Claude Code session discovered from ~/.claude/sessions/.
struct ClaudeSession: Identifiable, Codable {
    var pid: Int
    let sessionId: String
    let cwd: String
    let startedAt: TimeInterval  // milliseconds since epoch
    var kind: String?
    var entrypoint: String?
    var agentType: AgentType

    var id: String { sessionId }

    init(pid: Int, sessionId: String, cwd: String, startedAt: TimeInterval, kind: String? = nil, entrypoint: String? = nil, agentType: AgentType = .claude) {
        self.pid = pid
        self.sessionId = sessionId
        self.cwd = cwd
        self.startedAt = startedAt
        self.kind = kind
        self.entrypoint = entrypoint
        self.agentType = agentType
    }

    /// Custom decoding to default agentType when missing from JSON.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pid = try container.decode(Int.self, forKey: .pid)
        sessionId = try container.decode(String.self, forKey: .sessionId)
        cwd = try container.decode(String.self, forKey: .cwd)
        startedAt = try container.decode(TimeInterval.self, forKey: .startedAt)
        kind = try container.decodeIfPresent(String.self, forKey: .kind)
        entrypoint = try container.decodeIfPresent(String.self, forKey: .entrypoint)
        agentType = try container.decodeIfPresent(AgentType.self, forKey: .agentType) ?? .claude
    }

    /// Return a copy with an updated PID (if the new PID is valid).
    func withPID(_ newPid: Int) -> ClaudeSession {
        guard newPid > 0 else { return self }
        var copy = self
        copy.pid = newPid
        return copy
    }

    /// Human-readable project name.
    var projectName: String {
        (cwd as NSString).lastPathComponent
    }

    /// Session start time as Date.
    var startDate: Date {
        Date(timeIntervalSince1970: startedAt / 1000.0)
    }

    /// How long the session has been running.
    var elapsed: String {
        let interval = Date().timeIntervalSince(startDate)
        let minutes = Int(interval) / 60
        let hours = minutes / 60
        if hours > 0 {
            return "\(hours)h \(minutes % 60)m"
        }
        return "\(minutes)m"
    }
}

/// Runtime state for a tracked session (not persisted).
///
/// Lifecycle mirrors Claude Code's query loop:
///   UserPromptSubmit → running (loop starts)
///   PreToolUse/PostToolUse/SubagentStart/SubagentStop → still running
///   Stop → idle (loop ends)
enum SessionStatus: Equatable {
    case idle              // Waiting for user input
    case running(String?)  // Query loop active, optional current tool name
    case waitingPermission // PermissionRequest pending
}

/// Combined session info: file-based discovery + runtime state.
@Observable
final class TrackedSession: Identifiable {
    var session: ClaudeSession
    var status: SessionStatus = .idle
    var lastActivity: Date = Date()
    var isAlive: Bool = true
    var activeSubagentCount: Int = 0
    /// Active subagents spawned by this session (from SubagentStart/Stop events).
    var activeSubagents: [Subagent] = []
    /// Files currently being edited (tracked from PreToolUse for Edit/Write tools).
    var activeFiles: Set<String> = []
    /// Per-session permission mode. nil = use global default.
    var permissionModeOverride: PermissionMode?

    // MARK: - Session Analytics

    /// Total tool calls observed in this session.
    var toolCallCount: Int = 0
    /// Breakdown of tool calls by tool name.
    var toolFrequency: [String: Int] = [:]
    /// Number of errors detected (PostToolUse with error).
    var errorCount: Int = 0
    /// Number of permission requests received.
    var permissionRequestCount: Int = 0
    /// Number of context compactions (PreCompact events).
    var compactCount: Int = 0
    /// Timestamps of state transitions for timeline visualization.
    var stateTimeline: [(date: Date, status: SessionStatus)] = []

    /// Record a tool call for analytics.
    func recordToolCall(_ toolName: String?) {
        toolCallCount += 1
        if let name = toolName {
            toolFrequency[name, default: 0] += 1
        }
    }

    /// Record a state transition for the timeline.
    func recordStateTransition(_ newStatus: SessionStatus) {
        // Keep last 200 entries to bound memory
        if stateTimeline.count > 200 {
            stateTimeline.removeFirst(stateTimeline.count - 150)
        }
        stateTimeline.append((date: Date(), status: newStatus))
    }

    /// Top 3 most-used tools.
    var topTools: [(name: String, count: Int)] {
        toolFrequency.sorted { $0.value > $1.value }.prefix(3).map { ($0.key, $0.value) }
    }
    /// Cached terminal app name (e.g. "iTerm", "Term", "Ghostty"). Resolved once.
    var terminalName: String = "?"
    /// TTY of the session process (e.g. "/dev/ttys005"). Set during terminal detection.
    var tty: String?
    /// If session runs inside tmux, the pane ID (e.g. "%5"). Nil if not in tmux.
    var tmuxPaneId: String?
    private var terminalResolved = false

    var id: String { session.id }
    var projectName: String { session.projectName }
    var pid: Int { session.pid }

    /// Current tool name (extracted from status for display).
    var currentTool: String? {
        if case .running(let tool) = status { return tool }
        return nil
    }

    init(session: ClaudeSession) {
        self.session = session
    }

    func checkAlive() {
        if pid > 0 {
            isAlive = kill(Int32(pid), 0) == 0
        } else {
            // pid=0: keep alive if recent activity (Droid/Codex sessions without PID)
            isAlive = lastActivity.timeIntervalSinceNow > -300  // 5 minutes
        }
    }

    /// Resolve terminal name (called from SessionWatcher each poll cycle).
    /// Retries if PID was previously 0 and has since been back-filled.
    /// Reset so terminal detection re-runs on next poll (e.g. after PID back-fill).
    func resetTerminalDetection() {
        terminalResolved = false
        terminalName = "?"
    }

    func resolveTerminalIfNeeded() {
        guard !terminalResolved, pid > 0 else { return }
        terminalResolved = true
        let result = Self.detectTerminal(forPid: Int32(pid))
        terminalName = result.label
        tty = result.tty
        tmuxPaneId = result.tmuxPaneId
    }

    private static let knownTerminals: [(String, String)] = [
        ("com.googlecode.iterm2", "iTerm"),
        ("com.apple.Terminal", "Term"),
        ("com.mitchellh.ghostty", "Ghostty"),
        ("dev.warp.Warp-Stable", "Warp"),
        ("net.kovidgoyal.kitty", "Kitty"),
        ("org.alacritty", "Alac"),
        ("com.microsoft.VSCode", "VSC"),
        ("com.todesktop.230313mzl4w4u92", "Cursor"),
        ("com.codeium.windsurf", "Winds"),
    ]

    private struct TerminalInfo {
        var label: String = "?"
        var tty: String?
        var tmuxPaneId: String?
    }

    private static func detectTerminal(forPid pid: Int32) -> TerminalInfo {
        var info = TerminalInfo()

        // Resolve TTY for this PID
        let rawTTY = shell("ps -o tty= -p \(pid)").trimmingCharacters(in: .whitespacesAndNewlines)
        if !rawTTY.isEmpty, rawTTY != "??" {
            info.tty = rawTTY.hasPrefix("/dev/") ? rawTTY : "/dev/\(rawTTY)"
        }

        // Try direct PID chain first
        if let label = findTerminalByPIDChain(pid) {
            info.label = label
            return info
        }

        // Try via tmux: TTY → tmux pane → client PID chain
        guard let devTTY = info.tty else { return info }

        // Check if this TTY belongs to a tmux pane and get the pane ID
        let panes = shell("tmux list-panes -a -F '#{pane_tty} #{pane_id}'")
        for line in panes.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 1)
            guard parts.count == 2, String(parts[0]) == devTTY else { continue }
            info.tmuxPaneId = String(parts[1])
            break
        }

        guard info.tmuxPaneId != nil else { return info }

        // Walk tmux client PIDs to find the terminal
        let clients = shell("tmux list-clients -F '#{client_pid}'")
        for line in clients.split(separator: "\n") {
            let clientPid = Int32(line.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            guard clientPid > 0 else { continue }
            if let label = findTerminalByPIDChain(clientPid) {
                info.label = label
                return info
            }
        }
        return info
    }

    private static func findTerminalByPIDChain(_ startPid: Int32) -> String? {
        let appByPid = Dictionary(
            NSWorkspace.shared.runningApplications.compactMap { app -> (pid_t, NSRunningApplication)? in
                guard app.processIdentifier > 0 else { return nil }
                return (app.processIdentifier, app)
            },
            uniquingKeysWith: { first, _ in first }
        )
        var current = startPid
        var visited = Set<Int32>()
        for _ in 0..<20 {
            guard current > 1, !visited.contains(current) else { break }
            visited.insert(current)
            if let app = appByPid[current], let bid = app.bundleIdentifier {
                for (bundleId, label) in knownTerminals where bundleId == bid {
                    return label
                }
            }
            var info = kinfo_proc()
            var size = MemoryLayout<kinfo_proc>.size
            var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, current]
            guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { break }
            current = info.kp_eproc.e_ppid
        }
        return nil
    }

    private static func shell(_ command: String) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        } catch { return "" }
    }
}
