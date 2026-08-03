# ClaudeNext

Answer Claude Code's permission prompts from the macOS menu bar instead of the
terminal. Parallel sessions all show up at once, answerable in any order.

```
       ✳ 2  ← plain spark, a count, a pulse that fades out
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
  │ │ ▸ Ask about in api-server   7 tools      │ │
  │ └──────────────────────────────────────────┘ │
  │  … more cards …                              │
  ├──────────────────────────────────────────────┤
  │ Sound / Open automatically / Hide when idle  │
  └──────────────────────────────────────────────┘
```

macOS 14+ and the Swift toolchain (`xcode-select --install`).

> Days old, little real mileage, and it sits on the path of every tool call
> Claude Code makes. Read the four points below before installing.

## Install

```bash
git clone https://github.com/zhenweiding-dev/Claudenext.git
cd Claudenext
./install.sh
```

Builds `~/Applications/ClaudeNext.app`, puts the hook in `~/.claudenext/`, adds
one `PreToolUse` entry to `~/.claude/settings.json`, and installs a login agent
so it starts with you. Restart open Claude Code sessions afterwards.

`./uninstall.sh` undoes all four. Your rules stay, because they were always
yours — see below.

## Four things to know

**The hook is global.** One entry in `~/.claude/settings.json` covers every
session in every directory. A project can only narrow what it asks about, not
opt out.

**Answering `allow` skips Claude Code's own permission check.** That is what
lets this replace the terminal prompt, and it is the whole risk: a rule that
matches more than you meant grants more than you meant, with nothing behind it.

**It fails closed.** App not running, port taken, timeout, bad input,
unreadable settings — every failure prints nothing and you get the normal
terminal prompt. No setting can change that.

**Always allow edits your real config.** Rules go to
`<project>/.claude/settings.local.json`, the file Claude Code already uses, not
somewhere of ours.

## Controls

| | |
|---|---|
| `↩` / `esc` | Allow / Deny |
| `⌘A` | Always allow — saves the rule to this project |
| `⌥` + Deny | Always deny |
| Type a message, then `↩` | Deny, and send Claude the text as the reason |
| `⌘↑` `⌘↓` | Move between stacked requests |
| Right-click the icon | Pause, open rules, open config, quit |

Every waiting request is on screen at once; one is focused and owns the
keyboard, and the others hide their key hints. Clicking away parks a request
rather than answering it.

## Rules

One source: your own Claude Code permissions. Read from
`~/.claude/settings.json`, then the project's `settings.json`, then its
`settings.local.json`. Written to `settings.local.json`. Deny beats allow; an
`ask` entry beats both and always reaches the panel.

| Rule | Matches |
|---|---|
| `Bash(npm run:*)` | commands starting with `npm run` |
| `Bash(ls -la)` | exactly that command |
| `Edit(src/**)` | anything under `src/` |
| `Read(~/notes/*.md)` | `~` expands |
| `WebFetch(domain:example.com)` | that host |
| `mcp__github__*` | that MCP server |

Two limits are deliberate, because a rule must mean only what it says:

- A wildcard rule never matches a command containing `;` `&` `|` `<` `>`
  backtick or `$(`. `Bash(git status:*)` permits `git status`, not
  `git status && rm -rf ~`. Spell a chained command out in full to allow one.
- Paths are normalised and `..` is refused, so `Edit(src/**)` cannot be walked
  out of.

Rules always belong to the project they were approved in. There is no "remember
everywhere": `Edit(src/**)` resolves against the current directory, so storing
it globally would authorise `src/**` in every other repo.

The **Ask about in ‹project›** row on each card is that project's list of which
tools reach the panel at all — scope, not permission — kept in
`<project>/.claude/claudenext.json`.

## Settings

Three toggles in the panel: sound, whether the panel opens itself (off by
default — the count and pulse are the notification), and whether the icon hides
when idle. Everything else is `~/.claudenext/config.json`:

```json
{
  "port": 4471,
  "intercept": ["Bash", "Write", "Edit", "MultiEdit", "NotebookEdit", "WebFetch", "mcp__*"],
  "ignore": [],
  "timeout": 280
}
```

`intercept` is the global default for which tools reach the panel; a project
overrides it. Only `port` needs a restart. `CLAUDENEXT_HOME` relocates the
whole directory.

## Limits

- **Any process running as you can talk to it.** The server is loopback-only
  with no auth. A token would be theatre: whatever can reach the port can read
  the file the token would live in.
- **Claude Code writes `settings.local.json` too**, and does not know about our
  lock, so simultaneous writes could lose one change. An unreadable file is
  never overwritten.
- **Claude Code's matcher is looser than ours**, so a rule may permit slightly
  more when ClaudeNext is not running.
- **Allow is not a sandbox.** The tool then runs with everything you can do.
- Hooks are a CLI feature; this does not cover the desktop or web apps.
- Ad-hoc signed, so Gatekeeper may want a one-time approval.

## Development

```bash
./run-tests.sh   # build, then 5 suites: defaults agreement, rule matching,
                 # config round-trip, hook integration, cross-process writes
./build.sh       # dist/ClaudeNext.app
```

`hooks/claudenext-hook.py` holds every rule decision; the Swift app only draws
the panel and sends the answer back, so the matcher has one implementation.
`curl -s 127.0.0.1:4471/status` reports the queue.
