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

// MARK: - Permission Rules

/// A rule for auto-approving or auto-denying specific tool calls.
struct PermissionRule: Identifiable, Codable, Equatable {
    let id: UUID
    /// Tool name to match (e.g. "Bash", "Read"). Empty = match all tools.
    var toolName: String
    /// Regex pattern to match against tool input (command, file_path, etc.). Empty = match any input.
    var inputPattern: String
    /// Action to take when matched.
    var action: RuleAction
    /// How many times this rule has been triggered.
    var hitCount: Int

    init(toolName: String, inputPattern: String = "", action: RuleAction = .allow) {
        self.id = UUID()
        self.toolName = toolName
        self.inputPattern = inputPattern
        self.action = action
        self.hitCount = 0
    }

    enum RuleAction: String, Codable {
        case allow
        case deny
    }

    /// Check if this rule matches a permission request.
    func matches(tool: String, input: String) -> Bool {
        // Tool name must match (case-insensitive)
        guard toolName.lowercased() == tool.lowercased() else { return false }
        // If no input pattern, match any input
        guard !inputPattern.isEmpty else { return true }
        // Regex match on input
        guard let regex = try? NSRegularExpression(pattern: inputPattern, options: [.caseInsensitive]) else { return false }
        return regex.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)) != nil
    }
}

/// Pre-defined safe tools that can be auto-approved.
enum PermissionRulePresets {
    /// Read-only tools that never modify the filesystem.
    static let safeTools = ["Read", "Glob", "Grep", "WebSearch", "WebFetch", "LSP"]

    /// Create rules for all safe tools.
    static func safeToolRules() -> [PermissionRule] {
        safeTools.map { PermissionRule(toolName: $0, action: .allow) }
    }

    /// Safe git commands (read-only).
    static func safeGitRule() -> PermissionRule {
        PermissionRule(toolName: "Bash", inputPattern: "^(git\\s+(status|diff|log|branch|show|remote|stash list))", action: .allow)
    }

    /// Safe listing commands.
    static func safeListRule() -> PermissionRule {
        PermissionRule(toolName: "Bash", inputPattern: "^(ls|pwd|echo|cat|head|tail|wc|which|type|file)\\b", action: .allow)
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
