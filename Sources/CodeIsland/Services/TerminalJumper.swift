import AppKit

/// Jumps to the terminal window/tab/pane where a Claude Code session is running.
///
/// Strategy:
/// 1. Get the session's PID → find its TTY via `ps`
/// 2. Match TTY against `tmux list-panes` → find tmux session:window.pane
/// 3. If tmux match found: `tmux select-window` + `tmux select-pane` to switch
/// 4. Activate the terminal app (iTerm2, Terminal.app, etc.)
/// 5. Fallback: walk PID chain to find terminal app and just activate it
enum TerminalJumper {

    private static let terminalBundleIDs: Set<String> = [
        "com.googlecode.iterm2",
        "com.apple.Terminal",
        "com.mitchellh.ghostty",
        "dev.warp.Warp-Stable",
        "com.microsoft.VSCode",
        "com.todesktop.230313mzl4w4u92",
        "com.codeium.windsurf",
    ]

    /// Jump to the terminal running the given session.
    static func jump(to session: TrackedSession) {
        let pid = session.pid
        guard pid > 0 else { return }

        // Step 1: Get TTY for this PID
        guard let tty = getTTY(forPid: Int32(pid)) else {
            // Fallback: just activate terminal via PID chain
            activateTerminalByPIDChain(Int32(pid))
            return
        }

        // Step 2: Try tmux pane matching
        if switchToTmuxPane(tty: tty) {
            // Step 3: Activate the terminal app
            activateTerminalByPIDChain(Int32(pid))
            return
        }

        // No tmux — just activate terminal
        activateTerminalByPIDChain(Int32(pid))
    }

    // MARK: - TTY Detection

    /// Get the TTY device for a PID. Returns e.g. "/dev/ttys005".
    private static func getTTY(forPid pid: Int32) -> String? {
        let output = shell("ps -o tty= -p \(pid)")
        let tty = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tty.isEmpty, tty != "??" else { return nil }
        // ps returns "ttys005", we need "/dev/ttys005"
        return tty.hasPrefix("/dev/") ? tty : "/dev/\(tty)"
    }

    // MARK: - Tmux Pane Switching

    /// Find the tmux pane matching a TTY and switch to it.
    /// Returns true if a match was found and switch was attempted.
    private static func switchToTmuxPane(tty: String) -> Bool {
        // List all tmux panes: "TTY session:window.pane"
        let output = shell("tmux list-panes -a -F '#{pane_tty} #{session_name}:#{window_index}.#{pane_index}'")
        guard !output.isEmpty else { return false }

        for line in output.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let paneTTY = String(parts[0])
            let target = String(parts[1])  // e.g. "work:7.1"

            if paneTTY == tty {
                // Found it! Parse session:window.pane
                let colonIdx = target.firstIndex(of: ":")
                let dotIdx = target.lastIndex(of: ".")

                if let ci = colonIdx, let di = dotIdx {
                    let session = String(target[target.startIndex..<ci])
                    let window = String(target[target.index(after: ci)..<di])
                    let pane = String(target[target.index(after: di)...])

                    // Switch tmux to this window and pane
                    _ = shell("tmux select-window -t '\(session):\(window)'")
                    _ = shell("tmux select-pane -t '\(session):\(window).\(pane)'")
                } else {
                    // Simpler format — just try direct target
                    _ = shell("tmux select-window -t '\(target)'")
                }
                return true
            }
        }
        return false
    }

    // MARK: - Terminal App Activation (PID chain fallback)

    private static func activateTerminalByPIDChain(_ pid: Int32) {
        let runningApps = NSWorkspace.shared.runningApplications
        let appByPid = Dictionary(
            runningApps.compactMap { app -> (pid_t, NSRunningApplication)? in
                guard app.processIdentifier > 0 else { return nil }
                return (app.processIdentifier, app)
            },
            uniquingKeysWith: { first, _ in first }
        )

        var current = pid
        var visited = Set<Int32>()

        for _ in 0..<20 {
            guard current > 1, !visited.contains(current) else { break }
            visited.insert(current)

            if let app = appByPid[current],
               let bundleID = app.bundleIdentifier,
               terminalBundleIDs.contains(bundleID) {
                app.activate()
                return
            }
            current = getParentPID(current)
        }

        // Last resort: activate iTerm2 if running
        if let iterm = runningApps.first(where: { $0.bundleIdentifier == "com.googlecode.iterm2" }) {
            iterm.activate()
        }
    }

    // MARK: - Helpers

    private static func getParentPID(_ pid: Int32) -> Int32 {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        let result = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        guard result == 0 else { return 0 }
        return info.kp_eproc.e_ppid
    }

    /// Run a shell command and return stdout.
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
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}
