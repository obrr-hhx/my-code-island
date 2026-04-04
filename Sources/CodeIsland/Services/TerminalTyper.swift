import AppKit

/// Types text into the terminal using AppleScript.
/// Uses iTerm2's `write text` command which works regardless of screen/focus.
enum TerminalTyper {

    /// Send text to the active terminal session and press Enter.
    static func typeAndSend(_ text: String) {
        print("[TerminalTyper] typeAndSend: \(text.prefix(80))")
        guard !text.isEmpty else { return }

        // Try iTerm2 first (most common), then fallback
        if sendViaITerm(text) { return }
        if sendViaTerminalApp(text) { return }
        if sendViaClipboardPaste(text) { return }

        print("[TerminalTyper] All methods failed")
    }

    // MARK: - iTerm2

    private static func sendViaITerm(_ text: String) -> Bool {
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

    // MARK: - Terminal.app

    private static func sendViaTerminalApp(_ text: String) -> Bool {
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

    // MARK: - Clipboard paste fallback

    private static func sendViaClipboardPaste(_ text: String) -> Bool {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)

        let escaped = escapeForAppleScript(text)
        let script = """
        tell application "System Events"
            keystroke "v" using command down
            delay 0.3
            keystroke return
        end tell
        """
        let ok = runAppleScript(script)
        if ok { print("[TerminalTyper] Sent via clipboard paste") }
        return ok
    }

    // MARK: - Helpers

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
