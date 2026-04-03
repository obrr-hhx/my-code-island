# Code Island

A macOS native app that turns your MacBook's notch into a control center for monitoring Claude Code sessions. Inspired by [Vibe Island](https://vibeisland.app/).

## Features

- **Notch Integration** — Panel seamlessly blends with the MacBook notch using a pure-black background, extending left and right as visible "wings"
- **Real-time Session Monitoring** — Tracks Claude Code's query loop lifecycle: idle → running → tool use → idle
- **Permission Approval from Notch** — When Claude Code asks for permission, approve or deny directly from the notch panel without switching to the terminal
- **8-bit Retro Aesthetic** — Pixel fonts, character scatter animations, dot wave backgrounds, CRT scanlines, glitch text effects
- **Clawd Mascot** — Pixel art Claude Code mascot faithfully reproduced from source (Unicode block art → sub-pixel grid, height-doubled for correct aspect ratio). Frame-based animation system (60ms/frame) with click-triggered sequences (jump wave, look around) and state-driven idle behavior
- **Chiptune Sound Effects** — 8-bit synthesized sounds for permission alerts, approvals, denials, and notifications
- **Three Permission Modes** — Observe (default), Always Allow (bypass), Manual (approve everything)
- **Zero Dependencies** — Pure Swift, no Electron, no external frameworks. ~1.5MB total binary size, sub-50MB RAM

## Quick Start

```bash
# Build everything
make bundle

# Run
make run
# or
open .build/CodeIsland.app
```

On first launch, Code Island automatically:
1. Creates a Unix domain socket at `/tmp/code-island.sock`
2. Writes hook entries to `~/.claude/settings.json` for all relevant events
3. Shows the notch panel and menu bar icon

**Note:** Hooks hot-reload — no need to restart Claude Code sessions.

## Requirements

- macOS 14+ (Sonoma)
- Apple Silicon (arm64)
- Swift 6.1+ (via Xcode or CommandLineTools)
- MacBook with notch (falls back to floating bar on external displays)

## Architecture

```
Claude Code                    Code Island
┌────────────┐    stdin/stdout    ┌───────────────┐
│ Hook fires │───────────────────>│ Bridge Binary  │
│            │                    │ (code-island-  │
│ PreToolUse │                    │  bridge)       │
│ PostToolUse│    Unix Socket     │       │        │
│ Stop       │    /tmp/code-      │       ▼        │
│ Permission │    island.sock     │ Socket Server  │
│ Request    │                    │       │        │
│ Subagent*  │                    │       ▼        │
│ UserPrompt │                    │   AppState     │
│ Notification                    │       │        │
└────────────┘                    │       ▼        │
                                  │  Notch Panel   │
                                  │  (SwiftUI)     │
                                  └───────────────┘
```

### Components

| Component | Path | Purpose |
|-----------|------|---------|
| **Bridge Binary** | `Sources/Bridge/main.swift` | Lightweight CLI invoked by Claude Code hooks. Reads JSON from stdin, forwards to Unix socket, returns response to stdout |
| **Socket Server** | `Sources/CodeIsland/Services/SocketServer.swift` | Listens on Unix domain socket, routes events to AppState |
| **AppState** | `Sources/CodeIsland/App/AppState.swift` | Central state management. Handles all hook events, manages session lifecycle and permission flow |
| **Notch Panel** | `Sources/CodeIsland/Notch/` | `ClickThroughPanel` positioned over the notch with wings layout (content on left/right of notch gap) |
| **Settings Configurator** | `Sources/CodeIsland/Services/SettingsConfigurator.swift` | Auto-writes hook entries to `~/.claude/settings.json` |

### Session Status Lifecycle

Status follows Claude Code's query loop exactly:

```
UserPromptSubmit → RUNNING        (loop starts)
PreToolUse       → RUNNING "Bash" (tool starting)
PostToolUse      → RUNNING        (tool done, loop continues)
SubagentStart    → RUNNING        (background agent launched)
SubagentStop     → RUNNING        (background agent done)
PermissionRequest→ WAITING        (needs user approval)
Stop             → IDLE           (loop ended)
```

