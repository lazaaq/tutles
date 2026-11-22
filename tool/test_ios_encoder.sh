#!/usr/bin/env bash
# Tests ios/Runner/ImageEncoder.swift on macOS (same ImageIO / Core Graphics APIs as iOS),
# without a simulator or device.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

xcrun swiftc -O -target "$(uname -m)-apple-macos13" \
  "$ROOT/ios/Runner/ImageEncoder.swift" "$ROOT/ios/EncoderTests/main.swift" \
  -o "$WORK/encoder-tests"

"$WORK/encoder-tests" "$WORK"
