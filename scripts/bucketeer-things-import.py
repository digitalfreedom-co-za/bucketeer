#!/usr/bin/env python3
"""
bucketeer-things-import.py — push every credential-bound / GUI-bound
v1.0 release TODO into Things via the `things:///json` URL scheme.

Things JSON spec: https://culturedcode.com/things/support/articles/2803573/

Run from anywhere:
    python3 scripts/bucketeer-things-import.py

Things 3.app opens a confirmation dialog (or imports silently if
auto-import is enabled in the JSON URL scheme) and adds:

  - one project "Bucketeer v1.0 release"
  - per-area todos with notes pointing at the canonical doc in the
    repo (RELEASE_v1.0.md, DEEP_LINKS.md, PHASE_9_SETUP.md, etc.)
"""

import json
import subprocess
import urllib.parse
import sys

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def todo(title, notes="", tags=None, checklist=None):
    """One Things to-do dict."""
    attrs = {"title": title}
    if notes:
        attrs["notes"] = notes
    if tags:
        attrs["tags"] = tags
    if checklist:
        attrs["checklist-items"] = [
            {"type": "checklist-item", "attributes": {"title": item}}
            for item in checklist
        ]
    return {"type": "to-do", "attributes": attrs}


# ---------------------------------------------------------------------------
# Project + items
# ---------------------------------------------------------------------------

REPO = "github.com/digitalfreedom-co-za/bucketeer"
TAG_RELEASE = "bucketeer-v1"
TAG_DEVAPPLE = "developer.apple.com"
TAG_ASC = "app-store-connect"
TAG_XCODE = "xcode"
TAG_TEST = "testflight"
TAG_FOLLOWUP = "v1.1"


