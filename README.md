# ClaudeNext

A macOS menu bar app that answers Claude Code's permission prompts.

When Claude Code wants to run a command, edit a file, or call an MCP tool, the
request drops out of the menu bar in a Claude-styled panel with **Deny**,
**Always allow** and **Allow**, plus a field for telling Claude what to do
instead. Your terminal stays where it is.

```
       ✳ ← menu bar
  ┌──────────────────────────────────────────────┐
  │ ● Claude wants to run a command       [Bash] │
  │   ~/code/my-project                          │
  ├──────────────────────────────────────────────┤
  │ ┌──────────────────────────────────────────┐ │
  │ │ npm run build --watch                    │ │
  │ └──────────────────────────────────────────┘ │
  │ Build the project and keep rebuilding        │
  ├──────────────────────────────────────────────┤
  │ ┌ Tell Claude what to do differently…      ┐ │
  │ └──────────────────────────────────────────┘ │
  │ [Deny esc]        [Always allow ⌘A] [Allow ↩]│
  │ Always allow adds  Bash(npm run:*)           │
  └──────────────────────────────────────────────┘
```

Requires macOS 14+ and the Swift toolchain (`xcode-select --install`).

## Install

```bash
git clone https://github.com/zhenweiding-dev/Claudenext.git
cd Claudenext
./install.sh
```

That builds the app into `~/Applications/ClaudeNext.app`, copies the hook to
`~/.claudenext/`, registers it as a `PreToolUse` hook in
`~/.claude/settings.json`, and launches it.

Restart any running Claude Code session afterwards so it reloads the hook, then
ask Claude to run something.

`./uninstall.sh` reverses all of it and leaves your rules alone.

## How it works

Claude Code fires a `PreToolUse` hook before every tool call.
`claudenext-hook.py` reads the call and resolves it in this order:

1. **Not an intercepted tool** → prints nothing, Claude Code prompts as usual.
2. **Matches a saved rule** → decided instantly, no UI.
3. **Otherwise** → `POST /ask` to the app on `127.0.0.1:4471`. The HTTP request
   stays open, and that is what blocks Claude Code until you answer.
4. **App not running, or you never answered** → prints nothing, Claude Code
   prompts as usual.

The fallback is always silence, never approval. If ClaudeNext is closed, wedged,
or times out, you get the normal terminal prompt — it cannot fail open.

## Controls

| Action | |
|---|---|
| `↩` | Allow once |
| `⌘A` | Always allow — saves the suggested rule |
| `esc` | Deny |
| `⌥` + Deny | Always deny — saves the rule to the deny list |
| Type a message, then `↩` | Deny, and hand the text to Claude as the reason |
| `⌘↑` / `⌘↓` | Move between stacked requests |
| Click the icon | Open the panel: pending requests, or recent activity |
| Right-click the icon | Pause, open rules, open config, quit |

A message typed into the field is passed to Claude as
`permissionDecisionReason`, so "use pnpm, not npm" reaches the model the same
way it would if you had typed it into the terminal prompt.

Clicking away parks a request rather than answering it — the menu bar icon turns
orange and shows a count.

## Several sessions at once

Every Claude Code session gets its own blocking connection, so parallel
sessions work. When more than one request is waiting they are **all shown at
once**, stacked as scrollable cards with their own buttons and message field —
answer them in whatever order you like, not oldest first.

One card is focused at a time and owns the keyboard; `⌘↑` / `⌘↓` (or the
chevrons in the header, or a click) move the focus, and the list scrolls to
follow. Unfocused cards hide their key hints so it stays obvious what `↩` will
hit. The panel grows to fit two cards and scrolls beyond that, capped so it
never runs off the bottom of the screen.

Remembered rules are per project, so two sessions in different projects write
to their own `.claude/claudenext.json` and never collide.

## Rules

"Always allow" appends to `<project>/.claude/claudenext.json`:

```json
{
  "allow": ["Bash(npm run:*)", "Edit(src/**)"],
  "deny": ["Bash(git push:*)"]
}
```

`~/.claudenext/rules.json` holds the same shape and applies everywhere. Deny
rules are checked first and win over allow rules. Supported forms:

| Rule | Matches |
|---|---|
| `Bash` | every Bash call |
| `Bash(npm run:*)` | commands starting with `npm run` |
| `Bash(ls -la)` | exactly that command |
| `Edit(src/**)` | anything under `src/` |
| `Write(/etc/hosts)` | one absolute path |
| `Read(~/notes/*.md)` | `~` expands |
| `WebFetch(domain:docs.python.org)` | that host |
| `mcp__github__*` | every tool on that MCP server |

These are ClaudeNext's own rules, deliberately separate from
`.claude/settings.json`. A `PreToolUse` hook runs *before* Claude Code checks
its own permission list, so rules living there would not stop this panel from
appearing.

## Config

`~/.claudenext/config.json` — the app reads `port`, `sound`, `focusOnRequest`
and `rememberScope`; the hook reads the rest.

```json
{
  "port": 4471,
  "sound": true,
  "focusOnRequest": true,
  "rememberScope": "project",
  "intercept": ["Bash", "Write", "Edit", "MultiEdit", "NotebookEdit", "WebFetch", "mcp__*"],
  "ignore": [],
  "timeout": 280
}
```

- **intercept** — tool names (fnmatch patterns) routed through the panel.
  Anything else keeps Claude Code's normal prompt. Add `"Read"` if you want
  reads to come through too.
- **ignore** — checked first, wins over `intercept`.
- **timeout** — seconds the hook waits for you. Keep it under the hook timeout
  in `~/.claude/settings.json` (installed as 300).
- **rememberScope** — `"project"` or `"global"`, where "always allow" writes.
- **focusOnRequest** — `false` shows the panel without stealing keyboard focus.

Restart the app after editing; config is read at launch.

## Endpoints

```bash
curl -s 127.0.0.1:4471/health   # {"ok":true,"app":"ClaudeNext"}
curl -s 127.0.0.1:4471/status   # {"pending":1,"current":"Bash: npm run build","paused":false,...}
```

Bound to loopback only. `/status` is handy for a statusline.

## Development

```bash
./run-tests.sh   # swift build + both hook suites
./build.sh       # dist/ClaudeNext.app, ad-hoc signed
```

```
Sources/ClaudeNext/
  main.swift           entry point, .accessory activation policy
  AppDelegate.swift    status item, floating panel, server wiring
  PromptServer.swift   loopback HTTP/1.1, long-polls /ask
  PromptModel.swift    request queue and recent decisions
  Models.swift         hook payload, decision, pending request
  Presentation.swift   per-tool copy, diffs, path shortening
  PromptView.swift     the panel
  Theme.swift          Claude palette and button styles
  StatusIcon.swift     the menu bar spark
hooks/claudenext-hook.py   rule matching, rule saving, hook I/O
tests/                     rule unit tests, hook integration tests
```

`tests/test_integration.py` runs the real hook script against a stubbed app, so
the offline and malformed-input paths are covered — those are the ones that must
never turn into a silent allow.

## Notes

- The app is ad-hoc signed. Gatekeeper may want a one-time approval in System
  Settings → Privacy & Security.
- Hooks are a Claude Code feature, so this covers the CLI. It does not intercept
  prompts in the desktop or web apps.
- Nothing leaves your machine; the server only listens on `127.0.0.1`.
