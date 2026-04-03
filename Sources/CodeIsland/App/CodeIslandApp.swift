import SwiftUI

/// Main entry point for Code Island.
@main
struct CodeIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // We use a Settings scene placeholder since the real UI
        // is the NotchPanel managed by AppDelegate.
        // This keeps the SwiftUI lifecycle happy.
        Settings {
            EmptyView()
        }
    }
}