items = [
    # ----------------------------------------------------------------------
    # Xcode-side manual work
    # ----------------------------------------------------------------------
    todo(
        "Add File Provider Extension target in Xcode",
        notes=(
            "Manual Xcode step — pbxproj edit is too risky to automate.\n\n"
            "Follow PHASE_9_SETUP.md in the repo. Highlights:\n"
            "  • New target: macOS → File Provider Extension\n"
            "  • Bundle ID: za.co.digitalfreedom.Bucketeer.FileProvider\n"
            "  • Link BucketeerCore (local SPM package)\n"
            "  • Reuse Bucketeer File Provider/*.swift sources\n"
            "  • Entitlements: app-sandbox, network.client, App Group, "
            "Keychain Sharing\n"
            "  • Embed in host target\n\n"
            f"Repo: {REPO}\n"
            "Doc: PHASE_9_SETUP.md"
        ),
        tags=[TAG_RELEASE, TAG_XCODE],
        checklist=[
            "Create File Provider Extension target in Xcode",
            "Set bundle id za.co.digitalfreedom.Bucketeer.FileProvider",
            "Link BucketeerCore",
            "Copy existing extension sources into the target",
            "Configure entitlements (sandbox + network + App Group + Keychain)",
            "Embed extension in host target's Embed App Extensions build phase",
            "Archive locally → verify both binaries get signed cleanly",
        ],
    ),

    # ----------------------------------------------------------------------
    # developer.apple.com
    # ----------------------------------------------------------------------
    todo(
        "Register App Group: group.za.co.digitalfreedom.bucketeer",
        notes=(
            "developer.apple.com → Certificates, Identifiers & Profiles "
            "→ Identifiers → App Groups.\n\n"
            "Add identifier:\n"
            "  group.za.co.digitalfreedom.bucketeer\n\n"
            "Then attach to BOTH:\n"
            "  • za.co.digitalfreedom.Bucketeer (host)\n"
            "  • za.co.digitalfreedom.Bucketeer.FileProvider (extension)\n\n"
            "The App Group is the only way the File Provider extension can "
            "read account metadata. Without it, sandbox-isolated extension "
            "can't see the host's SwiftData store.\n\n"
            "Bucketeer.entitlements already references the group — Xcode "
            "will fail to sign until the developer-portal record exists."
        ),
        tags=[TAG_RELEASE, TAG_DEVAPPLE],
    ),
    todo(
        "Register Keychain Sharing group: za.co.digitalfreedom.bucketeer.shared",
        notes=(
            "developer.apple.com → Identifiers → Keychain Sharing\n\n"
            "Add identifier:\n"
            "  za.co.digitalfreedom.bucketeer.shared\n\n"
            "Attach to host + extension (same pair as App Group). The shared "
            "Keychain access group is how the File Provider extension reads "
            "credentials without re-prompting the user.\n\n"
            "Bucketeer.entitlements already references it; sign will fail "
            "until registered."
        ),
        tags=[TAG_RELEASE, TAG_DEVAPPLE],
    ),
    todo(
        "Delete dead App Groups: boatcare + s3-browser",
        notes=(
            "Flagged earlier in the session. Old groups left over from "
            "previous projects:\n\n"
            "  • group.boatcare\n"
            "  • group.s3-browser\n\n"
            "developer.apple.com → Identifiers → App Groups → select → "
            "Remove.\n\n"
            "Cosmetic, not blocking, but they show up in every signing-"
            "config picker."
        ),
        tags=[TAG_DEVAPPLE],
    ),

    # ----------------------------------------------------------------------
    # App Store Connect
    # ----------------------------------------------------------------------
    todo(
        "Create app record in App Store Connect",
        notes=(
            "appstoreconnect.apple.com → My Apps → New macOS App\n\n"
            "Bundle ID: za.co.digitalfreedom.Bucketeer (matches "
            "PRODUCT_BUNDLE_IDENTIFIER in the Xcode project)\n"
            "SKU: Bucketeer-v1\n"
            "Primary language: English (United States)\n\n"
            "docs/APP_STORE_METADATA.md in the repo has every other field "
            "ready (description, keywords, support / marketing / privacy "
            "URLs, app category Developer Tools, age rating 4+)."
        ),
        tags=[TAG_RELEASE, TAG_ASC],
    ),
    todo(
        "Register Bucketeer Pro IAP",
        notes=(
            "App Store Connect → Bucketeer → Features → In-App Purchases\n\n"
            "Create Non-Consumable:\n"
            "  Reference name: Bucketeer Pro Lifetime\n"
            "  Product ID: za.co.digitalfreedom.bucketeer.pro.lifetime\n"
            "  Price tier: Tier 15 (~€14.99)\n"
            "  Family Sharing: Enabled\n"
            "  Cleared for sale: Yes\n\n"
            "Localized display name + description per locale (en/de drafts "
            "in docs/APP_STORE_METADATA.md)."
        ),
        tags=[TAG_RELEASE, TAG_ASC],
        checklist=[
            "Reference name",
            "Product ID exactly as specified",
            "Price tier 15",
            "Family Sharing enabled",
            "Localized name + description per locale",
            "Cleared for sale",
        ],
    ),
    todo(
        "Upload App Store description + keywords + URLs",
        notes=(
            "Copy from docs/APP_STORE_METADATA.md — Description (4000 chars), "
            "Keywords (100 chars), Promotional text (170 chars), What's New.\n"
            "\n"
            "URLs:\n"
            "  Support: https://support.apps.digitalfreedom.co.za/\n"
            "  Marketing: https://digitalfreedom.co.za\n"
            "  Privacy: https://github.com/digitalfreedom-co-za/bucketeer/"
            "blob/main/Bucketeer/Resources/Legal/PRIVACY_POLICY.md"
        ),
        tags=[TAG_RELEASE, TAG_ASC],
    ),
    todo(
        "Capture + upload 9-shot screenshot set per locale",
        notes=(
            "Set listed in docs/APP_STORE_METADATA.md §Screenshots:\n\n"
            "  1. Browser with populated bucket + Quick Look preview\n"
            "  2. Add-account sheet provider picker (Azure highlighted)\n"
            "  3. Sync Jobs list with running job + watch folder row\n"
            "  4. Bucket Dashboard sheet with cost estimate\n"
            "  5. Activity Log window with rows for upload/delete/sync\n"
            "  6. Settings → Encryption tab with registered BYOK keys\n"
            "  7. Settings → Pro tab with price visible\n"
            "  8. Finder showing mounted bucket under Locations\n"
            "  9. Menubar popover with two transfers in flight\n\n"
            "Minimum 1280×800; recommended 2880×1800 for retina. Light + "
            "dark mode pair if Apple still requires it."
        ),
        tags=[TAG_RELEASE, TAG_ASC],
    ),
    todo(
        "Set up content rights + encryption declarations",
        notes=(
            "App Store Connect → App Information.\n\n"
            "Content rights: 'No' to 'uses third-party content' (Bucketeer "
            "doesn't bundle media).\n\n"
            "Encryption: ITSAppUsesNonExemptEncryption=NO is already set in "
            "the Xcode project. Confirm in ASC → App Privacy section."
        ),
        tags=[TAG_RELEASE, TAG_ASC],
    ),

    # ----------------------------------------------------------------------
    # Xcode Cloud
    # ----------------------------------------------------------------------
    todo(
        "Configure Xcode Cloud workflow: test branch → TestFlight Internal",
        notes=(
            "appstoreconnect.apple.com → Xcode Cloud → Workflows → New.\n\n"
            "Start condition: push to branch `test`\n"
            "Actions: Archive (macOS) → Submit to TestFlight Internal Testing\n\n"
            "Scripts in ci_scripts/ are auto-discovered by Xcode Cloud:\n"
            "  ci_post_clone.sh — environment dump\n"
            "  ci_pre_xcodebuild.sh — SHIP_BLOCKER + icon checks\n"
            "  ci_post_xcodebuild.sh — minimal summary\n\n"
            "Wiki ref: ~/Developer/projects/wiki/apple-native-apps.md"
        ),
        tags=[TAG_RELEASE, TAG_ASC],
    ),
    todo(
        "Configure Xcode Cloud workflow: beta branch → TestFlight External",
        notes=(
            "Start condition: push to branch `beta`\n"
            "Actions: Archive → TestFlight External\n\n"
            "External beta needs Apple review pass (~24h first time, "
            "then 1-2h per build). Plan around it."
        ),
        tags=[TAG_RELEASE, TAG_ASC],
    ),
    todo(
        "Configure Xcode Cloud workflow: main branch → App Store submit",
        notes=(
            "Start condition: push to branch `main`\n"
            "Actions: Archive → submit to App Store review\n\n"
            "Use Apple's automatic phased release setting so a regression "
            "doesn't go to every user on day 1."
        ),
        tags=[TAG_RELEASE, TAG_ASC],
    ),

    # ----------------------------------------------------------------------
    # TestFlight smoke test (the 22-step plan from RELEASE_v1.0.md)
    # ----------------------------------------------------------------------
    todo(
        "Run the 22-step TestFlight smoke-test plan",
        notes=(
            "docs/RELEASE_v1.0.md §TestFlight smoke-test plan covers the "
            "full surface: browser+transfers / 13.x features / Azure "
            "parity / Pro paywall / Crash recovery.\n\n"
            "If any step fails, fix on development first — don't promote "
            "beta → main with failing steps."
        ),
        tags=[TAG_RELEASE, TAG_TEST],
        checklist=[
            "Add AWS + Cloudflare R2 + Azure accounts",
            "Drill 2-3 folders deep, drag 1MB + 100MB file in",
            "1GB upload with mid-transfer network cut → resume works",
            "Bandwidth limit 1MB/s — verify throttle",
            "Activity Log ⌘⌥0 — shows every prior step + CSV export",
            "Trash ⌘⇧⌫ — small delete → Restore works; 100MB delete → 'Too large'",
            "Bucket Dashboard — cost estimate + top-10 list correct",
            "Versions browser — restore middle revision",
            "Metadata + Tags editor — add tag, change Cache-Control, save",
            "Auto-tagging rule *.pdf → project=demo applies after upload",
            "Encryption: 10MB roundtrip OK; AWS-console shows envelope",
            "Shortcuts: 'Upload File with Bucketeer' — both shortcuts land",
            "Spotlight: enable indexing, search filename, click opens App",
            "open bucketeer://activity from Terminal focuses Activity",
            "Azure: upload + delete on container",
            "Azure: show versions on blob with snapshot, restore",
            "Azure: Metadata & Tags editor — round-trip a tag + x-ms-meta-*",
            "Trial expiry: 4 Pro pillars redirect to paywall",
            "Buy Pro: pillars unlock",
            "Restore Purchases on fresh Family-Sharing device",
            "Force-quit during 500MB upload → resumes",
            "Force-quit during cross-account move → no orphan staging file",
        ],
    ),

    # ----------------------------------------------------------------------
    # v1.1 follow-ups (deferred from RELEASE_v1.0.md)
    # ----------------------------------------------------------------------
    todo(
        "[v1.1] Parallel-part resumable uploads",
        notes=(
            "Current S3ResumableUploader is sequential for correctness. "
            "Throughput hit is acceptable at the ≥ 50 MB band but a v1.1 "
            "fan-out under a semaphore would close the gap with Soto's "
            "non-resumable parallel helper.\n\n"
            "Implementation sketch:\n"
            "  • withTaskGroup over part numbers\n"
            "  • semaphore (e.g. max 4 in flight)\n"
            "  • lock checkpoint writes with an actor\n"
            "  • on cancellation, persist partial state before exit\n\n"
            "File: BucketeerCore/Sources/BucketeerCore/Services/S3/"
            "S3ResumableUploader.swift"
        ),
        tags=[TAG_FOLLOWUP],
    ),
    todo(
        "[v1.1] Azure ARM management-plane: lifecycle / CORS / policy",
        notes=(
            "loadInsights currently throws featureNotSupported for Azure "
            "accounts because lifecycle / CORS / policies live on the "
            "Azure Resource Manager (management plane) — OAuth-authenticated, "
            "completely separate from the Shared-Key-signed data plane.\n\n"
            "Implementation sketch:\n"
            "  • Add OAuth client (MSAL or hand-rolled) — service principal\n"
            "  • New AzureManagementClient that holds the AAD token\n"
            "  • Implement GET storage-account properties + lifecycle rules\n"
            "  • Wire into AzureBlobObjectStore.loadInsights\n\n"
            "Auth surface is the hard part. Microsoft's docs are at:\n"
            "  https://learn.microsoft.com/azure/storage/blobs/lifecycle-management-overview"
        ),
        tags=[TAG_FOLLOWUP],
    ),
    todo(
        "[v1.1] Hardware-key unlock gate replacement (CryptoTokenKit)",
        notes=(
            "Phase 13.16 shipped detection + settings preview. The actual "
            "secret-reveal gate replacement is deferred because validating "
            "across multiple YubiKey / PIV combinations needs real hardware.\n\n"
            "Implementation sketch:\n"
            "  • TKTokenWatcher to enumerate identities\n"
            "  • PIV applet: select AID A0 00 00 03 08 00 00 10 00 01 00\n"
            "  • Use SecKeyCreateSignature for a PIN-protected challenge\n"
            "  • Successful PIN entry counts as 'unlocked' for KeychainStore\n\n"
            "Hardware test matrix: YubiKey 5 series (USB-A/C/NFC), Feitian "
            "ePass FIDO, PIV-only smartcards via a Cherry/Identiv reader.\n\n"
            "File: Bucketeer/Services/HardwareKey/HardwareKeyAvailability.swift"
        ),
        tags=[TAG_FOLLOWUP],
        checklist=[
            "Buy/borrow a YubiKey 5 NFC for testing",
            "Buy/borrow a YubiKey 5C for second-form-factor coverage",
            "Buy/borrow a Cherry SmartTerminal ST-1144 reader",
            "Test PIV applet detection across all three",
            "Implement TKTokenWatcher-based gate",
            "Replace LAContext.deviceOwnerAuthentication call with HW path when enabled",
        ],
    ),
    todo(
        "[v1.1] Sync-job-detail window for bucketeer://sync/<id>",
        notes=(
            "Currently bucketeer://sync/<jobUUID> just focuses the main "
            "window and lets the user click into Sync. A dedicated "
            "detail window would be nicer — show recent runs, the diff "
            "summary, and the next scheduled trigger.\n\n"
            "File: Bucketeer/Services/DeepLink/DeepLinkRouter.swift "
            "(case .syncJob)"
        ),
        tags=[TAG_FOLLOWUP],
    ),
    todo(
        "[v1.1] Read tags on demand instead of with HEAD",
        notes=(
            "loadMetadata fires HEAD + GET tags in series. Could be one "
            "round-trip if the user only wants metadata or only wants "
            "tags. Open as a perf TODO once telemetry from real usage "
            "shows whether the second hop is noticeable."
        ),
        tags=[TAG_FOLLOWUP],
    ),
    todo(
        "[v1.1] Codex review round 4",
        notes=(
            "Two rounds done so far (35 findings, all addressed). A "
            "fresh round after the v1.0 cut and any post-launch "
            "patches catches whatever the previous rounds missed and "
            "any new code shipped during external beta.\n\n"
            "Repo: scripts/preflight.sh runs the test suite the audit "
            "depends on; run that first."
        ),
        tags=[TAG_FOLLOWUP],
    ),
]

