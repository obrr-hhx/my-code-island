import SwiftUI

/// Settings panel shown inside the expanded notch.
struct SettingsView: View {
    let appState: AppState
    let onDismiss: () -> Void

    @State private var soundEnabled = !ChiptuneEngine.shared.isMuted
    @State private var appIdText = VoiceInputService.shared.loadKey(CodeIslandConstants.doubaoAppIdPath) ?? ""
    @State private var accessTokenText = VoiceInputService.shared.loadKey(CodeIslandConstants.doubaoAccessTokenPath) ?? ""
    @State private var apiKeySaved = false

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Text("⚙ SETTINGS")
                    .font(RetroTheme.pixelFont(size: 11, weight: .bold))
                    .foregroundStyle(RetroTheme.cyan)
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Text("✕")
                        .font(RetroTheme.pixelFont(size: 10, weight: .bold))
                        .foregroundStyle(RetroTheme.textSecondary)
                        .padding(4)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(RetroTheme.cardBg)
                        )
                        .pixelBorder(color: RetroTheme.border, cornerRadius: 3)
                }
                .buttonStyle(.plain)
            }

            pixelDivider

            // Permission Mode
            settingSection("PERMISSION MODE") {
                ForEach(PermissionMode.allCases, id: \.rawValue) { mode in
                    Button {
                        appState.permissionMode = mode
                    } label: {
                        HStack(spacing: 6) {
                            Text(appState.permissionMode == mode ? "●" : "○")
                                .font(RetroTheme.pixelFont(size: 9))
                                .foregroundStyle(colorForMode(mode))
                            Text(mode.rawValue.uppercased())
                                .font(RetroTheme.pixelFont(size: 9, weight: .medium))
                                .foregroundStyle(appState.permissionMode == mode ? colorForMode(mode) : RetroTheme.textSecondary)
                            Spacer()
                            Text(descriptionForMode(mode))
                                .font(RetroTheme.pixelFont(size: 7))
                                .foregroundStyle(RetroTheme.textMuted)
                        }
                        .padding(.vertical, 3)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Sound
            settingSection("SOUND") {
                Button {
                    soundEnabled.toggle()
                    ChiptuneEngine.shared.isMuted = !soundEnabled
                } label: {
                    HStack(spacing: 6) {
                        Text(soundEnabled ? "♪ ON" : "♪ OFF")
                            .font(RetroTheme.pixelFont(size: 9, weight: .medium))
                            .foregroundStyle(soundEnabled ? RetroTheme.codexGreen : RetroTheme.textMuted)
                        Spacer()
                        RoundedRectangle(cornerRadius: 3)
                            .fill(soundEnabled ? RetroTheme.codexGreen.opacity(0.3) : RetroTheme.cardBg)
                            .frame(width: 28, height: 14)
                            .overlay(
                                Circle()
                                    .fill(soundEnabled ? RetroTheme.codexGreen : RetroTheme.textMuted)
                                    .frame(width: 10, height: 10)
                                    .offset(x: soundEnabled ? 6 : -6),
                                alignment: .center
                            )
                            .pixelBorder(color: RetroTheme.border.opacity(0.5), cornerRadius: 3)
                    }
                    .padding(.vertical, 3)
                }
                .buttonStyle(.plain)
            }

            // Claude Hooks
            settingSection("CLAUDE HOOKS") {
                HStack(spacing: 8) {
                    hookButton("INSTALL", color: RetroTheme.codexGreen) {
                        SettingsConfigurator.ensureHooksConfigured()
                    }
                    hookButton("REMOVE", color: RetroTheme.claudeOrange) {
                        SettingsConfigurator.removeHooks()
                    }
                    Spacer()
                }
            }

            // Codex Hooks
            settingSection("CODEX HOOKS") {
                HStack(spacing: 8) {
                    hookButton("INSTALL", color: RetroTheme.codexGreen) {
                        SettingsConfigurator.ensureCodexHooksConfigured()
                    }
                    hookButton("REMOVE", color: RetroTheme.claudeOrange) {
                        SettingsConfigurator.removeCodexHooks()
                    }
                    Spacer()
                }
            }

            // Voice Input — Doubao ASR
            settingSection("VOICE INPUT (DOUBAO ASR)") {
                VStack(alignment: .leading, spacing: 6) {
                    keyField("APP ID", text: $appIdText)
                    keyField("ACCESS TOKEN", text: $accessTokenText)
                    HStack {
                        Button {
                            VoiceInputService.shared.saveKey(appIdText, to: CodeIslandConstants.doubaoAppIdPath)
                            VoiceInputService.shared.saveKey(accessTokenText, to: CodeIslandConstants.doubaoAccessTokenPath)
                            apiKeySaved = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { apiKeySaved = false }
                        } label: {
                            Text(apiKeySaved ? "SAVED" : "SAVE")
                                .font(RetroTheme.pixelFont(size: 8, weight: .bold))
                                .foregroundStyle(apiKeySaved ? RetroTheme.codexGreen : RetroTheme.cyan)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill((apiKeySaved ? RetroTheme.codexGreen : RetroTheme.cyan).opacity(0.1))
                                )
                                .pixelBorder(color: (apiKeySaved ? RetroTheme.codexGreen : RetroTheme.cyan).opacity(0.3), cornerRadius: 3)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                }
            }

            Spacer()
        }
        .padding(12)
    }

    // MARK: - Helpers

    private func settingSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(RetroTheme.pixelFont(size: 8, weight: .bold))
                .foregroundStyle(RetroTheme.textMuted)
            content()
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(RetroTheme.cardBg.opacity(0.5))
                )
                .pixelBorder(color: RetroTheme.border.opacity(0.2), cornerRadius: 6)
        }
    }

    private var pixelDivider: some View {
        HStack(spacing: 2) {
            ForEach(0..<60, id: \.self) { i in
                Rectangle()
                    .fill(i % 2 == 0 ? RetroTheme.border : Color.clear)
                    .frame(width: 3, height: 1)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func keyField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(RetroTheme.pixelFont(size: 7))
                .foregroundStyle(RetroTheme.textMuted)
            SecureField("...", text: text)
                .font(RetroTheme.pixelFont(size: 9))
                .textFieldStyle(.plain)
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(RetroTheme.background.opacity(0.5))
                )
                .pixelBorder(color: RetroTheme.border.opacity(0.3), cornerRadius: 3)
        }
    }

    private func hookButton(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(RetroTheme.pixelFont(size: 8, weight: .bold))
                .foregroundStyle(color)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color.opacity(0.1))
                )
                .pixelBorder(color: color.opacity(0.3), cornerRadius: 3)
        }
        .buttonStyle(.plain)
    }

    private func colorForMode(_ mode: PermissionMode) -> Color {
        switch mode {
        case .observe: return RetroTheme.cyan
        case .alwaysAllow: return RetroTheme.codexGreen
        case .manual: return RetroTheme.claudeOrange
        }
    }

    private func descriptionForMode(_ mode: PermissionMode) -> String {
        switch mode {
        case .observe: return "watch only"
        case .alwaysAllow: return "auto-approve"
        case .manual: return "ask every time"
        }
    }
}
