import Foundation

/// A processed hook event with additional computed properties.
struct HookEvent: Identifiable {
    let id = UUID()
    let timestamp = Date()
    let payload: HookEventPayload

    var eventName: String { payload.hook_event_name ?? "unknown" }
    var sessionId: String { payload.session_id ?? "unknown" }
    var toolName: String? { payload.tool_name }
    var cwd: String? { payload.cwd }

    /// Human-readable project name extracted from the working directory.
    var projectName: String {
        guard let cwd = payload.cwd else { return "Unknown" }
        return (cwd as NSString).lastPathComponent
    }

    /// Summary of what this event is about.
    var summary: String {
        switch eventName {
        case "PreToolUse":
            let tool = toolName ?? "tool"
            let input = payload.tool_input?.summary ?? ""
            return "\(tool): \(input)"
        case "PostToolUse":
            return "Completed: \(toolName ?? "tool")"
        case "Stop", "SubagentStop":
            return "Agent stopped"
        case "Notification":
            return payload.title ?? payload.message ?? "Notification"
        case "UserPromptSubmit":
            return "User submitted prompt"
        default:
            return eventName
        }
    }

    /// Whether this event requires user interaction (permission decision).
    var requiresDecision: Bool {
        eventName == "PreToolUse"
    }
}

/// A pending permission request waiting for user decision.
struct PermissionRequest: Identifiable {
    let id = UUID()
    let event: HookEvent
    let replyHandler: (BridgeResponse) -> Void
    let createdAt = Date()

    var toolName: String { event.toolName ?? "Unknown Tool" }
    var projectName: String { event.projectName }

    /// Extract the command or file path from tool input for display.
    var inputSummary: String {
        guard let input = event.payload.tool_input else { return "" }
        // Try common field names
        if let cmd = input.getString("command") {
            return cmd
        }
        if let path = input.getString("file_path") {
            return path
        }
        if let content = input.getString("content") {
            return String(content.prefix(200))
        }
        return input.summary
    }
}

/// A pending AskUserQuestion awaiting user selection.
struct UserQuestion: Identifiable {
    let id = UUID()
    let event: HookEvent
    let replyHandler: (BridgeResponse) -> Void
    let createdAt = Date()

    var projectName: String { event.projectName }

    /// Parsed question data from tool_input.
    struct ParsedQuestion {
        let question: String
        let header: String
        let options: [(label: String, description: String)]
        let multiSelect: Bool
    }

    /// Extract questions from the AskUserQuestion tool_input.
    var questions: [ParsedQuestion] {
        guard let input = event.payload.tool_input,
              case .array(let qArray) = getField(input, "questions") else {
            return []
        }
        return qArray.compactMap { qVal -> ParsedQuestion? in
            guard case .object(let q) = qVal else { return nil }
            guard case .string(let question) = q["question"],
                  case .string(let header) = q["header"],
                  case .array(let opts) = q["options"] else { return nil }
            let multiSelect: Bool
            if case .bool(let ms) = q["multiSelect"] { multiSelect = ms } else { multiSelect = false }
            let options = opts.compactMap { optVal -> (String, String)? in
                guard case .object(let opt) = optVal,
                      case .string(let label) = opt["label"],
                      case .string(let desc) = opt["description"] else { return nil }
                return (label, desc)
            }
            return ParsedQuestion(question: question, header: header, options: options, multiSelect: multiSelect)
        }
    }

    private func getField(_ val: JSONValue, _ key: String) -> JSONValue? {
        if case .object(let dict) = val { return dict[key] }
        return nil
    }
}
