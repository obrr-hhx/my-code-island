import Foundation

/// Auto-configures Claude Code hooks in ~/.claude/settings.json
/// to invoke the bridge binary for all relevant events.
enum SettingsConfigurator {

    /// Hook events we want to intercept.
    private static let hookEvents = [
        "PreToolUse",
        "PostToolUse",
        "Stop",
        "SubagentStop",
        "SubagentStart",
        "Notification",
        "UserPromptSubmit",
        "PermissionRequest"
    ]

    /// Marker to identify our hooks in the config.
    private static let marker = "code-island-bridge"

    /// Ensure hooks are configured. Call on app launch.
    static func ensureHooksConfigured() {
        let bridgePath = resolveBridgePath()

        guard FileManager.default.fileExists(atPath: bridgePath) else {
            print("[SettingsConfigurator] Bridge binary not found at \(bridgePath)")
            return
        }

        let settingsPath = CodeIslandConstants.claudeSettingsPath

        // Read existing settings
        var settings: [String: Any] = [:]
        if let data = FileManager.default.contents(atPath: settingsPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = json
        }

        // Get or create hooks dict
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        var modified = false

        for eventName in hookEvents {
            // Check if we already have a hook for this event
            if let eventHooks = hooks[eventName] as? [[String: Any]] {
                let alreadyConfigured = eventHooks.contains { entry in
                    if let entryHooks = entry["hooks"] as? [[String: Any]] {
                        return entryHooks.contains { hook in
                            (hook["command"] as? String)?.contains(marker) == true
                        }
                    }
                    return false
                }
                if alreadyConfigured { continue }
            }

            // Add our hook entry
            let hookEntry: [String: Any] = [
                "hooks": [
                    [
                        "type": "command",
                        "command": bridgePath
                    ]
                ]
            ]

            var eventArray = hooks[eventName] as? [[String: Any]] ?? []
            eventArray.append(hookEntry)
            hooks[eventName] = eventArray
            modified = true
        }

        guard modified else {
            print("[SettingsConfigurator] Hooks already configured")
            return
        }

        // Write back
        settings["hooks"] = hooks

        do {
            let data = try JSONSerialization.data(
                withJSONObject: settings,
                options: [.prettyPrinted, .sortedKeys]
            )
            // Backup first
            let backupPath = settingsPath + ".bak"
            if FileManager.default.fileExists(atPath: settingsPath) {
                try? FileManager.default.copyItem(atPath: settingsPath, toPath: backupPath)
            }
            try data.write(to: URL(fileURLWithPath: settingsPath))
            print("[SettingsConfigurator] Hooks configured successfully")
        } catch {
            print("[SettingsConfigurator] Failed to write settings: \(error)")
        }
    }

    /// Remove our hooks from Claude Code settings.
    static func removeHooks() {
        let settingsPath = CodeIslandConstants.claudeSettingsPath

        guard let data = FileManager.default.contents(atPath: settingsPath),
              var settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var hooks = settings["hooks"] as? [String: Any] else {
            return
        }

        for eventName in hookEvents {
            guard var eventArray = hooks[eventName] as? [[String: Any]] else { continue }
            eventArray.removeAll { entry in
                if let entryHooks = entry["hooks"] as? [[String: Any]] {
                    return entryHooks.contains { hook in
                        (hook["command"] as? String)?.contains(marker) == true
                    }
                }
                return false
            }
            if eventArray.isEmpty {
                hooks.removeValue(forKey: eventName)
            } else {
                hooks[eventName] = eventArray
            }
        }

        settings["hooks"] = hooks.isEmpty ? nil : hooks

        if let data = try? JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys]
        ) {
            try? data.write(to: URL(fileURLWithPath: settingsPath))
        }
    }

    /// Find the bridge binary path.
    /// Looks for it next to the main executable (in .app bundle) or in .build/.
    private static func resolveBridgePath() -> String {
        // Check next to the current executable
        let executableURL = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
        let siblingPath = executableURL
            .deletingLastPathComponent()
            .appendingPathComponent(CodeIslandConstants.bridgeBinaryName)
            .path

        if FileManager.default.fileExists(atPath: siblingPath) {
            return siblingPath
        }

        // Check in .build directory (development)
        let devPath = FileManager.default.currentDirectoryPath + "/.build/" + CodeIslandConstants.bridgeBinaryName
        if FileManager.default.fileExists(atPath: devPath) {
            return devPath
        }

        // Fallback: assume it's in PATH
        return CodeIslandConstants.bridgeBinaryName
    }
}
