import Foundation

/// Supported coding agent types.
public enum AgentType: String, Codable, CaseIterable, Sendable {
    case claude
    case codex
    case droid
}

public enum CodeIslandConstants {
    /// Unix domain socket path for bridge ↔ app communication
    public static let socketPath = "/tmp/code-island.sock"

    /// PID file to prevent multiple instances
    public static let pidFilePath = "/tmp/code-island.pid"

    /// Claude Code sessions directory
    public static let claudeSessionsDir = NSHomeDirectory() + "/.claude/sessions"

    /// Claude Code settings file
    public static let claudeSettingsPath = NSHomeDirectory() + "/.claude/settings.json"

    /// Codex CLI sessions directory
    public static let codexSessionsDir = NSHomeDirectory() + "/.codex/sessions"

    /// Codex CLI hooks file
    public static let codexHooksPath = NSHomeDirectory() + "/.codex/hooks.json"

    /// Factory Droid settings file (same hook format as Claude Code)
    public static let droidSettingsPath = NSHomeDirectory() + "/.factory/settings.json"

    /// Dashscope API key file (legacy)
    public static let dashscopeKeyPath = NSHomeDirectory() + "/.config/code-island/dashscope.key"

    /// Doubao ASR App ID file
    public static let doubaoAppIdPath = NSHomeDirectory() + "/.config/code-island/doubao-app-id"
    /// Doubao ASR Access Token file
    public static let doubaoAccessTokenPath = NSHomeDirectory() + "/.config/code-island/doubao-access-token"

    /// Bridge binary name
    public static let bridgeBinaryName = "code-island-bridge"

    /// App bundle identifier
    public static let bundleIdentifier = "com.codeisland.app"

    /// Default timeout for permission requests (seconds)
    /// Claude Code's own timeout is 10 minutes, so we use slightly less.
    public static let permissionTimeout: TimeInterval = 570

    /// Session poll interval (seconds)
    public static let sessionPollInterval: TimeInterval = 5
}
