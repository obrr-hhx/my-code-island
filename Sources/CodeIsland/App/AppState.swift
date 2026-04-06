import Foundation
import SwiftUI

/// Permission handling mode.
enum PermissionMode: String, CaseIterable {
    case observe = "Observe"
    case alwaysAllow = "Always Allow"
    case manual = "Manual"
}

/// Drives Clawd animation selection — richer than SessionStatus.
enum ClawdBehavior: Equatable {
    case idle
    case sleeping
    case thinking
    case toolUse
    case error
    case celebrating
    case sweeping
    case carrying
    case juggling
    case conducting
}

/// Central state management for the entire app.
///
/// Session status follows Claude Code's query loop lifecycle:
///   UserPromptSubmit → running (loop starts)
///   PreToolUse       → running("Bash") (tool starting)
///   PostToolUse      → running(nil) (tool done, loop continues)
///   SubagentStart    → running(nil) (background agent launched)
///   SubagentStop     → running(nil) (background agent done, loop may continue)
///   Stop             → idle (loop ended, waiting for next user input)
@MainActor
@Observable
final class AppState {
    var sessions: [TrackedSession] = []
    var pendingPermissions: [PermissionRequest] = []
    var pendingQuestions: [UserQuestion] = []
    var recentEvents: [HookEvent] = []
    var isExpanded: Bool = false
    var permissionMode: PermissionMode = .observe
    var clawdBehavior: ClawdBehavior = .idle

    private let maxRecentEvents = 50
    private var sleepTimer: Timer?
    private var behaviorResetTimer: Timer?

    // MARK: - Event Handling

    /// Source string from the bridge, used to tag sessions with agent type.
    private var lastEventSource: String?

    func handleEvent(_ payload: HookEventPayload, source: String? = nil, replyHandler: @escaping (BridgeResponse) -> Void) {
        lastEventSource = source
        let event = HookEvent(payload: payload)
        let session = findOrCreateSession(for: event)

        recentEvents.insert(event, at: 0)
        if recentEvents.count > maxRecentEvents {
            recentEvents.removeLast()
        }

        // Cancel sleep timer on any activity
        cancelSleepTimer()

        // If this session was waiting for permission but we got a non-permission event,
        // it means the user approved in the terminal — the tool already ran.
        // Only clear if the session was actually in waitingPermission state.
        if session.status == .waitingPermission
            && event.eventName != "PermissionRequest"
            && event.eventName != "PreToolUse" {
            print("[AppState] Session \(session.projectName) was waiting permission but got \(event.eventName) — clearing stale requests")
            clearStaleRequests(forSessionId: event.payload.session_id)
        }

        switch event.eventName {

        // === Loop start ===
        case "UserPromptSubmit":
            session.status = .running(nil)
            session.lastActivity = Date()
            setBehavior(.thinking)
            replyHandler(BridgeResponse.ack())

        // === Loop events (keep running) ===
        case "PreToolUse":
            session.status = .running(event.toolName)
            session.lastActivity = Date()
            setBehavior(.toolUse)

            // Intercept AskUserQuestion — show options in Island UI
            if event.toolName == "AskUserQuestion" {
                let question = UserQuestion(event: event, replyHandler: replyHandler)
                if !question.questions.isEmpty {
                    pendingQuestions.append(question)
                    isExpanded = true
                    ChiptuneEngine.shared.playNotification()
                    return  // Don't ack yet — bridge blocks until user answers
                }
            }

            replyHandler(BridgeResponse.ack())

        case "PostToolUse":
            // Check for error in tool result
            if hasToolError(event.payload.tool_result) {
                session.status = .running(nil)
                session.lastActivity = Date()
                setBehavior(.error, autoResetAfter: 3.0)
                ChiptuneEngine.shared.playError()
            } else {
                session.status = .running(nil)
                session.lastActivity = Date()
                setBehavior(.toolUse)
            }
            replyHandler(BridgeResponse.ack())

        case "SubagentStart":
            session.status = .running(nil)
            session.lastActivity = Date()
            session.activeSubagentCount += 1
            updateSubagentBehavior()
            replyHandler(BridgeResponse.ack())

        case "SubagentStop":
            session.status = .running(nil)
            session.lastActivity = Date()
            session.activeSubagentCount = max(0, session.activeSubagentCount - 1)
            updateSubagentBehavior()
            replyHandler(BridgeResponse.ack())

        // === Permission gate (blocks loop) ===
        case "PermissionRequest":
            session.status = .waitingPermission
            session.lastActivity = Date()
            handlePermissionRequest(event: event, replyHandler: replyHandler)

        // === Loop end ===
        case "Stop":
            session.status = .idle
            session.lastActivity = Date()
            session.activeSubagentCount = 0
            setBehavior(.celebrating, autoResetAfter: 2.0)
            ChiptuneEngine.shared.playCelebration()
            replyHandler(BridgeResponse.ack())

        // === Context compaction ===
        case "PreCompact":
            session.lastActivity = Date()
            setBehavior(.sweeping, autoResetAfter: 3.0)
            ChiptuneEngine.shared.playSweep()
            replyHandler(BridgeResponse.ack())

        // === Worktree creation ===
        case "WorktreeCreate":
            session.lastActivity = Date()
            setBehavior(.carrying, autoResetAfter: 3.0)
            replyHandler(BridgeResponse.ack())

        // === Other events ===
        case "Notification":
            ChiptuneEngine.shared.playNotification()
            replyHandler(BridgeResponse.ack())

        case "_timeout":
            // Socket timeout — clean up stale permissions for this session
            clearStaleRequests(forSessionId: event.payload.session_id)
            replyHandler(BridgeResponse.ack())

        default:
            replyHandler(BridgeResponse.ack())
        }
    }

