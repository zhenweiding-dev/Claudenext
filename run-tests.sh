#!/usr/bin/env bash
# Compiles the app and runs the hook test suites.
set -euo pipefail

cd "$(dirname "$0")"

echo "==> swift build"
swift build -c release >/dev/null

echo "==> tests/test_rules.py"
python3 tests/test_rules.py

echo "==> tests/test_integration.py"
python3 tests/test_integration.py

echo "==> all green"
