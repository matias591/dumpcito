#!/usr/bin/env bash
# Builds Dumpcito.app and launches it.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
pkill -x Dumpcito 2>/dev/null || true
"$ROOT/scripts/build-app.sh"
open "$ROOT/build/Dumpcito.app"
