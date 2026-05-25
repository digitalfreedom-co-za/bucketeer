# Bucketeer v1.0 — release plan

This doc is the checklist + test-plan for the first Mac App Store
release. The phase-by-phase development history is in
[`CHANGELOG.md`](../CHANGELOG.md); the architecture is in
[`docs/ARCHITECTURE.md`](ARCHITECTURE.md). Read those first if you're
new to the codebase.

---

## Scope of v1.0

Everything on `development` at the v1.0 cut. That's:

- Phases 0 – 12 (browser + transfers + sandbox + Touch ID + Help /
  About + Civo migration + DNS error mapping + Privacy manifest).
- Phase A (Azure Blob Storage backend via `ProviderRouter`).
- Phase B (StoreKit 2 paywall, 14-day trial → free → €14.99 lifetime).
- Phases 9.5 – 9.10 (Core SPM package, test target, presigned URLs,
  local-folder sync, sync-on-change via FSEvents).
- Phase 13.1 – 13.16 (activity log, bandwidth limit, watch folders,
  trash, dashboard, versions, metadata editor, auto-tagging,
  lifecycle viewer, resumable uploads, deep links, App Intents,
  Spotlight, cross-account copy, client-side encryption, hardware
  key preview).
- Two Codex audit rounds — every blocker / high / medium / low
  finding addressed.
- Azure parity for object versions (snapshots), metadata + tags.

**Build state**: 135 BucketeerCore tests passing, host app builds
clean against macOS 14 deployment target on Xcode 16.

---

## Branch flow

```
development → test → beta → main
   (dev)      (CI)   (TF)    (prod)
```

| Branch | Purpose | CI trigger |
|---|---|---|
| `development` | active integration | GitHub Actions (test + unsigned build) |
| `test` | Xcode Cloud signed test build | Xcode Cloud workflow `test → Archive` |
| `beta` | TestFlight external | Xcode Cloud workflow `beta → Archive → TestFlight Internal` |
| `main` | App Store production | Xcode Cloud workflow `main → Archive → TestFlight External → App Store` |

GitHub Actions live in `.github/workflows/ci.yml` and do **no
signing** — they only catch broken tests / broken Debug builds.
Signed archive work happens in Xcode Cloud with the Apple Developer
credentials.

---

## Pre-release checklist (in order)

### 1. User-side manual work
- [ ] App icon ≥ 1024×1024 source PNG dropped into
      `Bucketeer/Assets.xcassets/AppIcon.appiconset/`
- [ ] Xcode project: enable URL Types for `bucketeer://` scheme
      (see [`docs/DEEP_LINKS.md`](DEEP_LINKS.md))
- [ ] Xcode project: add the File Provider Extension target per
      [`PHASE_9_SETUP.md`](../PHASE_9_SETUP.md)
- [ ] developer.apple.com: register App Group
      `group.za.co.digitalfreedom.bucketeer` and Keychain Sharing
      group `za.co.digitalfreedom.bucketeer.shared`
- [ ] developer.apple.com: clean up the now-dead App Groups
      (`boatcare`, `s3-browser`) flagged earlier in the session

### 2. App Store Connect setup
- [ ] Create app record with bundle id `za.co.digitalfreedom.Bucketeer`
- [ ] Register IAP `za.co.digitalfreedom.bucketeer.pro.lifetime` per
      [`docs/APP_STORE_METADATA.md`](APP_STORE_METADATA.md)
- [ ] Upload App Store description, keywords, support / marketing /
      privacy URLs (drafts in the same doc)
- [ ] Upload 9-shot screenshot set per locale

### 3. Xcode Cloud workflows
- [ ] Workflow A: `test` branch → Archive → upload to TestFlight Internal
- [ ] Workflow B: `beta` branch → Archive → upload to TestFlight External
- [ ] Workflow C: `main` branch → Archive → submit to App Store review

Each workflow uses the `ci_scripts/` directory we ship in the repo
(`ci_post_clone.sh`, `ci_pre_xcodebuild.sh`, `ci_post_xcodebuild.sh`).
`ci_pre_xcodebuild.sh` fails the build when:
- the App Icon source is missing
- a `SHIP_BLOCKER` marker is still in the Swift sources
- `Bucketeer.entitlements` is missing

