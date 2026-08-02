# ClaudeNext

A macOS menu bar app that answers Claude Code's permission prompts.

When Claude Code wants to run a command, edit a file, or call an MCP tool, the
request drops out of the menu bar with **Deny**, **Always allow** and **Allow**,
plus a field for telling Claude what to do instead. Your terminal stays where it
is, and parallel sessions all show up at once.

```
       ✳ 2  ← menu bar: plain spark, a count, a pulse that fades out
  ┌──────────────────────────────────────────────┐
  │ ● 2 requests waiting        ⌃ ⌄     [Pause]  │
  │   127.0.0.1:4471 · 5 decisions               │
  ├──────────────────────────────────────────────┤
  │ ┌──────────────────────────────────────────┐ │
  │ │ Claude wants to run a command     [Bash] │ │
  │ │ 📁 api-server                            │ │
  │ │ ┌──────────────────────────────────────┐ │ │
  │ │ │ npm run migrate:latest               │ │ │
  │ │ └──────────────────────────────────────┘ │ │
  │ │ ┌ Tell Claude what to do differently… ┐  │ │
  │ │ [Deny esc]   [Always allow ⌘A][Allow ↩]  │ │
  │ │ Always allow adds Bash(npm run:*)        │ │
  │ │ ▸ Ask about in api-server   7 tools      │ │
  │ └──────────────────────────────────────────┘ │
  │  … more cards …                              │
  ├──────────────────────────────────────────────┤
  │ SETTINGS                                     │
  │ Sound on a new request                  [on] │
  │ Open the panel automatically           [off] │
  │ Hide the menu bar icon when idle       [off] │
  ├──────────────────────────────────────────────┤
  │                                        Quit  │
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
`~/.claude/settings.json`, installs a login agent, and starts it.

Restart any running Claude Code session afterwards so it reloads the hook.

`./uninstall.sh` reverses all of it and leaves your rules alone.

## Running it

Nothing to run. The login agent starts ClaudeNext when you log in and restarts
it if it crashes — but not if you quit it yourself. The hook is registered
globally, so every session in every directory goes through it.

```bash
launchctl kickstart -k gui/$UID/com.claudenext.menubar   # restart it
curl -s 127.0.0.1:4471/health                            # is it up?
open -a ClaudeNext                                       # reopen the panel
```

If it is not running, nothing breaks — the hook falls through and Claude Code
prompts in the terminal as usual.

Re-running `install.sh` is safe: it replaces the running instance rather than
stacking a second menu bar icon, and the settings merge rewrites only its own
hook entry.

## How a tool call is decided

Claude Code fires a `PreToolUse` hook before every tool call.
`claudenext-hook.py` resolves it in this order:

1. **Not in the ask-about list** → prints nothing, Claude Code prompts as usual.
2. **Any deny rule matches** → denied, no UI. Yours or the repo's.
3. **A `permissions.ask` entry matches** → skips step 4, always shows the panel.
4. **Any allow rule matches** → allowed, no UI. Yours or the repo's.
5. **Otherwise** → `POST /ask` to the app on `127.0.0.1:4471`. The request stays
   open, and that is what blocks Claude Code until you answer.
6. **App not running, or you never answered** → prints nothing, Claude Code
   prompts as usual.

The fallback is always silence, never approval. If ClaudeNext is closed, wedged,
or times out, you get the normal terminal prompt — it cannot fail open.

## Controls

| Action | |
|---|---|
| `↩` | Allow once |
| `⌘A` | Always allow — saves the rule to this project |
| `esc` | Deny |
| `⌥` + Deny | Always deny — saves a deny rule to this project |
| Type a message, then `↩` | Deny, and hand the text to Claude as the reason |
| `⌘↑` / `⌘↓` | Move between stacked requests |
| Click the icon | Open the panel |
| Right-click the icon | Pause, open rules, open config JSON, quit |

A message typed into the field reaches Claude as `permissionDecisionReason`, so
"use pnpm, not npm" lands the same way it would from the terminal prompt.

Clicking away parks a request rather than answering it.

## Several sessions at once

Every Claude Code session gets its own blocking connection, so parallel sessions
work. When more than one request is waiting they are **all shown at once**,
stacked as scrollable cards with their own buttons and message field — answer
them in any order, not oldest first.

One card is focused at a time and owns the keyboard; `⌘↑` / `⌘↓` (or a click)
move the focus and the list scrolls to follow. Unfocused cards hide their key
hints so it stays obvious what `↩` will hit. Each card names its project, so two
sessions editing the same filename in different repos are told apart.

## Rules

Every remembered rule is written to the project it was approved in,
`<project>/.claude/claudenext.json`:

```json
{
  "allow": ["Bash(npm run:*)", "Edit(src/**)"],
  "deny": ["Bash(git push:*)"],
  "intercept": ["Bash", "Edit", "Read"]
}
```

There is deliberately no "remember everywhere" option. A suggested rule like
`Edit(src/**)` is resolved against the current working directory, so storing it
globally would silently authorise `src/**` in *every* repo Claude later touches.

`~/.claudenext/rules.json` is still read for rules you write by hand, but only
ones that mean the same thing outside a project — command prefixes, domains, and
absolute or `~`-rooted paths. Relative path rules there are ignored for the same
reason.

Deny is checked before allow. Supported forms:

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

### Your repo's existing permissions

The hook also reads `permissions.allow` / `deny` / `ask` from
`~/.claude/settings.json`, `<project>/.claude/settings.json` and
`settings.local.json`. Anything you already approved there is not asked about a
second time, and `ask` entries outrank every allow rule and always reach the
panel.

There is no switch for this. A hook answering `allow` bypasses Claude Code's own
permission check, so a repo's `deny` list has to be enforced before the panel is
ever consulted — otherwise one click here would override something the repo
explicitly forbids.

### What each project asks about

The **Ask about in ‹project›** row at the bottom of a card is that project's own
intercept list, collapsed by default. It shows the project's real state — the
summary reads `· global` while the project is still following the global default
— and changing anything writes the whole effective list into that project's
`claudenext.json`.

Both the app and the hook write that file, so writes take an exclusive `flock`
on `<project>/.claude/.claudenext.lock` and land via atomic rename. Neither side
can lose the other's change.

## Config

`~/.claudenext/config.json`. The panel edits the common ones; the rest are
file-only.

```json
{
  "port": 4471,
  "sound": true,
  "focusOnRequest": true,
  "autoOpenOnRequest": false,
  "hideWhenIdle": false,
  "intercept": ["Bash", "Write", "Edit", "MultiEdit", "NotebookEdit", "WebFetch", "mcp__*"],
  "ignore": [],
  "timeout": 280
}
```

- **intercept** — the global default for which tools reach the panel. A project
  overrides it in its own rules file.
- **ignore** — checked first, wins over `intercept`.
- **timeout** — seconds the hook waits for you. Keep it under the hook timeout in
  `~/.claude/settings.json` (installed as 300).
- **autoOpenOnRequest** — `true` pops the panel open by itself. Off by default:
  a new request adds a count to the menu bar icon and pulses it, and you open
  the panel when you are ready.
- **focusOnRequest** — whether an automatic open also takes the keyboard. Only
  consulted when `autoOpenOnRequest` is on; opening it yourself always focuses.
- **hideWhenIdle** — `true` keeps the icon out of the menu bar until there is
  something to ask. `open -a ClaudeNext` brings the panel back.

Everything except `port` applies immediately: the app holds its own copy and the
hook re-reads the file on every call. Writes are read-modify-write, so keys you
add by hand survive.

`CLAUDENEXT_HOME` relocates the whole support directory; both ends honour it.

## Menu bar icon

One glyph in both states — a plain template spark that takes the menu bar's own
colour, matching Claude's own tray icon. A waiting request shows a count beside
it and pulses the button, and that pulse decays to nothing over ~24 seconds so an
unanswered request stops being a flashing distraction. A newly arrived request
restarts the fade; answering one does not.

## Endpoints

```bash
curl -s 127.0.0.1:4471/health   # {"ok":true,"app":"ClaudeNext"}
curl -s 127.0.0.1:4471/status   # {"pending":1,"current":"Bash: npm run build",...}
```

Bound to loopback only. `/status` is handy for a statusline.

## Development

```bash
./run-tests.sh   # swift build + config round-trip + rules + hook integration + concurrency
./build.sh       # dist/ClaudeNext.app, ad-hoc signed, icon generated from source
```

```
Sources/ClaudeNext/
  main.swift           entry point, .accessory activation policy
  AppDelegate.swift    status item, pulse, floating panel, server wiring
  PromptServer.swift   loopback HTTP/1.1, long-polls /ask
  PromptModel.swift    request queue, recent decisions, config, per-project state
  Models.swift         hook payload, decision, pending request
  Presentation.swift   per-tool copy, diffs, project and path naming
  PromptView.swift     the panel
  ProjectRules.swift   locked read-modify-write of a project's rules file
  AppConfig.swift      ~/.claudenext/config.json
  Theme.swift          palette taken from the Claude app's own tokens
  StatusIcon.swift     the menu bar spark
Tools/make-icon.swift  draws AppIcon.iconset at build time
hooks/claudenext-hook.py   rule matching, rule saving, hook I/O
tests/                 config round-trip, rule unit tests, hook integration,
                       cross-process concurrency
```

`tests/test_integration.py` runs the real hook against a stubbed app, so the
offline and malformed-input paths are covered — those are the ones that must
never turn into a silent allow.

## Notes

- The app is ad-hoc signed. Gatekeeper may want a one-time approval in System
  Settings → Privacy & Security.
- Hooks are a Claude Code feature, so this covers the CLI. It does not intercept
  prompts in the desktop or web apps.
- Nothing leaves your machine; the server only listens on `127.0.0.1`.
