import SwiftUI

/// Permission approval/denial UI with full 8-bit retro styling.
struct PermissionPromptView: View {
    let request: PermissionRequest
    let appState: AppState
    @State private var alertPulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Alert header with flashing indicator
            HStack(spacing: 6) {
                // Flashing alert pixel
                Text("⚠")
                    .font(RetroTheme.pixelFont(size: 12))
                    .foregroundStyle(RetroTheme.claudeOrange)
                    .opacity(alertPulse ? 1.0 : 0.4)
                    .pixelGlow(RetroTheme.claudeOrange, radius: alertPulse ? 6 : 2)

                Text(request.toolName.uppercased())
                    .font(RetroTheme.pixelFont(size: 11, weight: .bold))
                    .foregroundStyle(RetroTheme.textPrimary)

                Spacer()

                // Project tag
                Text(request.projectName.uppercased())
                    .font(RetroTheme.pixelFont(size: 8))
                    .foregroundStyle(RetroTheme.claudeOrange.opacity(0.7))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 2)
                            .fill(RetroTheme.claudeOrange.opacity(0.1))
                    )
                    .pixelBorder(color: RetroTheme.claudeOrange.opacity(0.3), cornerRadius: 2)
            }

            // Input summary in terminal-style box
            if !request.inputSummary.isEmpty {
                HStack(spacing: 0) {
                    Text("$ ")
                        .font(RetroTheme.pixelFont(size: 10))
                        .foregroundStyle(RetroTheme.cyan.opacity(0.6))
                    Text(request.inputSummary)
                        .font(RetroTheme.pixelFont(size: 10))
                        .foregroundStyle(RetroTheme.textSecondary)
                        .lineLimit(4)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(RetroTheme.background)
                )
                .pixelBorder(color: RetroTheme.border.opacity(0.4), cornerRadius: 4)
            }

            // Action bar
            HStack(spacing: 8) {
                // Timer
                Text(timeAgo(request.createdAt))
                    .font(RetroTheme.pixelFont(size: 8))
                    .foregroundStyle(RetroTheme.textMuted)

                Spacer()

                // Deny button
                Button {
                    ChiptuneEngine.shared.playDenied()
                    withAnimation(.easeInOut(duration: 0.15)) {
                        appState.resolvePermission(request, approve: false)
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text("DENY")
                            .font(RetroTheme.pixelFont(size: 10, weight: .bold))
                        Text("⌘N")
                            .font(RetroTheme.pixelFont(size: 8))
                            .foregroundStyle(RetroTheme.textMuted)
                    }
                    .foregroundStyle(RetroTheme.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(RetroTheme.cardBg)
                    )
                    .pixelBorder(color: RetroTheme.statusStopped.opacity(0.4), cornerRadius: 4)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("n", modifiers: .command)

                // Allow button
                Button {
                    ChiptuneEngine.shared.playApproved()
                    withAnimation(.easeInOut(duration: 0.15)) {
                        appState.resolvePermission(request, approve: true)
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text("ALLOW")
                            .font(RetroTheme.pixelFont(size: 10, weight: .bold))
                        Text("⌘Y")
                            .font(RetroTheme.pixelFont(size: 8))
                            .foregroundStyle(RetroTheme.codexGreen.opacity(0.7))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(RetroTheme.codexGreen.opacity(0.7))
                    )
                    .pixelBorder(color: RetroTheme.codexGreen, cornerRadius: 4)
                    .pixelGlow(RetroTheme.codexGreen, radius: 3)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("y", modifiers: .command)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(RetroTheme.claudeOrange.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(RetroTheme.claudeOrange.opacity(0.25), lineWidth: 1)
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                alertPulse = true
            }
        }
    }

    private func timeAgo(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 5 { return "JUST NOW" }
        if seconds < 60 { return "\(seconds)S AGO" }
        return "\(seconds / 60)M AGO"
    }
}
