import Foundation
import SwiftUI

/// Permission handling mode.
enum PermissionMode: String, CaseIterable {
    case observe = "Observe"
    case alwaysAllow = "Always Allow"
    case manual = "Manual"
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

    private let maxRecentEvents = 50

    // MARK: - Event Handling

    func handleEvent(_ payload: HookEventPayload, replyHandler: @escaping (BridgeResponse) -> Void) {
        let event = HookEvent(payload: payload)
        let session = findOrCreateSession(for: event)

        recentEvents.insert(event, at: 0)
        if recentEvents.count > maxRecentEvents {
            recentEvents.removeLast()
        }

        switch event.eventName {

        // === Loop start ===
        case "UserPromptSubmit":
            session.status = .running(nil)
            session.lastActivity = Date()
            replyHandler(BridgeResponse.ack())

        // === Loop events (keep running) ===
        case "PreToolUse":
            session.status = .running(event.toolName)
            session.lastActivity = Date()

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
            // Tool done, but loop continues — stay running, clear tool name
            session.status = .running(nil)
            session.lastActivity = Date()
            replyHandler(BridgeResponse.ack())

        case "SubagentStart":
            // Background agent launched — still running
            session.status = .running(nil)
            session.lastActivity = Date()
            replyHandler(BridgeResponse.ack())

        case "SubagentStop":
            // Background agent done — loop may still be running
            session.status = .running(nil)
            session.lastActivity = Date()
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
            replyHandler(BridgeResponse.ack())

        // === Other events (don't change status) ===
        case "Notification":
            ChiptuneEngine.shared.playNotification()
            replyHandler(BridgeResponse.ack())

        default:
            replyHandler(BridgeResponse.ack())
        }
    }

    // MARK: - PermissionRequest Handling

    private func handlePermissionRequest(event: HookEvent, replyHandler: @escaping (BridgeResponse) -> Void) {
        switch permissionMode {
        case .alwaysAllow:
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
        guard let sessionId = event.payload.session_id else {
            // No session ID — create a transient one
            let session = ClaudeSession(pid: 0, sessionId: "unknown", cwd: "~", startedAt: Date().timeIntervalSince1970 * 1000)
            let tracked = TrackedSession(session: session)
            sessions.append(tracked)
            return tracked
        }

        if let existing = sessions.first(where: { $0.session.sessionId == sessionId }) {
            existing.isAlive = true
            return existing
        }

        let cwd = event.payload.cwd ?? "~"
        let session = ClaudeSession(pid: 0, sessionId: sessionId, cwd: cwd, startedAt: Date().timeIntervalSince1970 * 1000)
        let tracked = TrackedSession(session: session)
        sessions.append(tracked)
        return tracked
    }

    func refreshSessions(_ diskSessions: [ClaudeSession]) {
        for ds in diskSessions {
            if !sessions.contains(where: { $0.session.sessionId == ds.sessionId }) {
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

    // MARK: - Notifications

    private func sendNotification(title: String, body: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "display notification \"\(body)\" with title \"\(title)\""]
        try? process.run()
    }
}
