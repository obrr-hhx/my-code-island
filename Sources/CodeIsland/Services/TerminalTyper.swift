import AppKit

/// Types text into the terminal where a specific session is running.
/// Detects the terminal from the session's PID chain and uses the appropriate method.
enum TerminalTyper {

    private static let terminalBundleIDs: Set<String> = [
        "com.googlecode.iterm2",
        "com.apple.Terminal",
        "com.mitchellh.ghostty",
        "dev.warp.Warp-Stable",
        "net.kovidgoyal.kitty",
        "org.alacritty",
        "com.microsoft.VSCode",
        "com.todesktop.230313mzl4w4u92",
        "com.codeium.windsurf",
    ]

    /// Send text to the terminal running the given session.
    /// Priority: tmux pane → iTerm2 by TTY → terminal-specific → fallback
    static func typeAndSend(_ text: String, session: TrackedSession?) {
        print("[TerminalTyper] typeAndSend: \(text.prefix(80))")
        guard !text.isEmpty else { return }

        if let session {
            // 1. Tmux: send directly to the exact pane
            if let paneId = session.tmuxPaneId {
                if sendViaTmux(text, paneId: paneId) { return }
            }

            // 2. iTerm2: target exact session by TTY
            if session.terminalName == "iTerm", let tty = session.tty {
                if sendViaITermTTY(text, tty: tty) { return }
            }

            // 3. Other terminals: use terminal-specific method
            let bundleId = findTerminalBundleId(forSession: session)
            print("[TerminalTyper] Session terminal: \(bundleId ?? "unknown")")
            if let bid = bundleId {
                switch bid {
                case "com.googlecode.iterm2":
                    if sendViaITerm(text) { return }
                case "com.apple.Terminal":
                    if sendViaTerminalApp(text) { return }
                default:
                    if sendViaClipboardPaste(text, bundleId: bid) { return }
                }
            }
        }

        // Fallback: try iTerm2, then Terminal.app, then any frontmost
        if sendViaITerm(text) { return }
        if sendViaTerminalApp(text) { return }
        if sendViaClipboardPaste(text, bundleId: nil) { return }

        print("[TerminalTyper] All methods failed")
    }

    // MARK: - Terminal Detection from Session PID

    /// Walk up the PID chain from a session to find its terminal app.
    private static func findTerminalBundleId(forSession session: TrackedSession) -> String? {
        let pid = Int32(session.pid)
        guard pid > 0 else { return nil }

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
                return bundleID
            }
            current = getParentPID(current)
        }
        return nil
    }

    // MARK: - Tmux Pane Targeting

    /// Send text to an exact tmux pane via `tmux send-keys`.
    private static func sendViaTmux(_ text: String, paneId: String) -> Bool {
        let escaped = text.replacingOccurrences(of: "'", with: "'\\''")
        let result = shell("tmux send-keys -t '\(paneId)' '\(escaped)' Enter && echo OK")
        if result.trimmingCharacters(in: .whitespacesAndNewlines) == "OK" {
            print("[TerminalTyper] Sent via tmux send-keys to pane \(paneId)")
            return true
        }
        print("[TerminalTyper] tmux send-keys to \(paneId) failed")
        return false
    }

    // MARK: - iTerm2 by TTY (precise session targeting)

    /// Target a specific iTerm2 session by its TTY path.
    private static func sendViaITermTTY(_ text: String, tty: String) -> Bool {
        guard NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == "com.googlecode.iterm2" }) else {
            return false
        }
        let escaped = escapeForAppleScript(text)
        let script = """
        tell application "iTerm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s is "\(tty)" then
                            tell s to write text "\(escaped)"
                            return
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        """
        let ok = runAppleScript(script)
        if ok { print("[TerminalTyper] Sent via iTerm2 TTY \(tty)") }
        return ok
    }

    // MARK: - iTerm2 (AppleScript)

    private static func sendViaITerm(_ text: String) -> Bool {
        guard NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == "com.googlecode.iterm2" }) else {
            return false
        }
        let escaped = escapeForAppleScript(text)
        let script = """
        tell application "iTerm2"
            activate
            tell current session of current window
                write text "\(escaped)"
            end tell
        end tell
        """
        let ok = runAppleScript(script)
        if ok { print("[TerminalTyper] Sent via iTerm2") }
        return ok
    }

    // MARK: - Terminal.app (AppleScript)

    private static func sendViaTerminalApp(_ text: String) -> Bool {
        guard NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == "com.apple.Terminal" }) else {
            return false
        }
        let escaped = escapeForAppleScript(text)
        let script = """
        tell application "Terminal"
            activate
            do script "\(escaped)" in front window
        end tell
        """
        let ok = runAppleScript(script)
        if ok { print("[TerminalTyper] Sent via Terminal.app") }
        return ok
    }

    // MARK: - Clipboard Paste (works with any terminal)

    private static func sendViaClipboardPaste(_ text: String, bundleId: String?) -> Bool {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)

        // Activate the target terminal
        if let bid = bundleId,
           let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bid }) {
            app.activate()
            Thread.sleep(forTimeInterval: 0.5)
        }

        let script = """
        tell application "System Events"
            keystroke "v" using command down
            delay 0.3
            keystroke return
        end tell
        """
        let ok = runAppleScript(script)
        if ok { print("[TerminalTyper] Sent via clipboard paste to \(bundleId ?? "frontmost")") }
        return ok
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
            return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        } catch { return "" }
    }

    private static func escapeForAppleScript(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func runAppleScript(_ source: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        let errPipe = Pipe()
        process.standardError = errPipe
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let errStr = String(data: errData, encoding: .utf8) ?? ""
                print("[TerminalTyper] AppleScript error: \(errStr.prefix(200))")
                return false
            }
            return true
        } catch {
            print("[TerminalTyper] osascript failed: \(error)")
            return false
        }
    }
}