### Permission Flow

When Claude Code asks for user permission:

1. `PermissionRequest` hook fires → bridge sends to app via socket
2. App shows approval UI in notch panel (bridge blocks waiting for response)
3. User clicks Allow/Deny in the panel
4. App sends decision back through socket → bridge outputs JSON to stdout
5. Claude Code reads the decision and continues (or stops)

Output format (must include `hookEventName` for Zod validation):
```json
{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}
```

### Permission Modes

| Mode | PreToolUse | PermissionRequest |
|------|-----------|-------------------|
| **Observe** (default) | Update UI status only | Show approval UI, block for user decision |
| **Always Allow** | Update UI status only | Auto-return `allow` immediately |
| **Manual** | Update UI status only | Show approval UI, block for user decision |

Switch modes via menu bar icon → Permission Mode, or click the mode badge in the expanded panel header.

## Project Structure

```
Sources/
├── Bridge/main.swift                    # Bridge CLI binary
├── Shared/
│   ├── Constants.swift                  # Socket path, config paths
│   └── SocketProtocol.swift             # Wire protocol, message types, hook output formats
└── CodeIsland/
    ├── App/
    │   ├── CodeIslandApp.swift           # @main entry point
    │   ├── AppDelegate.swift             # Menu bar, services setup
    │   └── AppState.swift                # Central state + event handling
    ├── Models/
    │   ├── Session.swift                 # ClaudeSession, TrackedSession, SessionStatus
    │   ├── HookEvent.swift               # HookEvent, PermissionRequest
    │   └── NotchGeometry.swift           # Notch dimensions for wing layout
    ├── Notch/
    │   ├── NotchPanelController.swift    # NSPanel positioning + notch geometry
    │   ├── ClickThroughPanel.swift       # NSPanel subclass for click-through
    │   ├── NotchContentView.swift        # Root SwiftUI view
    │   ├── NotchCollapsedView.swift      # Collapsed: Clawd + status dots
    │   └── NotchExpandedView.swift       # Expanded: sessions + permissions
    ├── Views/
    │   ├── SessionCardView.swift         # Session card with status
    │   ├── PermissionPromptView.swift    # Allow/Deny UI
    │   └── MenuBarView.swift             # Menu bar dropdown
    ├── Services/
    │   ├── SocketServer.swift            # Unix domain socket listener
    │   ├── SessionWatcher.swift          # Polls ~/.claude/sessions/
    │   ├── HookEventRouter.swift         # Routes socket events to AppState
    │   └── SettingsConfigurator.swift     # Auto-configures Claude Code hooks
    ├── Theme/
    │   ├── RetroTheme.swift              # Colors, fonts, view modifiers
    │   ├── ClawdView.swift               # Pixel art Clawd mascot
    │   ├── CharacterScatterView.swift    # ASCII scatter background
    │   ├── DotWaveView.swift             # Sine wave dot animation
    │   └── GlitchTextView.swift          # Character-by-character glitch text
    └── Audio/
        └── ChiptuneEngine.swift          # 8-bit sound synthesis via AVAudioEngine
```

## Build

```bash
# Full build (app + bridge + .app bundle)
make bundle

# Just the bridge
make bridge

# Just the app
make app

# Clean
make clean
```

## Troubleshooting

**Hooks not working?**
- Check `~/.claude/settings.json` has entries pointing to the bridge binary
- Restart Claude Code session (hooks load at session start)
- Run `make bundle` to ensure bridge binary path is correct

**Panel not visible?**
- Check menu bar for the sparkles (✦) icon
- Click it → Show/Hide Panel

**Buttons not clickable?**
- The panel uses `ClickThroughPanel` (NSPanel subclass) to accept clicks without app activation
- If buttons still don't respond, click the panel area first to make it key window

**Remove hooks:**
- Menu bar → Remove Hooks, or manually delete the `code-island-bridge` entries from `~/.claude/settings.json`
