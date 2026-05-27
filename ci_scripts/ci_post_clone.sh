#!/bin/sh
# ci_post_clone.sh — runs in Xcode Cloud right after the clone step.
#
# Xcode Cloud auto-discovers this file via its `ci_scripts/` directory
# convention. Use it for any pre-build prep that the project itself
# can't express (Swift Package resolution, environment dumps, etc.).
#
# We deliberately keep this minimal: Xcode Cloud already resolves
# Swift Package dependencies before the build step, so the only thing
# we add is a versions dump that lands in the build log for triage.

set -euo pipefail

echo "Bucketeer CI — post-clone setup"
echo "================================"
echo "PWD                : $(pwd)"
echo "Xcode              : $(xcodebuild -version | head -1)"
echo "Swift              : $(swift --version | head -1)"
echo "Branch (CI_BRANCH) : ${CI_BRANCH:-(unset)}"
echo "Workflow           : ${CI_WORKFLOW:-(unset)}"
echo "Product            : ${CI_PRODUCT:-(unset)}"
