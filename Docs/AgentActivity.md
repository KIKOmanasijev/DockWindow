# Agent Activity (beta)

Agent Activity is an opt-in island at the top of the screen. It shows each Claude Code or Codex session as a small doodle dog. It reports whether the session is working, needs you, has finished a turn, or is idle. It never approves tools or answers permission prompts. After a Claude Code turn finishes, it can send a follow-up note through a background hook; this is not a user message in the agent's transcript and does not count as approval. Codex sessions support observation and opening the host app only.

It's off by default. To turn it on, open **Settings › Beta** (Command-9). The same page has a **Play Demo** button that works without any agent.

## Design intent

- **Visual thesis:** a matte, near-black surface attached to the top edge, broad and quiet. Each session is a cute vector doodle dog in its own stable coat. Motion happens only when something actually happens.
- **Island layout, current:**
  - **Compact:** the lead dog, plus a second dog or "+N".
  - **All sessions:** reached with the ⌘ button or the arrows. Each row has a dog, title, project, status and ⌘ number, plus a "Clear finished" action.
  - **One session:**
    - agent icon, title and project;
    - your latest prompt;
    - status with its observed timing;
    - the live tool feed (running and recent tools);
    - the last reply;
    - a reply field (Claude Code) and an Open button for the app hosting the session.

  This replaces the earlier content plan below wherever the two differ.
- **Content plan:** the compact island shows dogs on the left wing and a status ring on the right. The expanded island shows, in this order:
  1. session dots, with ⌘ hints and arrows;
  2. title and project/branch;
  3. status;
  4. tool calls this turn;
  5. the last reply;
  6. observed metrics.

  There is no Researching/Reasoning/Writing/Reviewing strip, no inferred progress, and no reply or approval controls.
- **Interaction thesis:**
  - Hover intent (100 ms) opens the island, and a 240 ms exit grace closes it.
  - The shell springs open while the dog gives one small squash, with ears that lag by about 35 ms.
  - A halo slides between session dots.
  - The ring rotates only while work is observed.

All timing values are hypotheses taken from the two research handoffs. They have not been measured, and should be tuned on hardware.

## Architecture

Sources are in `Sources/DogBarCore/Features/AgentActivity`.

| File | Role |
| --- | --- |
| `AgentEvent.swift` | Compact wire event: decoding, validation, clamping |
| `AgentHookRelay.swift` | `DogBar --agent-hook claude\|codex`: reads hook JSON from stdin, keeps a few fields, sends one datagram, exits 0 |
| `AgentEventSocket.swift` | Unix datagram socket in `~/Library/Application Support/DogBar/AgentActivity/` (directory `0700`, socket `0600`) and its dispatch-source listener |
| `AgentActivityStore.swift` | Pure session state: transitions, tool grouping, slots, coats, stale/removal policy; `.git/HEAD` branch reader |
| `AgentActivityCenter.swift` | Live and demo stores (kept separate), coalescing, single-deadline expiry, selection, demo script |
| `AgentIslandGeometry.swift` | Notch/no-notch layout math; `AgentShortcutPolicy` for ⌘1–⌘9 |
| `AgentIslandController.swift` | Panel, click-through, hover, sleep/display changes, reduced motion, shortcut tap lifecycle |
| `AgentIslandView.swift` / `AgentDogView.swift` | SwiftUI island and the vector dog rig |
| `AgentShortcutTap.swift` | Keyboard tap that exists only while the island is open |
| `Settings/BetaSettingsPane.swift` | Opt-in, always-visible preference, connection status, demo, copyable hook setup |

The relay is the main `DogBar` executable in a different mode (`main.swift` checks for the argument before AppKit starts). Packaging is therefore unchanged: no extra binary, resource or signing step.

## Replies, Open, and sounds

- **Reply (Claude Code):** with **Reply from the island** on (the default), the Stop hook is installed with `asyncRewake: true` and a 1800-second timeout, and the relay runs with `--reply`.
  - The relay opens a private reply socket and reports the Stop with its path, then waits in the background. Claude Code never waits for it.
  - Typing in the island sends the text. The relay prints a labeled message to stderr and exits 2, which Claude Code documents as waking the session and showing the text to Claude as a system reminder.
  - A newer event for the session (for example a prompt typed in the terminal), turning the feature off, or Clear sends a cancel instead, and the relay exits 0.
  - The relay exits at once when DogBar isn't running.
  - The reply reaches Claude as a note from DogBar, not as a typed user message in the transcript.
  - Codex has no documented way to wake a finished session from the background, so Codex sessions get Open only.
- **Open:** every event carries the agent process's PID. DogBar walks up the process tree to the first regular app (Terminal, Ghostty, iTerm, VS Code, T3 Code…) and activates it. It doesn't try to pick the exact tab.
  - Sessions inside tmux or other detached multiplexers have no app ancestor, so they show no Open button.
- **Sounds:** short sine "bell" cues synthesized in memory and played quietly through `NSSound`: rising for **Needs you**, settling for **Turn finished**, low for **failed**. They play at most once every 2 seconds, never for tool calls, and are controlled by **Sounds** in Settings (on by default).

## Events

The client's own hook JSON never leaves the relay. Only these fields are forwarded:

- session ID;
- `cwd`;
- event name;
- tool name and tool call ID;
- `agent_id` and `agent_type`;
- notification type and message;
- `session_title`;
- `model`;
- `source` or `reason`;
- the API error type;
- `last_assistant_message` (from Stop and StopFailure).

Tool inputs are never forwarded. The prompt is forwarded clamped to its first 300 characters, so the island can show what each session is working on.

