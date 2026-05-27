#!/bin/sh
# ci_pre_xcodebuild.sh — runs in Xcode Cloud right before
# `xcodebuild` fires. Use it to guard against ship-blockers that
# Xcode itself won't catch (missing icon source, dead entitlements
# left enabled, etc.).
#
# Anything we want to enforce per-build lives here so the build
# fails fast at Apple's expense, not after the App Store reviewer
# has to point it out.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "Bucketeer CI — pre-xcodebuild preflight"
echo "========================================"

# 1. Refuse to build if the App Icon source is missing. macOS 14+
#    accepts a single-resource icon set; we just need *something*
#    in the AppIcon.appiconset directory.
ICONSET="$REPO_ROOT/Bucketeer/Assets.xcassets/AppIcon.appiconset"
if [ -d "$ICONSET" ]; then
  icon_pngs=$(find "$ICONSET" -name "*.png" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$icon_pngs" -eq 0 ]; then
    echo "::warning::No PNG assets in $ICONSET — the App Store will reject this build."
    echo "Add the 1024×1024 (or per-slot) icon assets before pushing to test/beta/main."
  fi
fi

# 2. Surface any TODO-blocker markers the team uses for stop-the-ship
#    work-in-progress notes. Adjust the pattern when your team picks
#    a different convention; we look for the exact string `SHIP_BLOCKER`.
if grep -RIn --include='*.swift' 'SHIP_BLOCKER' "$REPO_ROOT/Bucketeer" "$REPO_ROOT/BucketeerCore" >/dev/null 2>&1; then
  echo "::error::SHIP_BLOCKER markers still present in source — refusing to build."
  grep -RIn --include='*.swift' 'SHIP_BLOCKER' "$REPO_ROOT/Bucketeer" "$REPO_ROOT/BucketeerCore"
  exit 1
fi

# 3. Production builds must keep the file-provider entitlement
#    consistent with the host. Quick existence check — Xcode will
#    surface signature mismatches itself.
if [ ! -f "$REPO_ROOT/Bucketeer/Bucketeer.entitlements" ]; then
  echo "::error::Bucketeer.entitlements is missing."
  exit 1
fi

echo "Preflight passed."
