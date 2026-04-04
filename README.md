# Code Island

A macOS native app that turns your MacBook's notch into a unified control center for all your AI coding agents. Monitor Claude Code and Codex CLI sessions, approve permissions, and use voice input to talk to your agents — all from the notch.

Inspired by [Vibe Island](https://vibeisland.app/), built with pure Swift, zero dependencies.

## Features

- **Unified Agent Platform** — Monitor both Claude Code and Codex CLI sessions from a single panel. Each session shows its agent type (CC/CX), terminal app (iTerm/Ghostty/Warp/VSCode/etc.), and real-time status
- **Voice Input** — Click the mic button on any session card, speak, and your words are transcribed by Doubao Seed-ASR 2.0 and automatically typed into the corresponding terminal. No keyboard needed
- **Notch Integration** — Panel blends seamlessly with the MacBook notch using a pure-black background, creating a Dynamic Island effect on macOS
- **Permission Approval** — Approve or deny Claude Code permission requests directly from the notch without switching windows
- **8-bit Retro Aesthetic** — Pixel fonts, dot wave backgrounds, CRT scanlines, glitch text, character scatter animations
- **Clawd Mascot** — Pixel art Claude mascot with state-driven animations: sleeping, thinking, tool use, error shake, celebration, sweeping, juggling subagents
- **Chiptune Audio** — 8-bit synthesized sound effects for all events (permission alerts, approvals, errors, celebrations, sleep/wake)
- **Terminal Detection** — Automatically detects which terminal each session runs in via PID chain traversal, including tmux client detection

## Quick Start

```bash
make run
```

On first launch, Code Island automatically:
1. Creates a Unix domain socket at `/tmp/code-island.sock`
2. Configures hooks in `~/.claude/settings.json` and `~/.codex/hooks.json`
3. Shows the notch panel and menu bar icon

Hooks hot-reload — no need to restart running sessions.

### Voice Input Setup

1. Open the settings panel (gear icon in expanded notch)
2. Enter your Volcengine App ID and Access Token ([get them here](https://console.volcengine.com/speech/app))
3. Click Save
4. Click the mic button (◎) on any session card to start talking

## Requirements

- macOS 14+ (Sonoma)
- Apple Silicon (arm64)
- Swift 6.1+ (via Xcode or CommandLineTools)
- MacBook with notch (falls back to floating bar on external displays)

## Technical Architecture

### Overview

Code Island is a ~6000 line Swift app (33 source files) built with raw `swiftc` — no Xcode project, no SPM, no external dependencies. It compiles to a 2.8MB binary.

```
Claude Code / Codex CLI              Code Island App
┌──────────────────────┐             ┌─────────────────────────┐
│  Hook fires          │   stdin     │  Bridge Binary (279KB)  │
│  (PreToolUse,        │────────────>│  Reads JSON, forwards   │
│   PermissionRequest, │             │  via Unix socket        │
│   Stop, etc.)        │   stdout    │         │               │
│                      │<────────────│         ▼               │
└──────────────────────┘             │  SocketServer           │
                                     │  (length-prefixed msg)  │
                                     │         │               │
  ~/.claude/sessions/  ──poll 5s──>  │         ▼               │
  ~/.codex/sessions/   ──poll 5s──>  │  AppState (@Observable) │
                                     │  ├─ sessions[]          │
                                     │  ├─ permissions[]       │
                                     │  └─ clawdBehavior       │
                                     │         │               │
                                     │         ▼               │
                                     │  Notch Panel (SwiftUI)  │
                                     │  ├─ SessionCardView     │
                                     │  ├─ VoiceListeningBar   │
                                     │  └─ SettingsView        │
                                     └─────────────────────────┘
```

### IPC: Bridge Binary + Unix Socket

Claude Code hooks execute **command-line binaries** — they spawn a process, pipe JSON to stdin, and read stdout. Code Island uses a thin bridge binary (`code-island-bridge`, 279KB) as the hook target.

**Wire protocol:** Length-prefixed JSON over Unix domain socket (`/tmp/code-island.sock`). Each message is `[4 bytes big-endian length][N bytes UTF-8 JSON]`. Blocking events (PermissionRequest, PreToolUse) use a semaphore to hold the bridge process until the user responds; other events fire-and-forget with an immediate ACK.

The bridge binary accepts a `--source` flag (`--source codex`) to tag events by agent type, enabling unified multi-agent routing through a single socket.

### Multi-Agent Session Discovery

**Claude Code sessions:** Polls `~/.claude/sessions/*.json` every 5 seconds. Files are named by PID (e.g., `84907.json`) and contain `sessionId`, `cwd`, `pid`, `startedAt`.

**Codex CLI sessions:** Scans `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`. Reads only the first line (`session_meta`) for session ID and working directory. Only scans today + yesterday to limit I/O. Sessions are marked alive based on recent hook activity (within 60s).

Both sources merge into a unified `TrackedSession` array in `AppState`.

### Terminal Detection

Each session card shows which terminal app it runs in (iTerm, Ghostty, Warp, VS Code, Cursor, etc.). Detection works by walking the PID chain:

1. **Direct chain:** Session PID → parent → parent → ... → find a known terminal bundle ID
2. **Tmux fallback:** If the chain hits `tmux-server` (PID parent = launchd), the session is in tmux. We then:
   - Get the session's TTY via `ps -o tty=`
   - Verify it's a tmux pane via `tmux list-panes`
   - Get tmux client PIDs via `tmux list-clients`
   - Walk each client's PID chain to find the terminal app

Terminal names are cached on `TrackedSession` and resolved once per session.

### Voice Input: Doubao Seed-ASR 2.0

Voice input uses Bytedance's Volcengine streaming ASR API via a **binary WebSocket protocol**.

**Protocol details:**
- Endpoint: `wss://openspeech.bytedance.com/api/v3/sauc/bigmodel`
- Auth: 4 HTTP headers (`X-Api-App-Key`, `X-Api-Access-Key`, `X-Api-Resource-Id`, `X-Api-Connect-Id`)
- Wire format: 4-byte binary header + 4-byte sequence + 4-byte payload size + gzip-compressed payload
- Audio: 16kHz mono 16-bit PCM, sent in 100ms chunks (3200 bytes), gzip-compressed per packet
- Responses: JSON with `utterances[]` containing `definite` (finalized) and pending text segments

**Audio capture:** `AVAudioEngine` with a tap on the input node in mono float format at hardware sample rate (44.1kHz on MacBook), downsampled to 16kHz 16-bit PCM via simple decimation.

**Text injection:** After transcription completes, text is sent to the terminal via AppleScript. iTerm2 uses `write text` (works across screens/focus), Terminal.app uses `do script`, and other terminals fall back to clipboard paste (`Cmd+V` via System Events). The target terminal is determined by the session's PID chain.

### Notch Panel

macOS has no Dynamic Island API. The notch is just a physical black cutout. Code Island places a black-background `NSPanel` at `CGShieldingWindowLevel` over the notch area, using `auxiliaryTopLeftArea`/`auxiliaryTopRightArea` to compute exact notch position. The panel is wider than the notch with "wings" on each side for content.

`NSHostingView.sizingOptions` is set to empty to prevent recursive layout crashes when SwiftUI tries to auto-resize the borderless panel.

### Chiptune Audio Engine

All sound effects are synthesized in real-time using `AVAudioEngine` + `AVAudioPlayerNode`. Waveforms (square, triangle, sawtooth, noise) are generated sample-by-sample at 44.1kHz with volume envelopes (attack/sustain/release). No audio files — everything is computed from frequency/duration note sequences.

## Resource Consumption

| Metric | Value |
|--------|-------|
| App binary | 2.5MB |
| Bridge binary | 279KB |
| Total .app bundle | ~3MB |
| RAM usage | ~53MB |
| Source files | 33 Swift files |
| Lines of code | ~6000 |
| External dependencies | 0 |
| Frameworks used | AppKit, SwiftUI, AVFoundation, ApplicationServices (all system) |
| CPU at idle | <0.1% |
| Disk I/O | Polls sessions directory every 5s |

## Project Structure

```
Sources/
├── Bridge/main.swift                    # Bridge CLI binary (hook target)
├── Shared/
│   ├── Constants.swift                  # Paths, AgentType enum
│   └── SocketProtocol.swift             # Wire protocol, message types
└── CodeIsland/
    ├── App/
    │   ├── CodeIslandApp.swift           # @main entry point
    │   ├── AppDelegate.swift             # Menu bar, services init
    │   └── AppState.swift                # Central state + event routing
    ├── Models/
    │   ├── Session.swift                 # ClaudeSession, TrackedSession, terminal detection
    │   ├── HookEvent.swift               # HookEvent, PermissionRequest, UserQuestion
    │   └── NotchGeometry.swift           # Notch dimensions for wing layout
    ├── Notch/
    │   ├── NotchPanelController.swift    # NSPanel positioning + animation
    │   ├── ClickThroughPanel.swift       # NSPanel/NSHostingView subclasses
    │   ├── NotchContentView.swift        # Root view (collapsed/expanded switch)
    │   ├── NotchCollapsedView.swift      # Collapsed: Clawd + status dots
    │   └── NotchExpandedView.swift       # Expanded: sessions + voice bar + settings
    ├── Views/
    │   ├── SessionCardView.swift         # Session card with agent/terminal badges, mic button
    │   ├── PermissionPromptView.swift    # Allow/Deny permission UI
    │   ├── UserQuestionView.swift        # AskUserQuestion UI
    │   ├── SettingsView.swift            # Settings panel (permissions, hooks, voice API keys)
    │   └── MenuBarView.swift             # Menu bar dropdown
    ├── Services/
    │   ├── SocketServer.swift            # Unix domain socket listener
    │   ├── SessionWatcher.swift          # Polls Claude + Codex session dirs
    │   ├── HookEventRouter.swift         # Routes socket events → AppState
    │   ├── SettingsConfigurator.swift     # Auto-configures Claude + Codex hooks
    │   ├── TerminalJumper.swift          # Jump to terminal via PID/tmux
    │   ├── TerminalTyper.swift           # Type text into terminal via AppleScript
    │   └── VoiceInputService.swift       # Doubao ASR WebSocket + AVAudioEngine
    ├── Theme/
    │   ├── RetroTheme.swift              # Colors, pixel fonts, view modifiers
    │   ├── ClawdView.swift               # Pixel art mascot + animations + particles
    │   ├── ClawdIcon.swift               # App/menu bar icon
    │   ├── DotWaveView.swift             # Sine wave dot animation
    │   ├── GlitchTextView.swift          # Glitch text effect
    │   └── CharacterScatterView.swift    # ASCII scatter background
    └── Audio/
        └── ChiptuneEngine.swift          # 8-bit waveform synthesis
```

## Build

```bash
make run      # Build everything and launch
make bundle   # Build app + bridge + .app bundle
make app      # Just the app binary
make bridge   # Just the bridge binary
make clean    # Remove build artifacts
```

## Troubleshooting

**Hooks not working?** Check `~/.claude/settings.json` has entries pointing to the bridge binary. Run `make bundle` to ensure the path is correct. Hooks hot-reload in running sessions.

**Voice input not working?** Ensure App ID and Access Token are saved in settings. Grant microphone permission when prompted. Check that the Volcengine "Doubao-流式语音识别" service is enabled.

**Panel not visible?** Check menu bar for the Code Island icon. Click → Show/Hide Panel.

**Text not typing into terminal?** iTerm2 uses AppleScript `write text` (works across screens). Other terminals use clipboard paste — grant Accessibility permission in System Settings if needed.

**Remove hooks:** Settings panel → Remove buttons, or menu bar → Remove Hooks.