### 4. Local sanity
- [ ] `sh scripts/preflight.sh` from the repo root passes cleanly
- [ ] `git status` is clean on `development` before promoting

---

## TestFlight smoke-test plan

The big chunks each tester should exercise on a fresh `beta` build:

### Browser + transfers
1. Add an account on each of the three preset families you have
   credentials for (AWS + Cloudflare R2 + Azure recommended).
2. Navigate into a bucket, drill 2-3 folders deep, drag a 1 MB and
   a 100 MB file in. Check Quick Look preview works for one of them.
3. Drag a 1 GB file in. The Resumable Multipart path kicks in
   (Phase 13.10) — pull the network cable mid-upload, plug back in,
   verify the upload resumes from the last completed part.
4. Bandwidth limit: in Settings → Transfers, set 1 MB/s and verify
   the next big upload throttles visibly.

### 13.x feature surface
5. Activity Log (⌘⌥0) — every prior step shows up; filter by kind
   and account; CSV export opens cleanly in Numbers.
6. Trash (⌘⇧⌫) — delete a small object, verify the local cache
   filled and the **Restore** button re-uploads it. Then delete a
   ≥ 100 MB object and verify the cache shows "Too large" — the
   row is metadata-only.
7. Bucket Dashboard (browser toolbar) — stats grid populates;
   monthly-cost estimate appears for non-MinIO providers; top-10
   largest list is correct.
8. Versions browser (right-click → Show Versions): on a versioning-
   enabled S3 bucket, upload 3 revisions of the same key, restore
   the middle one, verify it becomes the latest.
9. Metadata + Tags editor (right-click → Metadata & Tags…) — add a
   tag, change Cache-Control, save. Reopen to confirm round-trip.
10. Settings → Rules: create an auto-tagging rule
    `*.pdf → project=demo`. Upload a PDF. Verify the activity log
    shows the tag was applied.
11. Settings → Encryption: register a key for one bucket. Upload
    a 10 MB file, download it again — the round-trip yields identical
    bytes. Try downloading the same object through the AWS console
    — it should be the encrypted envelope, not the plaintext.
12. Shortcuts app: build a shortcut that calls "Upload File with
    Bucketeer". Run it twice and verify both uploads land.
13. Spotlight: enable indexing in Settings → Transfers; browse a
    folder; ⌘-space and search for one of the file names — clicking
    the result opens the App back to the right bucket.
14. Open `bucketeer://activity` from Terminal — the App focuses and
    opens the Activity Log window.

### Azure parity (Phase 13.6 / 13.7)
15. Connect an Azure Blob Storage account. List a container,
    upload + delete to make sure the data plane still works.
16. Right-click → Show Versions on an Azure blob that has at least
    one snapshot. Restore one. Delete one.
17. Right-click → Metadata & Tags… on an Azure blob — add a tag and
    a `x-ms-meta-*` entry. Save. Reopen to confirm both round-trip.

### Pro paywall
18. Wait out (or fast-forward via `Bucketeer.storekit`) the trial.
    Verify the four Pro pillars (Mount, Sync, Cross-account copy,
    Menubar) all redirect to the paywall sheet.
19. Buy Bucketeer Pro. Verify entitlement flips and pillars unlock.
20. Restore Purchases on a fresh sign-in / Family-Sharing device
    works without re-charging.

### Crash-recovery
21. Force-quit the App during a 500 MB upload. Re-launch. Verify
    the resumable path picks up from the last completed part.
22. Force-quit during a cross-account move. Re-launch. Verify the
    `CrossAccountStaging/` scavenger removed any orphan plaintext
    temp file.

If any of those 22 steps fails, **don't promote to `main`** —
report through the support URL and fix on `development` first.

---

## Post-launch follow-ups (v1.1 candidates)

- Resumable parallel parts (current resumable path is sequential
  for correctness; throughput hit is acceptable for v1).
- Azure ARM management-plane integration for lifecycle / CORS /
  policy viewer (currently `featureNotSupported` for Azure).
- Hardware-key unlock gate replacement (CryptoTokenKit detection
  shipped in 13.16 as preview; the actual secret-reveal gate
  swap follows after wider device validation).
- Per-account Spotlight purge (today's `purgeAll`-on-account-delete
  is honest but wasteful).
- A sync-job-detail window for `bucketeer://sync/<id>` deep links.
