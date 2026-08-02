#!/usr/bin/env bash
# Builds ClaudeNext.app into ./dist
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="ClaudeNext"
DIST="dist"
APP="$DIST/$APP_NAME.app"

echo "==> Compiling (release)"
swift build -c release

BIN="$(swift build -c release --show-bin-path)/$APP_NAME"
[ -x "$BIN" ] || { echo "build produced no binary at $BIN" >&2; exit 1; }

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key><string>ClaudeNext</string>
	<key>CFBundleDisplayName</key><string>ClaudeNext</string>
	<key>CFBundleIdentifier</key><string>com.claudenext.menubar</string>
	<key>CFBundleExecutable</key><string>ClaudeNext</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>1.0.0</string>
	<key>CFBundleVersion</key><string>1</string>
	<key>LSMinimumSystemVersion</key><string>14.0</string>
	<key>LSUIElement</key><true/>
	<key>NSHighResolutionCapable</key><true/>
	<key>NSSupportsAutomaticTermination</key><false/>
	<key>NSSupportsSuddenTermination</key><false/>
</dict>
</plist>
PLIST

echo "==> Signing (ad-hoc)"
# iCloud and Finder leave xattrs behind that codesign refuses to sign over.
xattr -cr "$APP" 2>/dev/null || true
if codesign --force --sign - --timestamp=none "$APP" 2>/dev/null; then
  echo "    signed"
else
  echo "    (ad-hoc signing skipped; the linker-signed binary still runs)"
fi

echo "==> Done: $APP"
