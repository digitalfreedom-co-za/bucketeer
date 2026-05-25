#!/bin/sh
# preflight.sh — local sanity check before pushing to `test` /
# `beta` / `main`. Mirrors what Xcode Cloud's ci_pre_xcodebuild.sh
# enforces so the dev finds the issue at their desk instead of after
# triggering an Xcode Cloud build.
#
# Run with:    sh scripts/preflight.sh
#
# Exit codes:
#   0  everything OK
#   1  at least one ship-blocker

set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
status=0

red()    { printf '\033[31m%s\033[0m\n' "$1"; }
yellow() { printf '\033[33m%s\033[0m\n' "$1"; }
green()  { printf '\033[32m%s\033[0m\n' "$1"; }

echo "Bucketeer preflight"
echo "==================="

# 1. SHIP_BLOCKER markers
if grep -RIn --include='*.swift' 'SHIP_BLOCKER' "$REPO_ROOT/Bucketeer" "$REPO_ROOT/BucketeerCore" >/dev/null 2>&1; then
  red "SHIP_BLOCKER markers still present"
  grep -RIn --include='*.swift' 'SHIP_BLOCKER' "$REPO_ROOT/Bucketeer" "$REPO_ROOT/BucketeerCore"
  status=1
fi

# 2. App icon assets exist
ICONSET="$REPO_ROOT/Bucketeer/Assets.xcassets/AppIcon.appiconset"
if [ -d "$ICONSET" ]; then
  icon_pngs=$(find "$ICONSET" -name "*.png" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$icon_pngs" -eq 0 ]; then
    yellow "No PNG assets in $ICONSET — App Store will reject."
    status=1
  else
    green "App icon assets: $icon_pngs PNG(s)"
  fi
else
  yellow "AppIcon.appiconset missing"
fi

# 3. Entitlements files exist
for plist in Bucketeer/Bucketeer.entitlements; do
  if [ ! -f "$REPO_ROOT/$plist" ]; then
    red "Missing entitlements file: $plist"
    status=1
  fi
done

# 4. App Group + Keychain Sharing entries are commented out (until
#    they're registered at developer.apple.com — see CHANGELOG).
#    A live entry without the developer-portal registration causes
#    code-signing to fail. We warn rather than block because the
#    user might have completed the registration without telling us.
if grep -q '<string>group\.za\.co\.digitalfreedom\.bucketeer</string>' \
   "$REPO_ROOT/Bucketeer/Bucketeer.entitlements" 2>/dev/null; then
  yellow "App Group entitlement is enabled in entitlements file."
  yellow "Verify developer.apple.com has 'group.za.co.digitalfreedom.bucketeer'."
fi

# 5. BucketeerCore tests pass
if command -v swift >/dev/null 2>&1; then
  echo "Running BucketeerCore tests…"
  if ( cd "$REPO_ROOT" && swift test --package-path BucketeerCore >/tmp/bucketeer-preflight.log 2>&1 ); then
    green "BucketeerCore tests passed"
  else
    red "BucketeerCore tests FAILED — see /tmp/bucketeer-preflight.log"
    tail -30 /tmp/bucketeer-preflight.log
    status=1
  fi
else
  yellow "Swift toolchain not found; skipping test step."
fi

# 6. Working tree clean (so the push doesn't carry uncommitted work)
if [ -n "$(git -C "$REPO_ROOT" status --porcelain)" ]; then
  yellow "Working tree has uncommitted changes — push will not include them."
  git -C "$REPO_ROOT" status --short
fi

if [ "$status" -eq 0 ]; then
  green "Preflight passed — ready to push."
else
  red "Preflight failed — fix the issues above before pushing to test/beta/main."
fi
exit "$status"