| Hook | Effect |
| --- | --- |
| SessionStart | Creates the session (Idle) |
| UserPromptSubmit | Working; starts the turn timer; resets this turn's tool counts |
| PreToolUse / PostToolUse / PostToolUseFailure | Tool groups, deduplicated by call ID (a start and its completion count once; failures are a subset). Answers a pending permission prompt (back to Working) |
| PermissionRequest; Notification `permission_prompt` or `elicitation_dialog` | Needs you |
| Notification `idle_prompt` | Working becomes Idle ("Waiting for your next prompt") |
| Stop | Turn finished; stores the last reply and the turn duration |
| StopFailure (Claude) | Turn ended with an error; stores the error type and text |
| Interrupt (Codex) | Idle ("Interrupted"); never treated as finished |
| SessionEnd | Removes the session |

**Ordering:** each event carries the time its hook ran. A status-changing event older than the session's current status is ignored. Tool events older than the current turn are also ignored. This covers out-of-order delivery from async hooks.

**Inactivity:** silence is never treated as "finished".
- Working or waiting sessions with no events for 4 hours become **No recent events**.
- Idle and finished sessions leave after 45 minutes.
- Stale sessions leave after 12 hours.

The center schedules a single wake-up at the next deadline. It does not poll.

**Subagents:** events that carry an `agent_id` are kept under their own session ID and counted (shown as "includes subagents"). They are never mapped to another session. A subagent tool event after Stop does not reopen the turn.

## Setup

Settings › Beta has **Install** and **Remove** for each agent. DogBar changes a config file only when one of these buttons is pressed.

- **Install** merges DogBar's handlers into the file, next to whatever is already there. Other settings and hooks are left as they are. The file is created if it's missing.
- **Remove** takes out only the handlers whose command runs `--agent-hook <client>`. Groups and events that end up empty are dropped.
- **Saving:** the previous file is copied to `<file>.dogbar-backup` before every write. Writes are atomic, and permissions and symlinks are kept.
- **Unparseable files:** if a file can't be parsed as a JSON object, DogBar refuses to change it.
- **Moved app:** if DogBar's hooks point at another copy of the app (for example after moving it), the status shows "Installed for another copy" and offers **Update**.
- **Manual setup:** the copyable JSON is still available under **Show configuration**.

Per agent:

- **Claude Code** (`~/.claude/settings.json`):
  - Covers ten events.
  - Every hook except SessionEnd uses `async: true`, so Claude Code never waits.
  - SessionEnd runs in the foreground with a 2-second timeout.
  - The relay prints nothing, so it adds no context and makes no decision.
- **Codex** (`~/.codex/hooks.json`):
  - Covers eight events and runs in the foreground (timeout 5 seconds; SessionEnd and Interrupt 2 seconds).
  - Codex requires JSON stdout for Stop, so the relay prints `{}` only there.
  - Hooks must be reviewed and trusted with `/hooks`. Codex asks again whenever the command changes.
  - Hooks defined inline in `config.toml` are detected but never edited.

**Uninstalling:** macOS gives apps no uninstall event, so DogBar can't clean up after it has been deleted. Each command is guarded: `test -x '<DogBar>' && exec '<DogBar>' --agent-hook <client> || true`. Once the app is gone, the hook does nothing and exits 0. To leave the config files clean, use **Remove** before deleting DogBar.

Sources: code.claude.com/docs/en/hooks and the Codex hooks reference (learn.chatgpt.com/docs/hooks), both read on 2026-11-02. App-server attachment was not used: it doesn't observe independently started CLI sessions.

## Native behavior

- **Panel:** a nonactivating `NSPanel` at status-bar level that never becomes key. It has a fixed maximum frame, and the shape animates inside it.
  - `ignoresMouseEvents` stays on except while the pointer is over the visible shape, using global and local monitors plus an in-panel hover fallback.
  - Clicks anywhere else, including the transparent margins, reach the app underneath.
  - A click outside the open island closes it.
- **Notched displays:** the compact shape is the camera housing plus two wings. Extra dogs widen both wings, so no dog is drawn under the camera. Displays without a notch get a short centered pill.
- **Display changes:** the island collapses instantly and re-anchors.
- **Screens sleep:** the island hides.
- **Hidden or off:** the SwiftUI tree is released, so nothing renders.
- **Feature off:** no socket, no monitors and no panel. Only settings subscriptions remain.
- **Reduced motion:** both the macOS setting and DogBar's own Reduce animations are honored, and changes apply live. Geometry changes become instant, the dog stays still and the ring becomes a static arc.
- **⌘1–⌘9 and Esc:** a keyboard tap exists only while the island is open.
  - It takes Command-digit presses only while the pointer is over the shape.
  - Escape is observed and closes the island, but still reaches the frontmost app.
  - Without Accessibility permission the tap is unavailable, the ⌘ hint is hidden, and the dots and arrows still work.

## Verification

- **Unit tests:** `swift test --filter Agent` covers validation, the relay mapping, store transitions, dedupe, ordering, slots, expiry, socket delivery and rejection, setup JSON, geometry, the shortcut policy, settings defaults, and keyframe bounds.
- **Stills:** `DOGBAR_RENDER_DIR=<dir> swift test --filter AgentIslandRenderTests` renders still images of the island and the dog gallery.
- **Relay without a live agent:** pipe a hook payload into `DOGBAR_AGENT_SOCKET=/tmp/x.sock .build/debug/DogBar --agent-hook claude` while something listens on that socket.

Not yet verified:
- live Claude Code or Codex sessions sending real hooks;
- motion on 60 Hz and 120 Hz hardware;
- notch and external displays;
- VoiceOver;
- energy use.

Still images can't show motion.
