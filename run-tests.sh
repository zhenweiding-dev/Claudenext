#!/usr/bin/env bash
# Compiles the app and runs the hook test suites.
set -euo pipefail

cd "$(dirname "$0")"

echo "==> swift build"
swift build -c release >/dev/null

echo "==> tests/config_roundtrip.swift"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
swiftc -O Sources/ClaudeNext/AppConfig.swift Sources/ClaudeNext/ProjectRules.swift tests/config_roundtrip.swift \
  -o "$WORK/config_roundtrip" 2>&1 | grep -v "^$" || true
CLAUDENEXT_HOME="$WORK/support" "$WORK/config_roundtrip"

echo "==> tests/test_rules.py"
python3 tests/test_rules.py

echo "==> tests/test_integration.py"
python3 tests/test_integration.py

echo "==> concurrent writers (app + hook on one project file)"
swiftc -O Sources/ClaudeNext/ProjectRules.swift tests/concurrent_writer.swift \
  -o "$WORK/concurrent_writer" 2>&1 | grep -v "^$" || true
PROJ="$WORK/proj"
mkdir -p "$PROJ/.claude"
"$WORK/concurrent_writer" "$PROJ" 40 &
python3 - "$PROJ" 40 <<'PY' &
import importlib.util, sys
spec = importlib.util.spec_from_file_location("hook", "hooks/claudenext-hook.py")
hook = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hook)
for i in range(int(sys.argv[2])):
    hook.save_rule(sys.argv[1], f"Bash(cmd{i}:*)", "allow")
PY
wait
python3 - "$PROJ/.claude/claudenext.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
assert len(data.get("allow", [])) == 40, f"lost rules: {len(data.get('allow', []))}/40"
assert data.get("intercept"), "lost the intercept write"
print("concurrent_writers: all pass (40 rules + intercept survived)")
PY

echo "==> all green"
