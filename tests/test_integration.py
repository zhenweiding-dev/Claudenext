#!/usr/bin/env python3
"""Drives the real hook script against a stubbed menu bar app.

Covers the decision round-trip, rule persistence, and — most importantly —
that every failure path stays silent rather than granting anything.
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HOOK = os.path.join(REPO, "hooks", "claudenext-hook.py")
PORT = 44711        # stub app
DEAD_PORT = 44712   # nothing listening here

workdir = tempfile.mkdtemp(prefix="claudenext-test-")
HOME = os.path.join(workdir, "home")
PROJ = os.path.join(workdir, "proj")
os.makedirs(os.path.join(HOME, ".claudenext"))
os.makedirs(os.path.join(PROJ, "src"))

reply = {"decision": "pass"}
seen = []


class Stub(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        seen.append(json.loads(self.rfile.read(length)))
        body = json.dumps(reply).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


server = HTTPServer(("127.0.0.1", PORT), Stub)
threading.Thread(target=server.serve_forever, daemon=True).start()


def write_config(port, timeout=10):
    with open(os.path.join(HOME, ".claudenext", "config.json"), "w") as fh:
        json.dump({"port": port, "timeout": timeout}, fh)


def run(tool, tool_input, event="PreToolUse", raw=None, entrypoint="cli"):
    payload = raw if raw is not None else json.dumps({
        "hook_event_name": event,
        "tool_name": tool,
        "tool_input": tool_input,
        "cwd": PROJ,
        "session_id": "test",
    })
    # Pin the entrypoint: this suite may itself be run from a host that the
    # hook is configured to step aside for.
    env = dict(os.environ, HOME=HOME, CLAUDE_CODE_ENTRYPOINT=entrypoint)
    proc = subprocess.run([sys.executable, HOOK], input=payload, capture_output=True,
                          text=True, env=env, timeout=30)
    out = proc.stdout.strip()
    decision = json.loads(out)["hookSpecificOutput"] if out else None
    return proc.returncode, decision, proc.stderr


failures = []


def check(desc, condition, detail=""):
    if not condition:
        failures.append(f"{desc}  ({detail})")


write_config(PORT)
settings_path = os.path.join(PROJ, ".claude", "settings.local.json")
scope_path = os.path.join(PROJ, ".claude", "claudenext.json")


def write_permissions(**buckets):
    os.makedirs(os.path.dirname(settings_path), exist_ok=True)
    json.dump({"permissions": buckets}, open(settings_path, "w"))

# 1. A plain allow.
reply = {"decision": "allow"}
rc, out, err = run("Bash", {"command": "echo hi"})
check("allow exits 0", rc == 0, rc)
check("allow is reported as allow", out and out["permissionDecision"] == "allow", out)
check("the app is told which rule to offer",
      seen[-1]["suggested_rule"] == "Bash(echo:*)", seen[-1].get("suggested_rule"))

# 2. A deny carries the user's message back to Claude.
reply = {"decision": "deny", "message": "use pnpm instead"}
rc, out, err = run("Bash", {"command": "npm install lodash"})
check("deny is reported as deny", out and out["permissionDecision"] == "deny", out)
check("the typed message becomes the reason",
      out and out["permissionDecisionReason"] == "use pnpm instead", out)

# 3. "Always allow" writes into the project's own permissions.
os.makedirs(os.path.dirname(settings_path), exist_ok=True)
json.dump({"model": "opus", "permissions": {"allow": ["Bash(ls:*)"]}},
          open(settings_path, "w"))
reply = {"decision": "allow", "remember": True}
rc, out, err = run("Bash", {"command": "npm run build --watch"})
saved = json.load(open(settings_path))
check("the rule lands in permissions.allow",
      saved["permissions"]["allow"] == ["Bash(ls:*)", "Bash(npm run:*)"], saved)
check("unrelated keys in that file survive", saved.get("model") == "opus", saved)
check("the reason mentions the save", out and "saved" in out["permissionDecisionReason"], out)
check("it names settings.local.json",
      out and "settings.local.json" in out["permissionDecisionReason"], out)

# 4. That rule now short-circuits without bothering the app.
before = len(seen)
reply = {"decision": "deny"}  # would flip the result if the app were consulted
rc, out, err = run("Bash", {"command": "npm run build -- --verbose"})
check("a saved rule decides on its own", out and out["permissionDecision"] == "allow", out)
check("the app is not contacted", len(seen) == before, f"{len(seen)} vs {before}")

# 5. Deny rules beat allow rules.
write_permissions(allow=["Bash(npm run:*)"], deny=["Bash(npm run deploy:*)"])
rc, out, err = run("Bash", {"command": "npm run deploy"})
check("deny wins", out and out["permissionDecision"] == "deny", out)

# 6. Tools outside `intercept` are left to Claude Code.
rc, out, err = run("Read", {"file_path": os.path.join(PROJ, "src", "a.ts")})
check("passthrough exits 0", rc == 0, rc)
check("passthrough prints nothing", out is None, out)

# 7. App unreachable — must stay silent, never allow.
write_config(DEAD_PORT, timeout=3)
rc, out, err = run("Bash", {"command": "curl https://example.com"})
check("offline exits 0", rc == 0, rc)
check("offline prints nothing", out is None, out)
check("offline is quiet on stderr", err == "", err)

# 8. Garbage on stdin — same.
rc, out, err = run(None, None, raw="not json at all")
check("garbage exits 0", rc == 0, rc)
check("garbage prints nothing", out is None, out)

# 9. A different hook event is none of our business.
rc, out, err = run("Bash", {"command": "ls"}, event="PostToolUse")
check("other events print nothing", out is None, out)

# 10. The shared settings.json counts too, not just the local one.
os.remove(settings_path)
write_config(PORT)
cc_settings = os.path.join(PROJ, ".claude", "settings.json")
json.dump({"permissions": {"allow": ["Bash(git status:*)"],
                           "deny": ["Bash(rm:*)"],
                           "ask": ["Bash(git push:*)"]}},
          open(cc_settings, "w"))

before = len(seen)
reply = {"decision": "deny"}  # would flip the result if the app were consulted
rc, out, err = run("Bash", {"command": "git status --short"})
check("settings.json allow is honoured", out and out["permissionDecision"] == "allow", out)
check("settings.json allow skips the panel", len(seen) == before, len(seen))

rc, out, err = run("Bash", {"command": "rm -rf build"})
check("settings.json deny is honoured", out and out["permissionDecision"] == "deny", out)
check("deny reason quotes the rule",
      out and "Bash(rm:*)" in out["permissionDecisionReason"], out)

# "ask" must beat an allow rule from either source and reach the panel.
write_permissions(allow=["Bash(git push:*)"])
before = len(seen)
reply = {"decision": "allow"}
rc, out, err = run("Bash", {"command": "git push origin main"})
check("settings.json ask outranks allow", len(seen) == before + 1, len(seen))
check("ask still ends in a real answer", out and out["permissionDecision"] == "allow", out)
os.remove(settings_path)

# A repo deny must be unreachable from the panel. "allow" from a hook bypasses
# Claude Code's own permission check, so the deny has to be enforced before the
# panel is ever consulted — there is deliberately no way to opt out of this.
before = len(seen)
reply = {"decision": "allow"}
rc, out, err = run("Bash", {"command": "rm -rf build"})
check("a repo deny is never offered to the panel", len(seen) == before, len(seen))
check("a repo deny cannot be clicked away",
      out and out["permissionDecision"] == "deny", out)
os.remove(cc_settings)
write_config(PORT)

# 10b. A settings file that will not parse must be left strictly alone.
#      It is the user's own file and holds far more than permissions.
broken = '{\n  "model": "opus",\n  "env": {"FOO": "bar"},\n  "permissions": {"allow": ["Bash(ls:*)"]},\n}\n'
open(settings_path, "w").write(broken)
reply = {"decision": "allow", "remember": True}
rc, out, err = run("Bash", {"command": "npm run something"})
check("a malformed settings file is not rewritten",
      open(settings_path).read() == broken, open(settings_path).read()[:80])
check("the call is still answered", out and out["permissionDecision"] == "allow", out)
check("and the failure is reported back to Claude",
      out and "could not save" in out["permissionDecisionReason"], out)
os.remove(settings_path)
write_config(PORT)

# 10c. Every host goes through the panel by default; ignoreEntrypoints opts out.
before = len(seen)
reply = {"decision": "allow"}
rc, out, err = run("Bash", {"command": "echo hi"}, entrypoint="claude-desktop")
check("the desktop app is intercepted like anything else",
      len(seen) == before + 1, len(seen))
with open(os.path.join(HOME, ".claudenext", "config.json"), "w") as fh:
    json.dump({"port": PORT, "timeout": 10, "ignoreEntrypoints": ["claude-desktop"]}, fh)
before = len(seen)
rc, out, err = run("Bash", {"command": "echo hi"}, entrypoint="claude-desktop")
check("ignoreEntrypoints steps aside", out is None and len(seen) == before, out)
rc, out, err = run("Bash", {"command": "echo hi"}, entrypoint="cli")
check("and only for the named host", len(seen) == before + 1, len(seen))
write_config(PORT)

# 11. Exactly one rule source: files of our own grant nothing.
os.makedirs(os.path.join(HOME, ".claudenext"), exist_ok=True)
json.dump({"allow": ["Bash(echo:*)"], "deny": []},
          open(os.path.join(HOME, ".claudenext", "rules.json"), "w"))
json.dump({"allow": ["Bash(echo:*)"], "deny": []}, open(scope_path, "w"))
write_config(PORT)
before = len(seen)
reply = {"decision": "allow"}
rc, out, err = run("Bash", {"command": "echo hi"})
check("a legacy rules file grants nothing", len(seen) == before + 1, len(seen))
os.remove(os.path.join(HOME, ".claudenext", "rules.json"))

# 12. A project can still override which tools are intercepted at all.
json.dump({"intercept": ["Read"]}, open(scope_path, "w"))
before = len(seen)
rc, out, err = run("Bash", {"command": "echo hi"})
check("project override drops Bash", out is None and len(seen) == before, out)
rc, out, err = run("Read", {"file_path": os.path.join(PROJ, "src", "a.ts")})
check("project override adds Read", len(seen) == before + 1, len(seen))
os.remove(scope_path)

server.shutdown()
shutil.rmtree(workdir, ignore_errors=True)

if failures:
    print("\n".join("FAIL  " + f for f in failures))
    sys.exit(1)
print(f"test_integration: all pass ({len(seen)} app round-trips)")
