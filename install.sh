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

echo "==> Registering the login agent"
AGENT="$HOME/Library/LaunchAgents/com.claudenext.menubar.plist"
mkdir -p "$(dirname "$AGENT")"
cat > "$AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key><string>com.claudenext.menubar</string>
	<key>ProgramArguments</key>
	<array>
		<string>$APPS/ClaudeNext.app/Contents/MacOS/ClaudeNext</string>
	</array>
	<key>RunAtLoad</key><true/>
	<key>KeepAlive</key>
	<dict><key>SuccessfulExit</key><false/></dict>
	<key>ProcessType</key><string>Interactive</string>
</dict>
</plist>
PLIST

# Replace any previous instance so we do not end up with two menu bar icons.
pkill -x ClaudeNext 2>/dev/null || true
launchctl bootout "gui/$UID/com.claudenext.menubar" 2>/dev/null || true
sleep 1
launchctl bootstrap "gui/$UID" "$AGENT" 2>/dev/null || launchctl load -w "$AGENT"
# bootstrap does not always start it, and KeepAlive only covers crashes.
launchctl kickstart "gui/$UID/com.claudenext.menubar" 2>/dev/null || true

for _ in 1 2 3 4 5 6 7 8 9 10; do
  curl -fsS --max-time 2 "http://127.0.0.1:4471/health" >/dev/null 2>&1 && break
  sleep 1
done
if curl -fsS --max-time 2 "http://127.0.0.1:4471/health" >/dev/null 2>&1; then
  echo "    running and answering on 127.0.0.1:4471"
else
  echo "    WARNING: it did not come up. Try:"
  echo "      launchctl kickstart -k gui/$UID/com.claudenext.menubar"
fi

cat <<'EOF'

ClaudeNext is installed. Look for the spark in your menu bar.

It starts automatically at login from now on — there is nothing to run.

Restart any open Claude Code session so it picks up the new hook, then try:
    claude
    > run `echo hello` in bash

To uninstall:  ./uninstall.sh
EOF
