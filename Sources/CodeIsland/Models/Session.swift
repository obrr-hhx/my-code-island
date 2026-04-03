import Foundation

/// Represents a Claude Code session discovered from ~/.claude/sessions/.
struct ClaudeSession: Identifiable, Codable {
    let pid: Int
    let sessionId: String
    let cwd: String
    let startedAt: TimeInterval  // milliseconds since epoch
    var kind: String?
    var entrypoint: String?

    var id: String { sessionId }

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
    let session: ClaudeSession
    var status: SessionStatus = .idle
    var lastActivity: Date = Date()
    var isAlive: Bool = true
    var activeSubagentCount: Int = 0

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
        isAlive = kill(Int32(pid), 0) == 0
    }
}
