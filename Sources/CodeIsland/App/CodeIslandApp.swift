import AppKit

/// Pure AppKit entry point — no SwiftUI scene lifecycle.
/// All UI is managed by AppDelegate via NSPanel + NSHostingView.
/// This avoids SwiftUI's automatic app termination when no scenes are active.
@main
enum CodeIslandApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
