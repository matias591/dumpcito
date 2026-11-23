#!/usr/bin/env bash
# Builds build/Dumpcito.app, then build/Dumpcito.zip and its SHA-256. Use when a DMG is not needed.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
"$ROOT/scripts/build-app.sh"
rm -f build/Dumpcito.zip build/Dumpcito.zip.sha256
ditto -c -k --keepParent build/Dumpcito.app build/Dumpcito.zip
(cd build && shasum -a 256 Dumpcito.zip > Dumpcito.zip.sha256)
echo "Built build/Dumpcito.zip"
cat build/Dumpcito.zip.sha256
