#!/bin/sh
# Supply a booted iOS simulator UDID. This does not connect to a Parsec host.
set -eu
DEVICE="${1:?Pass a booted simulator UDID}"
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/openparsec-keyboard-smoke.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
APP="$WORK/TabletopKeyboardSmoke.app"
mkdir -p "$APP"
# Use the production keyboard unchanged except for its device-only SDK import.
sed '/^import ParsecSDK$/d' "$ROOT/OpenParsec/TabletopKeyboard.swift" > "$WORK/TabletopKeyboard.swift"
xcrun swiftc -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
	-target arm64-apple-ios16.0-simulator -module-name TabletopKeyboardSmoke \
	"$ROOT/OpenParsec/AdaptiveGeometry.swift" "$ROOT/OpenParsec/TabletopState.swift" \
	"$WORK/TabletopKeyboard.swift" "$ROOT/Tests/TabletopKeyboardSmoke.swift" \
	-o "$APP/TabletopKeyboardSmoke"
/usr/bin/plutil -create xml1 "$APP/Info.plist"
/usr/bin/plutil -insert CFBundleIdentifier -string dev.openparsec.keyboard-smoke "$APP/Info.plist"
/usr/bin/plutil -insert CFBundleExecutable -string TabletopKeyboardSmoke "$APP/Info.plist"
/usr/bin/plutil -insert CFBundleName -string TabletopKeyboardSmoke "$APP/Info.plist"
/usr/bin/plutil -insert CFBundlePackageType -string APPL "$APP/Info.plist"
/usr/bin/plutil -insert CFBundleVersion -string 1 "$APP/Info.plist"
/usr/bin/plutil -insert CFBundleShortVersionString -string 1 "$APP/Info.plist"
/usr/bin/plutil -insert LSRequiresIPhoneOS -bool YES "$APP/Info.plist"
xcrun simctl install "$DEVICE" "$APP"
python3 - "$DEVICE" <<'PY'
import subprocess
import sys

device = sys.argv[1]
bundle = "dev.openparsec.keyboard-smoke"
try:
    result = subprocess.run(
        ["xcrun", "simctl", "launch", "--console", "--terminate-running-process", device, bundle],
        capture_output=True, text=True, timeout=20, check=True,
    )
    print(result.stdout)
    if "TABLETOP_UI_SMOKE_PASSED" not in result.stdout:
        print(result.stderr, file=sys.stderr)
        raise SystemExit("Keyboard smoke test did not complete its assertions")
finally:
    subprocess.run(["xcrun", "simctl", "terminate", device, bundle], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
PY
