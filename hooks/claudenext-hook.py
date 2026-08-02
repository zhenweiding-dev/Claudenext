#!/usr/bin/env python3
"""ClaudeNext — PreToolUse hook.

Reads a tool call from Claude Code on stdin, decides what to do with it, and
prints a PreToolUse hook decision on stdout.

Order of resolution:
  1. Not a tool we intercept          -> stay silent, Claude Code prompts as usual
  2. Matches a saved allow/deny rule  -> decide immediately, no UI
  3. Otherwise                        -> ask the menu bar app and block on the answer
  4. App not running / times out      -> stay silent, Claude Code prompts as usual

Staying silent is always the safe fallback: it never grants anything, it just
hands the decision back to Claude Code's built-in prompt.
"""

from __future__ import annotations

import fnmatch
import json
import os
import posixpath
import re
import shlex
import sys
import urllib.error
import urllib.request

SUPPORT_DIR = os.path.expanduser("~/.claudenext")
CONFIG_PATH = os.path.join(SUPPORT_DIR, "config.json")
GLOBAL_RULES_PATH = os.path.join(SUPPORT_DIR, "rules.json")
PROJECT_RULES_RELPATH = os.path.join(".claude", "claudenext.json")

DEFAULT_CONFIG = {
    "port": 4471,
    # Tool names (fnmatch patterns) routed through the menu bar UI.
    "intercept": ["Bash", "Write", "Edit", "MultiEdit", "NotebookEdit", "WebFetch", "mcp__*"],
    # Always skipped, even if they match `intercept`.
    "ignore": [],
    # Seconds to wait for a human. Keep below the hook timeout in settings.json.
    "timeout": 280,
    # "project" writes remembered rules next to the code, "global" to ~/.claudenext.
    "rememberScope": "project",
}

# Commands whose second word is meaningful enough to keep in a rule.
SUBCOMMAND_TOOLS = {
    "git", "npm", "npx", "pnpm", "yarn", "bun", "cargo", "go", "docker", "kubectl",
    "brew", "uv", "pip", "pip3", "poetry", "make", "gh", "swift", "xcodebuild",
    "terraform", "aws", "gcloud", "systemctl", "apt", "apt-get", "composer", "dotnet",
    "rustup", "deno", "flutter", "gradle", "mvn", "sed", "rails", "bundle",
}

SHELL_OPERATORS = re.compile(r"[|&;><$`\n]|\$\(")

FILE_PATH_KEYS = ("file_path", "notebook_path", "path", "filePath")


# --------------------------------------------------------------------------- io


def load_json(path, fallback):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
        return data if isinstance(data, dict) else fallback
    except (OSError, ValueError):
        return fallback


def load_config():
    cfg = dict(DEFAULT_CONFIG)
    cfg.update(load_json(CONFIG_PATH, {}))
    return cfg


def rules_path(cwd, scope):
    if scope == "global":
        return GLOBAL_RULES_PATH
    return os.path.join(cwd, PROJECT_RULES_RELPATH)


def load_rules(cwd):
    """Project rules layered on top of global ones."""
    allow, deny = [], []
    for path in (GLOBAL_RULES_PATH, os.path.join(cwd, PROJECT_RULES_RELPATH)):
        data = load_json(path, {})
        allow += [r for r in data.get("allow", []) if isinstance(r, str)]
        deny += [r for r in data.get("deny", []) if isinstance(r, str)]
    return allow, deny


def save_rule(cwd, scope, rule, bucket):
    path = rules_path(cwd, scope)
    data = load_json(path, {})
    entries = data.get(bucket)
    if not isinstance(entries, list):
        entries = []
    if rule in entries:
        return path
    entries.append(rule)
    data[bucket] = entries
    data.setdefault("allow", [])
    data.setdefault("deny", [])
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2)
        fh.write("\n")
    os.replace(tmp, path)
    return path


# ------------------------------------------------------------------ rule syntax


def split_rule(rule):
    """`Bash(git status:*)` -> ("Bash", "git status:*")."""
    rule = rule.strip()
    if rule.endswith(")") and "(" in rule:
        head, _, arg = rule.partition("(")
        return head.strip(), arg[:-1]
    return rule, None


def normalize_command(command):
    return " ".join(command.split())


def candidate_paths(raw_path, cwd):
    """A path expressed the several ways a rule might spell it."""
    if not raw_path:
        return []
    expanded = os.path.expanduser(raw_path)
    absolute = expanded if os.path.isabs(expanded) else os.path.normpath(os.path.join(cwd, expanded))
    out = [absolute]
    if absolute.startswith(cwd + os.sep):
        out.append(absolute[len(cwd) + 1:])
    home = os.path.expanduser("~")
    if absolute.startswith(home + os.sep):
        out.append("~/" + absolute[len(home) + 1:])
    out.append(raw_path)
    return out


def input_path(tool_input):
    for key in FILE_PATH_KEYS:
        value = tool_input.get(key)
        if isinstance(value, str) and value:
            return value
    return None


def rule_matches(rule, tool_name, tool_input, cwd):
    name, arg = split_rule(rule)
    if not name:
        return False
    if not fnmatch.fnmatchcase(tool_name, name):
        return False
    if arg is None or arg == "" or arg == "*":
        return True

    if tool_name == "Bash":
        command = normalize_command(str(tool_input.get("command", "")))
        target = normalize_command(arg)
        if target.endswith(":*"):
            prefix = target[:-2].strip()
            return command == prefix or command.startswith(prefix + " ")
        return fnmatch.fnmatchcase(command, target) or command == target

    if arg.startswith("domain:"):
        domain = arg[len("domain:"):].strip()
        url = str(tool_input.get("url", ""))
        host = ""
        match = re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*://([^/?#]+)", url)
        if match:
            host = match.group(1).split("@")[-1].split(":")[0]
        return bool(host) and (host == domain or fnmatch.fnmatchcase(host, domain))

    raw = input_path(tool_input)
    if raw:
        pattern = os.path.expanduser(arg)
        for candidate in candidate_paths(raw, cwd):
            if fnmatch.fnmatchcase(candidate, pattern):
                return True
            # `src/**` should also cover `src/a/b.ts`, which fnmatch's `*`
            # already spans since it does not treat `/` specially.
            if pattern.endswith("/**") and candidate.startswith(pattern[:-3] + "/"):
                return True
        return False

    return False


