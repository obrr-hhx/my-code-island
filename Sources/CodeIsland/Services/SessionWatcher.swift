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
        let sessionsDir = CodeIslandConstants.claudeSessionsDir
        let fm = FileManager.default

        guard fm.fileExists(atPath: sessionsDir) else { return }

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

            appState.refreshSessions(sessions)
        } catch {
            // Directory read failed - ignore silently
        }
    }
}
