#!/bin/zsh
# Builds Pingo.app in the current directory.
set -e
cd "$(dirname "$0")"

APP="Pingo.app"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
ICON_SOURCE="assets/pingo.png"
ICON_MASTER="assets/pingo-app-icon.png"
ICON_OUTPUT="assets/Pingo.icns"
ICON_RENDERER="assets/render-app-icon.swift"
TEMP_DIR="$(mktemp -d)"
ICONSET="$TEMP_DIR/Pingo.iconset"
trap 'rm -rf "$TEMP_DIR"' EXIT

if pgrep -x Pingo >/dev/null; then
	print -u2 "Pingo is running. Quit it before rebuilding so macOS can validate the app signature."
	exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ICONSET"
cp Info.plist "$APP/Contents/Info.plist"

swift "$ICON_RENDERER" "$ICON_SOURCE" "$ICON_MASTER"
for icon_size in 16 32 128 256 512; do
	retina_size=$((icon_size * 2))
	sips -z "$icon_size" "$icon_size" "$ICON_MASTER" \
		--out "$ICONSET/icon_${icon_size}x${icon_size}.png" >/dev/null
	sips -z "$retina_size" "$retina_size" "$ICON_MASTER" \
		--out "$ICONSET/icon_${icon_size}x${icon_size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$ICON_OUTPUT"
cp "$ICON_OUTPUT" "$APP/Contents/Resources/Pingo.icns"

swiftc -O -o "$APP/Contents/MacOS/Pingo" main.swift

# Hardened Runtime (--options runtime) is required for notarization and blocks
# code injection into the running app. A secure timestamp is only meaningful
# with a real Developer ID, so skip it for ad-hoc ("-") signing to keep offline
# builds working.
codesign_flags=(--force --options runtime --sign "$SIGNING_IDENTITY")
if [[ "$SIGNING_IDENTITY" != "-" ]]; then
	codesign_flags+=(--timestamp)
fi
codesign "${codesign_flags[@]}" "$APP"
echo "Built $APP — launch with: open $APP"
