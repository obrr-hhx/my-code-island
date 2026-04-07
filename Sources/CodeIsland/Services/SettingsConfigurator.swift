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
        "PermissionRequest",
        "PreCompact",
        "WorktreeCreate",
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

    // MARK: - Codex Hooks

    /// Codex hook events we want to intercept.
    private static let codexHookEvents = [
        "UserPromptSubmit",
        "Stop",
        "SessionStart",
        "PreToolUse",
        "PostToolUse",
        "SubagentStart",
        "SubagentStop",
    ]

    /// Ensure Codex hooks are configured. Call on app launch.
    static func ensureCodexHooksConfigured() {
        let bridgePath = resolveBridgePath()

        guard FileManager.default.fileExists(atPath: bridgePath) else {
            print("[SettingsConfigurator] Bridge binary not found at \(bridgePath)")
            return
        }

        let hooksPath = CodeIslandConstants.codexHooksPath

        // Read existing hooks
        var settings: [String: Any] = [:]
        if let data = FileManager.default.contents(atPath: hooksPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = json
        }

        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        var modified = false

        for eventName in codexHookEvents {
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

            let hookEntry: [String: Any] = [
                "hooks": [
                    [
                        "type": "command",
                        "command": bridgePath + " --source codex"
                    ]
                ]
            ]

            var eventArray = hooks[eventName] as? [[String: Any]] ?? []
            eventArray.append(hookEntry)
            hooks[eventName] = eventArray
            modified = true
        }

        guard modified else {
            print("[SettingsConfigurator] Codex hooks already configured")
            return
        }

        settings["hooks"] = hooks

        do {
            let data = try JSONSerialization.data(
                withJSONObject: settings,
                options: [.prettyPrinted, .sortedKeys]
            )
            let backupPath = hooksPath + ".bak"
            if FileManager.default.fileExists(atPath: hooksPath) {
                try? FileManager.default.copyItem(atPath: hooksPath, toPath: backupPath)
            }
            try data.write(to: URL(fileURLWithPath: hooksPath))
            print("[SettingsConfigurator] Codex hooks configured successfully")
        } catch {
            print("[SettingsConfigurator] Failed to write Codex hooks: \(error)")
        }
    }

    /// Remove our hooks from Codex settings.
    static func removeCodexHooks() {
        let hooksPath = CodeIslandConstants.codexHooksPath

        guard let data = FileManager.default.contents(atPath: hooksPath),
              var settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var hooks = settings["hooks"] as? [String: Any] else {
            return
        }

        for eventName in codexHookEvents {
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
            try? data.write(to: URL(fileURLWithPath: hooksPath))
        }
    }

    // MARK: - Droid Hooks

    /// Ensure Factory Droid hooks are configured (same format as Claude Code).
    static func ensureDroidHooksConfigured() {
        let bridgePath = resolveBridgePath()
        guard FileManager.default.fileExists(atPath: bridgePath) else { return }

        let settingsPath = CodeIslandConstants.droidSettingsPath

        // Ensure ~/.factory/ directory exists
        let dir = (settingsPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        var settings: [String: Any] = [:]
        if let data = FileManager.default.contents(atPath: settingsPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = json
        }

        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        var modified = false

        for eventName in hookEvents {
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

            let hookEntry: [String: Any] = [
                "hooks": [
                    [
                        "type": "command",
                        "command": bridgePath + " --source droid"
                    ]
                ]
            ]

            var eventArray = hooks[eventName] as? [[String: Any]] ?? []
            eventArray.append(hookEntry)
            hooks[eventName] = eventArray
            modified = true
        }

        guard modified else {
            print("[SettingsConfigurator] Droid hooks already configured")
            return
        }

        settings["hooks"] = hooks

        do {
            let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
            let backupPath = settingsPath + ".bak"
            if FileManager.default.fileExists(atPath: settingsPath) {
                try? FileManager.default.copyItem(atPath: settingsPath, toPath: backupPath)
            }
            try data.write(to: URL(fileURLWithPath: settingsPath))
            print("[SettingsConfigurator] Droid hooks configured successfully")
        } catch {
            print("[SettingsConfigurator] Failed to write Droid hooks: \(error)")
        }
    }

    /// Remove our hooks from Factory Droid settings.
    static func removeDroidHooks() {
        let settingsPath = CodeIslandConstants.droidSettingsPath

        guard let data = FileManager.default.contents(atPath: settingsPath),
              var settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var hooks = settings["hooks"] as? [String: Any] else { return }

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
        if let data = try? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: settingsPath))
        }
    }

    // MARK: - Bridge Path

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
