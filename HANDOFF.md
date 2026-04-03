# Code Island — Handoff Document

## What Was Built

A macOS native app (27 Swift files, ~1.5MB binary) that monitors Claude Code sessions from the MacBook notch. Clone of [Vibe Island](https://vibeisland.app/) with 8-bit retro aesthetic. Includes a `tools/clawd_preview.swift` script for quick iteration on the Clawd pixel art without rebuilding the full app.

## Key Decisions & Why

### IPC: Unix Domain Socket + Bridge Binary
- Claude Code hooks execute **command-line binaries** — they spawn a process, write JSON to stdin, read stdout
- Bridge binary (`code-island-bridge`) is the thin CLI that hooks invoke; it forwards events to the main app via Unix socket at `/tmp/code-island.sock`
- Bridge blocks for `PermissionRequest` events (waiting for user decision), fire-and-forget for all others

### Notch Positioning
- macOS has **no Dynamic Island API** — the notch is just a physical black cutout
- We place a black-background `NSPanel` over the notch area using `auxiliaryTopLeftArea`/`auxiliaryTopRightArea` to compute exact notch position (179pt wide, 32pt tall on 14" MBP)
- Panel uses `CGShieldingWindowLevel` to render above the menu bar
- Collapsed view has "wings" layout: content on left/right of notch, gap in the middle matching notch width
- `ClickThroughPanel` (NSPanel subclass) with `canBecomeKey = true` is **required** for SwiftUI buttons to work in a non-activating panel

### Session Status Model
- Mirrors Claude Code's `query()` async generator loop in `QueryEngine.ts` exactly
- `UserPromptSubmit` starts the loop → `Stop` ends it
- Everything between is "running" — **no timeouts, no heuristics**, pure event-driven
- `SubagentStart`/`SubagentStop` included so background agents don't cause false idle
- Earlier attempts used a 5s idle fallback timer after `PostToolUse` — this was **removed** as unreliable. The correct signal for idle is always the `Stop` event
- Status enum is simple: `.idle`, `.running(String?)` (optional tool name), `.waitingPermission`

### Clawd Mascot Pixel Art
- Faithfully reproduced from Claude Code source `src/components/LogoV2/Clawd.tsx`
- Original uses Unicode quarter-block characters (▛▜▙▘█▐▌ etc.), each mapping to a 2×2 sub-pixel grid
- Sub-pixel rows are **height-doubled** to compensate for terminal char aspect ratio (~1:2 width:height) — without this, Clawd looks too wide/flat
- Head row is shifted left by 1 sub-pixel to align with body (original has 8-char head vs 9-char body)
- Eye spacing is fixed at gap=7 across all poses (default: col 5,12; lookLeft: col 4,11; lookRight: col 6,13)
- Use `swift tools/clawd_preview.swift` to iterate on the pixel grid without rebuilding the app

### Clawd Animation System
- Frame-based (60ms/frame), matching Claude Code's `AnimatedClawd.tsx`
- **Click-triggered**: tap Clawd to randomly play JUMP_WAVE or LOOK_AROUND
  - `JUMP_WAVE`: crouch(offset=1, 2f) → arms-up(3f) → default(1f) → crouch(2f) → arms-up(3f) → default(1f)
  - `LOOK_AROUND`: look-right(5f) → look-left(5f) → default(1f)
- **State-driven idle**: frequency adapts to app state
  - alert (permission waiting): bounce every 0.8s
  - thinking (running): look around every 2s
  - idle: occasional glance every 4s
- Crouch effect: offset=1 shifts Clawd down by 3×pixelSize, feet clipped by container

### Hook Output Format
- **Critical:** `hookSpecificOutput` must include `hookEventName` field matching the event type, or Claude Code's Zod schema validation rejects the entire output
- `PermissionRequest` uses `{ decision: { behavior: "allow" } }` format (different from PreToolUse's `{ permissionDecision: "allow" }`)
- Found this by reading `src/types/hooks.ts:50-166` in Claude Code source — the `syncHookResponseSchema` Zod union

### Permission Modes
- **Observe** (default): PreToolUse = observe only, PermissionRequest = show UI and block
- **Always Allow**: PermissionRequest auto-returns `allow`
- **Manual**: Same as Observe (both show UI)
- Mode switching via menu bar submenu or clickable badge in expanded panel header

## Known Issues / TODO

### Not Yet Implemented
- **Terminal jumping** — clicking a session card should focus the terminal where that Claude Code session runs. Vibe Island supports 13+ terminal emulators. Would need AppleScript/Accessibility API per terminal app
- **Plan review** — showing markdown-rendered plans with inline diffs before approval
- **Sound customization** — custom sound pack support
- **Landing page** — the marketing website with pixel animations
- **Multi-agent support** — currently only Claude Code; Codex CLI, Gemini CLI, Cursor, OpenCode, Droid would each need their own hook mechanism research

### Known Bugs / Gotchas
- Hooks hot-reload in Claude Code — no need to restart sessions after configuring
- Sessions from `~/.claude/sessions/` that predate hook configuration show as "idle" until they emit their first hook event
- The `SessionWatcher` polls every 5 seconds and may include stale sessions whose processes have died between polls
- Menu bar "Remove Hooks" doesn't force-reload hooks in running Claude Code sessions
- System notifications were removed from permission requests (only the notch panel + 8-bit sound alert). If you need them back, add `sendNotification()` in `AppState.handlePermissionRequest()`

### Architecture Improvements
- `SocketServer.shared.onEvent` is fetched via `DispatchQueue.main.async` + `SocketServer.shared` access pattern — works but is technically a MainActor isolation boundary that relies on runtime behavior. Would be cleaner with a proper actor-based design
- Bridge binary path is resolved at runtime by `SettingsConfigurator` — if the app is moved after hooks are configured, hooks break. Should detect this on launch and re-configure

## File Quick Reference

| Need to change... | Look at... |
|---|---|
| Hook event handling logic | `AppState.swift:handleEvent()` |
| Which events are hooked | `SettingsConfigurator.swift:hookEvents` |
| Bridge output format | `SocketProtocol.swift` (output structs) + `Bridge/main.swift` (switch on event type) |
| Notch positioning | `NotchPanelController.swift:frameForPanel()` |
| Notch collapsed layout | `NotchCollapsedView.swift` (wing layout) |
| Permission UI | `PermissionPromptView.swift` |
| Clawd pixel art grid | `ClawdView.swift:ClawdSprite.grid()` — or iterate fast with `swift tools/clawd_preview.swift` |
| Clawd animation sequences | `ClawdView.swift:ClawdAnimations` |
| Clawd eye spacing | `ClawdView.swift:ClawdSprite.grid()` — keep gap=7 across all poses |
| Sound effects | `ChiptuneEngine.swift` |
| Colors/fonts | `RetroTheme.swift` |
| Socket wire protocol | `SocketProtocol.swift:SocketProtocol` + message types |

## Claude Code Hook System Reference

Hooks are configured in `~/.claude/settings.json` under the `hooks` key. Each event maps to an array of hook entries.

**Events we use:**
| Event | When | Blocking? |
|-------|------|-----------|
| `UserPromptSubmit` | User sends a message | No |
| `PreToolUse` | Before each tool call | No (observe only) |
| `PostToolUse` | After each tool call | No |
| `PermissionRequest` | Claude wants user approval | **Yes** — bridge blocks |
| `SubagentStart` | Background agent launched | No |
| `SubagentStop` | Background agent finished | No |
| `Stop` | Main agent turn ended | No |
| `Notification` | Claude sends a notification | No |

**Hook input** (JSON on stdin):
```json
{
  "session_id": "uuid",
  "hook_event_name": "PermissionRequest",
  "tool_name": "Bash",
  "tool_input": {"command": "..."},
  "cwd": "/path/to/project",
  "permission_mode": "ask"
}
```

**Hook output** (JSON on stdout, must pass Zod validation):
```json
{
  "hookSpecificOutput": {
    "hookEventName": "PermissionRequest",
    "decision": {"behavior": "allow"}
  }
}
```

Key source files in Claude Code:
- `src/types/hooks.ts:50-166` — Zod schema for hook output validation (`syncHookResponseSchema`)
- `src/utils/hooks.ts:399-450` — `parseHookOutput()` function
- `src/utils/hooks.ts:645-672` — per-event-type result extraction (PermissionRequest at line 657)
- `src/hooks/toolPermission/PermissionContext.ts:220-263` — PermissionRequest hook consumption
- `src/QueryEngine.ts:675-1049` — the main query loop that generates hook events
- `src/components/LogoV2/Clawd.tsx` — Clawd pixel art (Unicode block chars + color scheme)
- `src/components/LogoV2/AnimatedClawd.tsx` — Frame-based animation system (60ms/frame, JUMP_WAVE, LOOK_AROUND)
- `src/utils/theme.ts` — `clawd_body: rgb(215,119,87)`, `clawd_background: rgb(0,0,0)`
