#!/usr/bin/env bash
# Builds build/Dumpcito.app, then a drag-to-Applications disk image and its SHA-256.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

"$ROOT/scripts/build-app.sh"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R build/Dumpcito.app "$STAGE/Dumpcito.app"
ln -s /Applications "$STAGE/Applications"

rm -f build/Dumpcito.dmg build/Dumpcito.dmg.sha256
hdiutil create -volname "Dumpcito" -srcfolder "$STAGE" -ov -format UDZO build/Dumpcito.dmg >/dev/null
(cd build && shasum -a 256 Dumpcito.dmg > Dumpcito.dmg.sha256)
echo "Built build/Dumpcito.dmg"
cat build/Dumpcito.dmg.sha256
