#!/bin/zsh
# Builds Pingo.app in the current directory.
set -e
cd "$(dirname "$0")"

APP="Pingo.app"
ICON_SOURCE="assets/pingo.png"
ICON_OUTPUT="assets/Pingo.icns"
TEMP_DIR="$(mktemp -d)"
ICONSET="$TEMP_DIR/Pingo.iconset"
trap 'rm -rf "$TEMP_DIR"' EXIT

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ICONSET"
cp Info.plist "$APP/Contents/Info.plist"

for icon_size in 16 32 128 256 512; do
	retina_size=$((icon_size * 2))
	sips -z "$icon_size" "$icon_size" "$ICON_SOURCE" \
		--out "$ICONSET/icon_${icon_size}x${icon_size}.png" >/dev/null
	sips -z "$retina_size" "$retina_size" "$ICON_SOURCE" \
		--out "$ICONSET/icon_${icon_size}x${icon_size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$ICON_OUTPUT"
cp "$ICON_OUTPUT" "$APP/Contents/Resources/Pingo.icns"

swiftc -O -o "$APP/Contents/MacOS/Pingo" main.swift
codesign --force --sign - "$APP"
echo "Built $APP — launch with: open $APP"
