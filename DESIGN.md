# How ClaudeNext works

The friendly version is in [README.md](README.md). This is everything else.

## Shape

Claude Code fires a `PreToolUse` hook before every tool call.
`hooks/claudenext-hook.py` reads the call, decides what to do, and prints a
decision. When it needs a human it `POST`s to the menu bar app and **leaves the
HTTP request open** — that open connection is what blocks Claude Code until you
answer.

```
Claude Code ──stdin──▶ hook          (one process per tool call)
                        │ POST /ask  (connection held open)
                        ▼
                    ClaudeNext.app   (resident, 127.0.0.1:4471)
                        │ {"decision":"allow"}
                        ▼
             hook ──stdout──▶ Claude Code
```

Every rule decision lives in the hook; the app only draws the panel and sends
the answer back. That keeps the matcher to one implementation in one language.

## The three invariants

Most of what looks like a missing feature comes from one of these.

**Fail closed.** Every failure path — app not running, port taken, timeout,
malformed input, unreadable settings, unknown hook event — prints nothing, and
Claude Code prompts exactly as it would without any of this. No setting changes
that.

**No switch may weaken a permission decision.** Settings cover presentation
only. Two earlier settings were removed for breaking this: one stored remembered
rules globally, where a project-relative path like `Edit(src/**)` silently
authorised the same path in every other repo; the other disabled reading the
repo's permissions, which let one click override a `deny` the repo had declared.

**One rule source, and it's yours.** No permission store of our own. Rules are
read from and written to the Claude Code permission lists you already have.

## Deciding a call

0. The session's permission mode already settled it — `bypassPermissions`,
   `plan`, or `acceptEdits` on a file edit → print nothing.
1. Not in the ask-about list → print nothing, Claude Code prompts.
2. A `permissions.deny` entry matches → denied, no UI.
3. A `permissions.ask` entry matches → skip step 4, always show the panel.
4. `permissions.allow` covers it → allowed, no UI.
5. Otherwise → `POST /ask` and block.
6. No answer, or no app → print nothing, Claude Code prompts.

Note that a hook answering `allow` **bypasses Claude Code's own permission
check**. That's what lets the panel replace the prompt, and it's why deny is
enforced at step 2 rather than left to Claude Code afterwards — otherwise one
click here could override something the repo forbids.

## Rules

Read in Claude Code's own precedence order:

```
~/.claude/settings.json                 permissions.allow / deny / ask
<project>/.claude/settings.json         shared, committed
<project>/.claude/settings.local.json   personal, gitignored
```

Written to `settings.local.json`, always in the project the call came from.
There's no "remember everywhere" because `Edit(src/**)` resolves against the
current working directory — stored globally it would authorise `src/**` in every
repo you later touch.

| Rule | Matches |
|---|---|
| `Bash` | every Bash call |
| `Bash(npm run:*)` | commands starting with `npm run` |
| `Bash(ls -la)` | exactly that command |
| `Edit(src/**)` | anything under `src/` |
| `Write(/etc/hosts)` | one absolute path |
| `Read(~/notes/*.md)` | `~` expands |
| `Read(//Users/me/**)` | Claude Code's `//` absolute form |
| `WebFetch(domain:example.com)` | that host |
| `mcp__github__*` | every tool on that server |

### Two things the matcher refuses

