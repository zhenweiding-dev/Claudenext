#!/usr/bin/env bash
# Builds ClaudeNext, installs it to ~/Applications, copies the hook to
# ~/.claudenext, and registers the PreToolUse hook in ~/.claude/settings.json.
set -euo pipefail

cd "$(dirname "$0")"

SUPPORT="$HOME/.claudenext"
APPS="$HOME/Applications"
HOOK="$SUPPORT/claudenext-hook.py"
SETTINGS="$HOME/.claude/settings.json"

./build.sh

echo "==> Installing to $APPS"
mkdir -p "$APPS" "$SUPPORT"
rm -rf "$APPS/ClaudeNext.app"
cp -R "dist/ClaudeNext.app" "$APPS/ClaudeNext.app"

echo "==> Installing hook to $HOOK"
cp "hooks/claudenext-hook.py" "$HOOK"
chmod +x "$HOOK"

if [ ! -f "$SUPPORT/config.json" ]; then
  cat > "$SUPPORT/config.json" <<'JSON'
{
  "port": 4471,
  "sound": true,
  "focusOnRequest": true,
  "rememberScope": "project",
  "intercept": ["Bash", "Write", "Edit", "MultiEdit", "NotebookEdit", "WebFetch", "mcp__*"],
  "ignore": [],
  "timeout": 280
}
JSON
  echo "    wrote default config"
fi

echo "==> Registering PreToolUse hook in $SETTINGS"
mkdir -p "$(dirname "$SETTINGS")"
HOOK_PATH="$HOOK" python3 - "$SETTINGS" <<'PY'
import json, os, sys

path = sys.argv[1]
hook_path = os.environ["HOOK_PATH"]

try:
    with open(path, encoding="utf-8") as fh:
        settings = json.load(fh)
    if not isinstance(settings, dict):
        settings = {}
except (OSError, ValueError):
    settings = {}

hooks = settings.setdefault("hooks", {})
matchers = hooks.setdefault("PreToolUse", [])

entry = {
    "matcher": "*",
    "hooks": [{"type": "command", "command": hook_path, "timeout": 300}],
}

def is_ours(m):
    return any(h.get("command", "").endswith("claudenext-hook.py")
               for h in m.get("hooks", []) if isinstance(h, dict))

matchers[:] = [m for m in matchers if isinstance(m, dict) and not is_ours(m)]
matchers.append(entry)

os.makedirs(os.path.dirname(path), exist_ok=True)
tmp = path + ".tmp"
with open(tmp, "w", encoding="utf-8") as fh:
    json.dump(settings, fh, indent=2)
    fh.write("\n")
os.replace(tmp, path)
print(f"    hook registered ({hook_path})")
PY

echo "==> Launching"
open -a "$APPS/ClaudeNext.app"

cat <<'EOF'

ClaudeNext is running — look for the spark in your menu bar.

Restart any open Claude Code session so it picks up the new hook, then try:
    claude
    > run `echo hello` in bash

To uninstall:  ./uninstall.sh
EOF
