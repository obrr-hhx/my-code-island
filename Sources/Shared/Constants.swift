import Foundation

public enum CodeIslandConstants {
    /// Unix domain socket path for bridge ↔ app communication
    public static let socketPath = "/tmp/code-island.sock"

    /// PID file to prevent multiple instances
    public static let pidFilePath = "/tmp/code-island.pid"

    /// Claude Code sessions directory
    public static let claudeSessionsDir = NSHomeDirectory() + "/.claude/sessions"

    /// Claude Code settings file
    public static let claudeSettingsPath = NSHomeDirectory() + "/.claude/settings.json"

    /// Bridge binary name
    public static let bridgeBinaryName = "code-island-bridge"

    /// App bundle identifier
    public static let bundleIdentifier = "com.codeisland.app"

    /// Default timeout for permission requests (seconds)
    public static let permissionTimeout: TimeInterval = 55

    /// Session poll interval (seconds)
    public static let sessionPollInterval: TimeInterval = 5
}
