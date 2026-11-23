#!/usr/bin/env bash
# Builds build/Dumpcito.app from the SwiftPM release product and code-signs it.
#
# SIGNING NOTE: with no signing identity we ad-hoc sign ("-"). An ad-hoc signature's
# designated requirement is the code hash, which changes on every rebuild, so macOS
# treats each build as a new app and may re-prompt for Screen Recording / Microphone /
# Calendar after every rebuild.
# One-time fix: Keychain Access > Certificate Assistant > Create a Certificate...,
# Name "Dumpcito Dev", Identity Type "Self-Signed Root", Certificate Type "Code Signing".
# Then build with:  DUMPCITO_SIGN_IDENTITY="Dumpcito Dev" scripts/build-app.sh
# The stable identity keeps permission grants across rebuilds.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP="build/Dumpcito.app"
IDENTITY="${DUMPCITO_SIGN_IDENTITY:--}"
KEYCHAIN_ARGS=()
[ -n "${DUMPCITO_SIGN_KEYCHAIN:-}" ] && KEYCHAIN_ARGS=(--keychain "$DUMPCITO_SIGN_KEYCHAIN")

# Universal binary: runs natively on Apple Silicon and Intel Macs.
ARCHS=(--arch arm64 --arch x86_64)
swift build -c release --product Dumpcito --scratch-path .build-release "${ARCHS[@]}"
BIN_DIR="$(swift build -c release --product Dumpcito --scratch-path .build-release "${ARCHS[@]}" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Dumpcito" "$APP/Contents/MacOS/Dumpcito"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --options runtime --timestamp=none --sign "$IDENTITY" ${KEYCHAIN_ARGS[@]+"${KEYCHAIN_ARGS[@]}"} \
  --identifier com.matias.dumpcito \
  --entitlements Resources/Buddy.entitlements \
  "$APP"
codesign --verify --verbose "$APP"
echo "Built $APP (signed with: ${IDENTITY/-/ad-hoc})"