**A line is split into the commands it actually runs.** `a && b | c` is three
commands. Allow needs *every* one covered; deny fires if *any* one matches. So
`Bash(git status:*)` permits `git status --short` but not
`git status && rm -rf ~`, and `Bash(rm:*)` in the deny list still catches
`ls && rm -rf ~`. Operators inside quotes are text, not plumbing. Command
substitution (`` ` ``, `$(`) is never covered — no rule can speak for text that
doesn't exist yet.

**Paths are normalised and `..` is refused**, so `Edit(src/**)` can't be walked
out of via `src/../../../etc/passwd`.

Both of these make ClaudeNext stricter than Claude Code's own matcher, which
means a rule may permit slightly more when ClaudeNext isn't running.

### When no rule is offered

**Always allow** only appears when a rule can be scoped to the call. For `Bash`
that means a command to take a prefix from, for a file tool a path, for
`WebFetch` a host. Without one the only rule left would be the bare tool name —
which allows *every* call to that tool — so the button is hidden instead. Tools
with no natural sub-scope (`WebSearch`, an MCP tool) still offer themselves,
because there the bare name is the intended granularity rather than a fallback.

Claude Code does not tell a hook which buttons it would have shown; the payload
carries `tool_name`, `tool_input`, `cwd`, `permission_mode` and identifiers, and
nothing about the prompt. So the panel cannot mirror the host's options exactly —
it decides for itself which ones are honest for the call in front of it.

### Scope, not permission

The **Ask about in ‹project›** row on a card is which tools reach the panel at
all for that project. That's not a permission, and Claude Code has no concept
for it, so it lives in `<project>/.claude/claudenext.json`:

```json
{ "intercept": ["Bash", "Edit", "Read"] }
```

Absent means the project follows the global default.

### Concurrent writes

Two sessions can save a rule at once, and the app writes the scope file while
the hook writes rules. Writes take an exclusive `flock` on
`<project>/.claude/.claudenext.lock` and land via atomic rename. That lock file
is left behind in any project you save a rule in — add `.claudenext.lock` to
your `.gitignore`. A file that
exists but won't parse is never overwritten — that guard exists because an
earlier version replaced a settings file it couldn't read with just its own key,
costing everything else in it.

## Settings

`~/.claudenext/config.json`. The panel edits sound, self-opening, and hiding the
icon; the rest is file-only.

| Key | Default | |
|---|---|---|
| `port` | `4471` | needs a restart |
| `sound` | `true` | |
| `autoOpenOnRequest` | `false` | open the panel by itself |
| `focusOnRequest` | `false` | let an automatic open take the keyboard |
| `hideWhenIdle` | `false` | keep out of the menu bar until needed |
| `intercept` | 7 tools | global default; a project overrides it |
| `ignore` | `[]` | checked before `intercept` |
| `ignoreEntrypoints` | `[]` | hosts to skip, vs `CLAUDE_CODE_ENTRYPOINT` |
| `timeout` | `280` | seconds to wait, capped at 290 |
| `respectPermissionMode` | `true` | skip what the session's mode would accept |

Everything but `port` applies immediately: the app holds its own copy and the
hook re-reads the file every call. Writes preserve keys you add by hand.
`CLAUDENEXT_HOME` relocates the whole directory; the hook honours it too.

`ignoreEntrypoints` is worth a warning. Adding `claude-desktop` stops the panel
seeing that host's calls entirely — for anyone who works in the desktop app,
that turns the tool off. Use **Skip** for one-offs instead.

## The menu bar icon

One glyph in both states: a plain template spark that takes the menu bar's own
colour, matching Claude's own tray icon. Its geometry was measured off
`Claude.app`'s shipped tray template — twelve spokes at irregular angles — and
fitted to 82.7% intersection-over-union. A waiting request adds a count and
pulses the button, decaying to nothing over ~24 seconds so an unanswered request
stops being a flashing distraction. A new request restarts the fade; answering
one doesn't.

## What this doesn't protect you from

- **Any process running as you can talk to it.** The server is loopback-only
  with no auth. A token would be theatre — whatever can reach the port can read
  the file the token would live in.
- **Claude Code writes `settings.local.json` too** and doesn't know about our
  lock, so simultaneous writes could lose one change.
- **Allow is not a sandbox.** The tool then runs with everything you can do.
- Ad-hoc signed, so Gatekeeper may want a one-time approval.

## Working on it

```bash
./run-tests.sh   # build, then: defaults agreement, rule matching,
                 # config round-trip, hook integration, cross-process writes
./build.sh       # dist/ClaudeNext.app, icon generated from source
```

```
Sources/ClaudeNext/
  main.swift           entry point, .accessory activation policy
  AppDelegate.swift    status item, pulse, floating panel, server wiring
  PromptServer.swift   loopback HTTP/1.1, long-polls /ask
  PromptModel.swift    request queue, recent decisions, config, project scope
  Models.swift         hook payload, decision, pending request
  Presentation.swift   per-tool copy, diffs, repo and path naming
  PromptView.swift     the panel
  ProjectScope.swift   locked read-modify-write of a project's scope file
  AppConfig.swift      ~/.claudenext/config.json
  Theme.swift          palette taken from the Claude app's own tokens
  StatusIcon.swift     the menu bar spark
Tools/make-icon.swift  draws AppIcon.iconset at build time
hooks/claudenext-hook.py   every rule decision
tests/                 rules, config, integration, concurrency
```

Two tests are worth knowing about. `tests/test_integration.py` drives the real
hook against a stubbed app, so the offline and malformed-input paths are
covered — those must never turn into a silent allow. And because the app and the
hook each fall back to their own defaults for anything missing from the shared
config, the suite dumps a pristine `AppConfig` and diffs it against the hook's
`DEFAULT_CONFIG`; drift there is silent and can fail toward the panel claiming a
tool is reviewed while the hook waves it through.
