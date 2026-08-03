#!/usr/bin/env bash
# Compiles the app and runs the hook test suites.
set -euo pipefail

cd "$(dirname "$0")"

echo "==> swift build"
swift build -c release >/dev/null

echo "==> tests/config_roundtrip.swift"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
swiftc -O Sources/ClaudeNext/AppConfig.swift Sources/ClaudeNext/ProjectScope.swift tests/config_roundtrip.swift \
  -o "$WORK/config_roundtrip" 2>&1 | grep -v "^$" || true
CLAUDENEXT_HOME="$WORK/support" "$WORK/config_roundtrip"

echo "==> tests/test_rules.py"
python3 tests/test_rules.py

echo "==> tests/test_integration.py"
python3 tests/test_integration.py

echo "==> concurrent writers (app + hook on one project file)"
swiftc -O Sources/ClaudeNext/ProjectScope.swift tests/concurrent_writer.swift \
  -o "$WORK/concurrent_writer" 2>&1 | grep -v "^$" || true
PROJ="$WORK/proj"
mkdir -p "$PROJ/.claude"
save_rules() {
python3 - "$PROJ" "$1" 40 <<'HOOKPY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("hook", "hooks/claudenext-hook.py")
hook = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hook)
for i in range(int(sys.argv[3])):
    hook.save_rule(sys.argv[1], f"Bash({sys.argv[2]}{i}:*)", "allow")
HOOKPY
}

# two Claude Code sessions saving rules at once, plus the app writing scope
"$WORK/concurrent_writer" "$PROJ" 40 &
save_rules sessionA &
save_rules sessionB &
wait

python3 - "$PROJ" <<'CHECKPY'
import json, os, sys
proj = sys.argv[1]
perms = json.load(open(os.path.join(proj, ".claude", "settings.local.json")))["permissions"]
assert len(perms["allow"]) == 80, f"lost rules: {len(perms['allow'])}/80"
scope = json.load(open(os.path.join(proj, ".claude", "claudenext.json")))
assert scope.get("intercept"), "lost the intercept write"
print("concurrent_writers: all pass (80 rules from 2 sessions + intercept survived)")
CHECKPY

echo "==> all green"
