import Foundation

/// Watches ~/.claude/sessions/ for active Claude Code sessions.
/// Uses periodic polling as a reliable cross-version approach.
@MainActor
final class SessionWatcher {
    private let appState: AppState
    private var timer: Timer?

    init(appState: AppState) {
        self.appState = appState
    }

    func start() {
        // Initial scan
        scan()

        // Periodic polling
        timer = Timer.scheduledTimer(withTimeInterval: CodeIslandConstants.sessionPollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.scan()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func scan() {
        var allSessions: [ClaudeSession] = []
        allSessions.append(contentsOf: scanClaude())
        allSessions.append(contentsOf: scanCodex())
        appState.refreshSessions(allSessions)

        // Resolve terminal names for sessions that haven't been resolved yet
        for session in appState.sessions {
            session.resolveTerminalIfNeeded()
        }
    }

    // MARK: - Claude Sessions

    private func scanClaude() -> [ClaudeSession] {
        let sessionsDir = CodeIslandConstants.claudeSessionsDir
        let fm = FileManager.default

        guard fm.fileExists(atPath: sessionsDir) else { return [] }

        do {
            let files = try fm.contentsOfDirectory(atPath: sessionsDir)
            let jsonFiles = files.filter { $0.hasSuffix(".json") }

            var sessions: [ClaudeSession] = []
            for file in jsonFiles {
                let path = (sessionsDir as NSString).appendingPathComponent(file)
                guard let data = fm.contents(atPath: path),
                      let session = try? JSONDecoder().decode(ClaudeSession.self, from: data) else {
                    continue
                }
                // Only include sessions with a running process
                if kill(Int32(session.pid), 0) == 0 {
                    sessions.append(session)
                }
            }
            return sessions
        } catch {
            return []
        }
    }

    // MARK: - Codex Sessions

    /// Scan Codex session .jsonl files from today and yesterday.
    private func scanCodex() -> [ClaudeSession] {
        let baseDir = CodeIslandConstants.codexSessionsDir
        let fm = FileManager.default
        guard fm.fileExists(atPath: baseDir) else { return [] }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        let today = formatter.string(from: Date())
        let yesterday = formatter.string(from: Date().addingTimeInterval(-86400))

        var sessions: [ClaudeSession] = []
        for dateStr in [today, yesterday] {
            let dayDir = (baseDir as NSString).appendingPathComponent(dateStr)
            guard let files = try? fm.contentsOfDirectory(atPath: dayDir) else { continue }

            for file in files where file.hasSuffix(".jsonl") {
                let path = (dayDir as NSString).appendingPathComponent(file)
                guard let handle = FileHandle(forReadingAtPath: path),
                      let lineData = handle.readLine(),
                      let meta = parseCodexSessionMeta(lineData) else {
                    continue
                }

                // Check if this session has recent hook activity
                // (Codex .jsonl files don't have PID in filename)
                let hasRecentActivity = appState.sessions.contains {
                    $0.session.sessionId == meta.id && $0.lastActivity.timeIntervalSinceNow > -60
                }
                if hasRecentActivity {
                    let session = ClaudeSession(
                        pid: 0,
                        sessionId: meta.id,
                        cwd: meta.cwd,
                        startedAt: meta.timestamp,
                        agentType: .codex
                    )
                    sessions.append(session)
                }
            }
        }
        return sessions
    }

    /// Parse the first line of a Codex .jsonl file for session metadata.
    private func parseCodexSessionMeta(_ data: Data) -> (id: String, cwd: String, timestamp: TimeInterval)? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["type"] as? String == "session_meta",
              let payload = json["payload"] as? [String: Any],
              let id = payload["id"] as? String,
              let cwd = payload["cwd"] as? String else {
            return nil
        }

        // Parse ISO timestamp or use current time
        var ts = Date().timeIntervalSince1970 * 1000
        if let tsStr = payload["timestamp"] as? String {
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = isoFormatter.date(from: tsStr) {
                ts = date.timeIntervalSince1970 * 1000
            }
        }
        return (id, cwd, ts)
    }
}

/// FileHandle extension to read a single line.
private extension FileHandle {
    func readLine() -> Data? {
        let chunkSize = 4096
        var buffer = Data()
        while true {
            let chunk = readData(ofLength: chunkSize)
            if chunk.isEmpty { break }
            if let newlineIdx = chunk.firstIndex(of: UInt8(ascii: "\n")) {
                buffer.append(chunk[chunk.startIndex..<newlineIdx])
                return buffer
            }
            buffer.append(chunk)
            if buffer.count > 65536 { return nil } // safety limit
        }
        return buffer.isEmpty ? nil : buffer
    }
}
