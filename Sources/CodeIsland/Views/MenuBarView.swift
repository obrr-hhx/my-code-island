import SwiftUI

/// Menu bar extra dropdown view (shown when clicking the menu bar icon).
struct MenuBarView: View {
    let appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(.cyan)
                Text("Code Island")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                Spacer()
            }
            .padding(.bottom, 4)

            Divider()

            // Active sessions
            if appState.sessions.isEmpty {
                Text("No active sessions")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(appState.sessions) { session in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(session.isAlive ? .green : .red)
                            .frame(width: 6, height: 6)
                        Text(session.projectName)
                            .font(.system(size: 12, design: .monospaced))
                        Spacer()
                        Text(session.session.elapsed)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }

            if !appState.pendingPermissions.isEmpty {
                Divider()
                Text("\(appState.pendingPermissions.count) pending permission\(appState.pendingPermissions.count == 1 ? "" : "s")")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.orange)
            }

            Divider()

            Button("Quit Code Island") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(12)
        .frame(width: 260)
    }
}