def first_match(rules, tool_name, tool_input, cwd):
    for rule in rules:
        try:
            if rule_matches(rule, tool_name, tool_input, cwd):
                return rule
        except Exception:
            continue
    return None


# ------------------------------------------------------------- rule suggestion


def suggest_rule(tool_name, tool_input, cwd):
    if tool_name == "Bash":
        command = normalize_command(str(tool_input.get("command", "")))
        if not command:
            return "Bash"
        try:
            tokens = shlex.split(command)
        except ValueError:
            tokens = command.split()
        if not tokens:
            return "Bash"
        head = tokens[0]
        # Anything with shell plumbing only gets a single-word prefix.
        if SHELL_OPERATORS.search(command):
            return f"Bash({head}:*)"
        if head in SUBCOMMAND_TOOLS and len(tokens) > 1 and not tokens[1].startswith("-"):
            return f"Bash({head} {tokens[1]}:*)"
        return f"Bash({head}:*)"

    if tool_name == "WebFetch":
        url = str(tool_input.get("url", ""))
        match = re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*://([^/?#]+)", url)
        if match:
            host = match.group(1).split("@")[-1].split(":")[0]
            return f"WebFetch(domain:{host})"
        return "WebFetch"

    raw = input_path(tool_input)
    if raw:
        absolute = os.path.abspath(os.path.expanduser(raw))
        parent = os.path.dirname(absolute)
        if parent and parent != cwd and absolute.startswith(cwd + os.sep):
            relative = posixpath.join(os.path.relpath(parent, cwd).replace(os.sep, "/"), "**")
            return f"{tool_name}({relative})"
        if absolute.startswith(cwd + os.sep):
            return f"{tool_name}({absolute[len(cwd) + 1:]})"
        return f"{tool_name}({absolute})"

    return tool_name


# ------------------------------------------------------------------- decisions


def emit(decision, reason):
    json.dump(
        {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": decision,
                "permissionDecisionReason": reason,
            }
        },
        sys.stdout,
    )
    sys.stdout.write("\n")
    sys.exit(0)


def passthrough():
    """Say nothing: Claude Code falls back to its own permission flow."""
    sys.exit(0)


def ask_app(cfg, payload):
    url = f"http://127.0.0.1:{int(cfg['port'])}/ask"
    body = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        url, data=body, headers={"Content-Type": "application/json"}, method="POST"
    )
    with urllib.request.urlopen(request, timeout=float(cfg["timeout"])) as response:
        return json.loads(response.read().decode("utf-8"))


def matches_any(patterns, tool_name):
    return any(fnmatch.fnmatchcase(tool_name, p) for p in patterns if isinstance(p, str))


def main():
    try:
        event = json.load(sys.stdin)
    except (ValueError, OSError):
        passthrough()

    if event.get("hook_event_name") not in (None, "PreToolUse"):
        passthrough()

    tool_name = event.get("tool_name") or ""
    tool_input = event.get("tool_input")
    if not isinstance(tool_input, dict):
        tool_input = {}
    cwd = event.get("cwd") or os.getcwd()
    cwd = os.path.abspath(cwd)

    cfg = load_config()

    if not tool_name:
        passthrough()
    if matches_any(cfg.get("ignore", []), tool_name):
        passthrough()
    if not matches_any(cfg.get("intercept", []), tool_name):
        passthrough()

    allow_rules, deny_rules = load_rules(cwd)

    hit = first_match(deny_rules, tool_name, tool_input, cwd)
    if hit:
        emit("deny", f"Blocked by ClaudeNext rule {hit}")

    hit = first_match(allow_rules, tool_name, tool_input, cwd)
    if hit:
        emit("allow", f"Allowed by ClaudeNext rule {hit}")

    rule = suggest_rule(tool_name, tool_input, cwd)
    payload = {
        "tool_name": tool_name,
        "tool_input": tool_input,
        "cwd": cwd,
        "session_id": event.get("session_id"),
        "transcript_path": event.get("transcript_path"),
        "suggested_rule": rule,
    }

    try:
        answer = ask_app(cfg, payload)
    except (urllib.error.URLError, OSError, ValueError, TimeoutError):
        # App is closed or the user never answered — let Claude Code ask.
        passthrough()

    decision = answer.get("decision", "pass")
    message = answer.get("message") or None
    remember = bool(answer.get("remember"))
    scope = cfg.get("rememberScope", "project")

    if decision == "allow":
        reason = "Approved in ClaudeNext"
        if remember:
            try:
                path = save_rule(cwd, scope, rule, "allow")
                reason = f"Approved in ClaudeNext; saved {rule} to {path}"
            except OSError as exc:
                reason = f"Approved in ClaudeNext (could not save rule: {exc})"
        if message:
            reason += f" — {message}"
        emit("allow", reason)

    if decision == "deny":
        reason = message or "Denied in ClaudeNext"
        if remember:
            try:
                save_rule(cwd, scope, rule, "deny")
                reason += f" (saved deny rule {rule})"
            except OSError:
                pass
        emit("deny", reason)

    passthrough()


if __name__ == "__main__":
    main()