project = {
    "type": "project",
    "attributes": {
        "title": "Bucketeer v1.0 release",
        "notes": (
            "Generated by scripts/bucketeer-things-import.py.\n\n"
            "Everything that needs to happen to ship Bucketeer v1.0 to "
            "the Mac App Store, organised by area (Xcode-side, "
            "developer.apple.com, App Store Connect, Xcode Cloud, "
            "TestFlight smoke test, v1.1 follow-ups).\n\n"
            f"Repo: {REPO}\n"
            "Canonical doc: docs/RELEASE_v1.0.md\n"
            "Architecture: docs/ARCHITECTURE.md\n"
            "App Store metadata: docs/APP_STORE_METADATA.md\n"
            "Pre-release CI: .github/workflows/ci.yml + ci_scripts/\n"
            "Local preflight: scripts/preflight.sh"
        ),
        "tags": [TAG_RELEASE],
        "items": items,
    },
}

payload = [project]
encoded = urllib.parse.quote(json.dumps(payload), safe="")
url = f"things:///json?data={encoded}"

print(f"Pushing {len(items)} todos into Things …")
result = subprocess.run(["open", url], capture_output=True, text=True)
if result.returncode == 0:
    print("Done. Check Things 3 for the 'Bucketeer v1.0 release' project.")
else:
    print("open(1) failed:", result.stderr, file=sys.stderr)
    sys.exit(1)