    // MARK: - PermissionRequest Handling

    private func handlePermissionRequest(event: HookEvent, replyHandler: @escaping (BridgeResponse) -> Void) {
        switch permissionMode {
        case .alwaysAllow:
            // Auto-approve and reset session status back to running
            if let session = sessions.first(where: { $0.session.sessionId == event.sessionId }) {
                session.status = .running(nil)
            }
            replyHandler(BridgeResponse.allow())

        case .observe, .manual:
            let request = PermissionRequest(event: event, replyHandler: replyHandler)
            pendingPermissions.append(request)
            isExpanded = true
            ChiptuneEngine.shared.playPermissionAlert()
        }
    }

    // MARK: - Permission Resolution

    func resolvePermission(_ request: PermissionRequest, approve: Bool) {
        pendingPermissions.removeAll { $0.id == request.id }

        // After approval, session goes back to running (loop continues)
        if let session = sessions.first(where: { $0.session.sessionId == request.event.sessionId }) {
            session.status = .running(nil)
        }

        if approve {
            ChiptuneEngine.shared.playApproved()
            request.replyHandler(BridgeResponse.allow())
        } else {
            ChiptuneEngine.shared.playDenied()
            request.replyHandler(BridgeResponse.deny(reason: "Denied by user via Code Island"))
        }

        if pendingPermissions.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                if self?.pendingPermissions.isEmpty == true {
                    self?.isExpanded = false
                }
            }
        }
    }

    // MARK: - Stale Request Cleanup

    /// Clear pending permissions/questions for a session that was already handled in the terminal.
    private func clearStaleRequests(forSessionId sessionId: String?) {
        guard let sessionId else { return }
        let hadPermissions = !pendingPermissions.isEmpty
        pendingPermissions.removeAll { $0.event.sessionId == sessionId }
        pendingQuestions.removeAll { $0.event.sessionId == sessionId }

        if hadPermissions && pendingPermissions.isEmpty && pendingQuestions.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                if self?.pendingPermissions.isEmpty == true && self?.pendingQuestions.isEmpty == true {
                    self?.isExpanded = false
                }
            }
        }
    }

    // MARK: - AskUserQuestion Resolution

    /// User selected answers for an AskUserQuestion prompt.
    func resolveQuestion(_ question: UserQuestion, answers: [String: String]) {
        pendingQuestions.removeAll { $0.id == question.id }

        if let session = sessions.first(where: { $0.session.sessionId == question.event.sessionId }) {
            session.status = .running(nil)
        }

        // Build updatedInput: original tool_input with answers injected
        var inputDict: [String: JSONValue] = [:]
        if case .object(let orig) = question.event.payload.tool_input {
            inputDict = orig
        }
        inputDict["answers"] = .object(answers.mapValues { .string($0) })

        ChiptuneEngine.shared.playApproved()
        question.replyHandler(BridgeResponse.allowWithInput(.object(inputDict)))

        if pendingQuestions.isEmpty && pendingPermissions.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                if self?.pendingQuestions.isEmpty == true && self?.pendingPermissions.isEmpty == true {
                    self?.isExpanded = false
                }
            }
        }
    }

    // MARK: - Session Management

    private func findOrCreateSession(for event: HookEvent) -> TrackedSession {
        let agentType: AgentType = (lastEventSource == "codex") ? .codex : .claude

        guard let sessionId = event.payload.session_id else {
            // No session ID — create a transient one
            let session = ClaudeSession(pid: 0, sessionId: "unknown", cwd: "~", startedAt: Date().timeIntervalSince1970 * 1000, agentType: agentType)
            let tracked = TrackedSession(session: session)
            sessions.append(tracked)
            return tracked
        }

        if let existing = sessions.first(where: { $0.session.sessionId == sessionId }) {
            existing.isAlive = true
            // Back-fill PID from disk session file if we don't have one
            if existing.pid == 0 {
                existing.session = existing.session.withPID(Self.readPIDFromDisk(sessionId: sessionId))
            }
            return existing
        }

        let cwd = event.payload.cwd ?? "~"
        let pid = Self.readPIDFromDisk(sessionId: sessionId)
        let session = ClaudeSession(pid: pid, sessionId: sessionId, cwd: cwd, startedAt: Date().timeIntervalSince1970 * 1000, agentType: agentType)
        let tracked = TrackedSession(session: session)
        sessions.append(tracked)
        return tracked
    }

    /// Scan ~/.claude/sessions/ to find the PID for a given session UUID.
    /// Files are named by PID (e.g. 48308.json), content contains sessionId.
    private static func readPIDFromDisk(sessionId: String) -> Int {
        let dir = CodeIslandConstants.claudeSessionsDir
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: dir) else { return 0 }
        for file in files where file.hasSuffix(".json") {
            let path = (dir as NSString).appendingPathComponent(file)
            guard let data = fm.contents(atPath: path),
                  let session = try? JSONDecoder().decode(ClaudeSession.self, from: data),
                  session.sessionId == sessionId else { continue }
            return session.pid
        }
        return 0
    }

    func refreshSessions(_ diskSessions: [ClaudeSession]) {
        for ds in diskSessions {
            if let existing = sessions.first(where: { $0.session.sessionId == ds.sessionId }) {
                // Update PID from disk if hook-created session had pid=0
                if existing.pid == 0 && ds.pid > 0 {
                    existing.session = ds
                }
            } else {
                sessions.append(TrackedSession(session: ds))
            }
        }

        let diskIds = Set(diskSessions.map(\.sessionId))
        sessions.removeAll { session in
            if diskIds.contains(session.session.sessionId) { return false }
            session.checkAlive()
            return !session.isAlive
        }

        for session in sessions { session.checkAlive() }
    }

    // MARK: - Clawd Behavior

    /// Set behavior, optionally auto-resetting to idle after a duration.
    private func setBehavior(_ behavior: ClawdBehavior, autoResetAfter: TimeInterval? = nil) {
        behaviorResetTimer?.invalidate()
        behaviorResetTimer = nil
        clawdBehavior = behavior

        if let delay = autoResetAfter {
            behaviorResetTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.clawdBehavior = .idle
                    self.startSleepTimer()
                }
            }
        } else if behavior == .idle {
            startSleepTimer()
        }
    }

    /// Update behavior based on total active subagent count across sessions.
    private func updateSubagentBehavior() {
        let totalSubagents = sessions.reduce(0) { $0 + $1.activeSubagentCount }
        if totalSubagents >= 2 {
            setBehavior(.conducting)
        } else if totalSubagents == 1 {
            setBehavior(.juggling)
        } else {
            setBehavior(.thinking)
        }
    }

    /// Check if tool_result indicates an error.
    private func hasToolError(_ result: JSONValue?) -> Bool {
        guard let result else { return false }
        let text: String
        switch result {
        case .string(let s): text = s
        case .object(let dict):
            if case .bool(let isError) = dict["is_error"], isError { return true }
            text = dict.values.compactMap { if case .string(let s) = $0 { return s } else { return nil } }.joined()
        default: return false
        }
        let lower = text.lowercased()
        return lower.contains("error") || lower.contains("failed") || lower.contains("permission denied")
    }

    // MARK: - Sleep Timer

    private func startSleepTimer() {
        sleepTimer?.invalidate()
        sleepTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.clawdBehavior == .idle {
                    self.clawdBehavior = .sleeping
                    ChiptuneEngine.shared.playSleepChime()
                }
            }
        }
    }

    private func cancelSleepTimer() {
        sleepTimer?.invalidate()
        sleepTimer = nil
        // Wake up if sleeping
        if clawdBehavior == .sleeping {
            ChiptuneEngine.shared.playWakeUp()
        }
    }

    // MARK: - Notifications

    private func sendNotification(title: String, body: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "display notification \"\(body)\" with title \"\(title)\""]
        try? process.run()
    }
}
