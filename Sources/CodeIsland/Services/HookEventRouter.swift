import Foundation

/// Routes incoming hook events from the SocketServer to AppState.
@MainActor
final class HookEventRouter {
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    /// Wire up the socket server to route events through AppState.
    func start() {
        // Capture appState for the sendable closure
        let state = appState
        SocketServer.shared.onEvent = { @Sendable payload, source, replyHandler in
            Task { @MainActor in
                state.handleEvent(payload, source: source, replyHandler: replyHandler)
            }
        }
    }
}
