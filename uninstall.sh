#!/usr/bin/env bash
# Removes the hook registration and the app. Leaves ~/.claudenext rules alone.
set -euo pipefail

SETTINGS="$HOME/.claude/settings.json"

echo "==> Quitting ClaudeNext"
osascript -e 'quit app "ClaudeNext"' 2>/dev/null || true
pkill -x ClaudeNext 2>/dev/null || true

echo "==> Removing hook from $SETTINGS"
python3 - "$SETTINGS" <<'PY'
import json, os, sys

path = sys.argv[1]
try:
    with open(path, encoding="utf-8") as fh:
        settings = json.load(fh)
except (OSError, ValueError):
    sys.exit(0)

matchers = settings.get("hooks", {}).get("PreToolUse")
if isinstance(matchers, list):
    def is_ours(m):
        return isinstance(m, dict) and any(
            h.get("command", "").endswith("claudenext-hook.py")
            for h in m.get("hooks", []) if isinstance(h, dict)
        )
    matchers[:] = [m for m in matchers if not is_ours(m)]
    if not matchers:
        settings["hooks"].pop("PreToolUse", None)
    if not settings.get("hooks"):
        settings.pop("hooks", None)

tmp = path + ".tmp"
with open(tmp, "w", encoding="utf-8") as fh:
    json.dump(settings, fh, indent=2)
    fh.write("\n")
os.replace(tmp, path)
print("    removed")
PY

echo "==> Removing ~/Applications/ClaudeNext.app"
rm -rf "$HOME/Applications/ClaudeNext.app"

echo "Done. Rules and config left in ~/.claudenext (delete manually if you want)."
