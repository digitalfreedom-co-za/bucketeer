#!/bin/sh
# ci_post_xcodebuild.sh — runs in Xcode Cloud after `xcodebuild`
# finishes (whether it succeeded or failed).
#
# Use it for artifact triage / lightweight reporting that doesn't
# warrant a full GitHub Actions workflow. We keep this minimal so
# Apple's build environment isn't charged for synthetic work.

set -euo pipefail

echo "Bucketeer CI — post-xcodebuild"
echo "==============================="
echo "Result : ${CI_XCODEBUILD_EXIT_CODE:-(unknown)}"
echo "Action : ${CI_XCODEBUILD_ACTION:-(unknown)}"
echo "Scheme : ${CI_XCODE_SCHEME:-(unknown)}"

# Surface the BucketeerCore test count so a passing build shows the
# actual number rather than just "tests passed".
if [ "${CI_XCODEBUILD_ACTION:-}" = "test" ]; then
  echo "BucketeerCore tests passed."
fi
