# Changelog

All notable changes to Bucketeer. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Dates are
Europe/Berlin local time. This is the developer-facing changelog; the
user-facing **What's New** copy for each App Store release lives in
`docs/APP_STORE_METADATA.md`.

The first shipped version is **v1.0.0** to the Mac App Store. Everything
before that is internal phase work on the `development` branch.

---

## [Unreleased] — `development` branch

### Documentation
- `docs/ARCHITECTURE.md` lands with eight Mermaid diagrams covering
  module composition, sync routing, sandbox lifecycle, File Provider
  sequence, entitlement state machine, account save flow, multipart
  transfer flow, and the developer.apple.com / App Store Connect
  provisioning topology.
- `docs/DEVELOPER_SETUP.md` clone-to-run guide.
- `CONTRIBUTING.md` per the design spec §13.2.

### Phase 9.8 — Local folder ↔ S3 sync (commit `a861c46`)
- `SyncEndpoint` becomes an enum: `.s3(accountID, bucket, prefix)` or
  `.localFolder(bookmark, displayPath)`.
- `SyncEngine` routes four paths (s3↔s3, s3→local, local→s3,
  local↔local) with security-scoped bookmark start/release pairing.
- `LocalFolderEnumerator` + `LocalFolderWriter` in `BucketeerCore`,
  the latter with a `safeChildURL` path-traversal guard.
- `SyncJobRecord` schema simplified to two JSON-encoded `Data`
  columns; snapshot is `Optional<SyncJob>` so corrupted records are
  filtered out by `compactMap` rather than crashing the list.
- `SyncJobSheet` gains an endpoint-kind picker + NSOpenPanel folder
  chooser.
- 8 localised strings × 10 languages.
- 5 new `SyncPlanner` tests cover local-folder paths.

### Codex review #2 + fixes (commit `79620a0`)
Method-by-method review of Phase 9.5–9.8 + the audit fixes. 10
findings, 9 addressed:
- **Blocker (path traversal):** `LocalFolderWriter.safeChildURL`
  rejects empty / absolute / `..` / `.` keys and anchors every
  install/delete/copy/upload to the chosen sync root.
- **Blocker (SwiftData migration):** deliberately deferred — pre-
  release, no production data, schema ships clean from v1.0.
- **High:** Keychain migration uses `SecItemAdd` with
  `errSecDuplicateItem` to close the load+save race.
- **High:** `LocalFolderEnumerator.enumerate` periodically calls
  `Task.checkCancellation` so cancels land within milliseconds even
  during huge folder walks.
- **Medium:** `SyncEngine.resolveEndpointContext` throws
  `sandboxAccessDenied` on stale bookmark or failed
  `startAccessingSecurityScopedResource()`.
- **Medium:** `cancelledJobIDs` set closes the
  enqueue/register-race window so a cancel between
  `enqueueDownload` and `registerActiveTransfer` is honoured.
- **Medium:** `replaceItemAt` in `LocalFolderWriter.install` and
  `executeLocalToLocal` keeps the previous good file alive during
  the swap.
- **Low:** dead `SyncEndpoint` helpers
  (`displayLocation`/`kindLabel`/`accountID`/`isLocal`/`isS3`) and
  `LocalFolderWriter.write` removed.
- **Low:** new `LocalFolderSafeChildURLTests` suite (6 cases).

### Phase 9.7 — Trial bookkeeping tests (commit `0914d37`)
- `TrialBookkeeping` extracted from host `EntitlementManager` into
  `BucketeerCore` with a `TrialDefaults` storage seam.
- 11 regression tests covering the future-date clamp + consumed
  marker (Codex deep-audit medium #8 mitigation).

### Phase 9.6 — Core test target (commit `2a5413c`)
- `BucketeerCore/Tests/BucketeerCoreTests/` with Swift Testing,
  62 tests across 6 suites covering Azure signer, S3 endpoints,
  Azure request builder, Azure list parser, sync planner.
- `SyncPlanner` extracted from host `SyncEngine`.
- `SyncJob` moved to `BucketeerCore`.

### Phase 9.5 — Core framework + live File Provider (commit `e25f4cb`)
- `BucketeerCore` local SPM package created; Models + Services
  shared between host and (manually-wired) File Provider extension.
- `Bucketeer File Provider/` rewritten to do live S3 / Azure traffic
  via `ExtensionContainer` (Sendable composition root) and
  `FileProviderItemResolver` with synthetic folder handling.
- Codex review #1 findings 1, 3, 4, 5 addressed (`any` existentials,
  synthetic folder items, stable sync anchor, visibility tightened).
- Dead-code pass: 15 unused `import BucketeerCore` removed,
  `CredentialCacheInvalidating` protocol + extensions deleted,
  `EntitlementManager.shutdown()` deleted, umbrella file deleted.

### Codex deep-audit (commit `05fa218`)
First Codex review across the entire spec-phase delta. 15 findings:
3 blockers + 5 high + 6 medium + 1 low — all addressed in the same
commit. See the commit body for details.

### Legal docs Bucketeer-specific (commit `d18ad0a`)
- EULA, Impressum, License, Open Source Notices, Privacy Policy
  rewritten to specifically describe this App. Boilerplate removed.
- Support URL changed from GitHub Issues to
  `https://support.apps.digitalfreedom.co.za/` in host, About,
  QuickStart, and App Store metadata.

### Phase 12 — Hardening (commit `db6980f`)
- `PrivacyInfo.xcprivacy` adds `NSPrivacyCollectedDataTypePurchaseHistory`
  for the StoreKit-driven Bucketeer Pro IAP.
- MenuBarExtra image gets an explicit `accessibilityLabel`.
- `docs/APP_STORE_METADATA.md` draft (description, keywords, IAP
  table, screenshot brief, launch checklist).

### Phase B — Paywall (commit `bf44797`)
- `EntitlementManager` (StoreKit 2 + 14-day UserDefaults trial)
  exposes `.trial(daysRemaining:)`, `.free`, `.pro`.
- `PaywallSheet` (single-page upsell, no funnel), Settings → Pro
  tab, sidebar Pro badge.
- Feature gating across Mount / Sync / cross-account copy / Menubar.
- `Bucketeer.storekit` local-test configuration.

### Phase 9 — File Provider scaffold (commit `ee62d39`)
- `MountController` wraps `NSFileProviderManager.add/remove`.
- App Group store migration in `AppContainer.resolveStoreURL`.
- Sidebar context menu gets Mount / Unmount.
- Stub `Bucketeer File Provider/` files; full extension setup
  documented in `PHASE_9_SETUP.md`.

### Phase 10 — Sync engine (commit `641c1e9`)
- `SyncEngine` actor with plan/execute/reconcile lifecycle.
- Copy / move / mirror modes; manual / on-launch / interval schedule.
- `SyncJobRecord` SwiftData @Model; `SyncJobListView` + `SyncJobSheet`.
- Cross-provider via TransferManager round-trip.

### Phase 11 — Localisation finalisation (commit `9ff5808`)
- 10-language coverage across all ~166 keys in
  `Localizable.xcstrings`. 1304 new translations.

### Phase 8 — Menubar background mode (commit `809c10f`)
- `MenuBarExtra` with SwiftUI popover (transfers / mount / sync /
  actions sections).
- `AppActivationController` switches `NSApp.activationPolicy`
  between `.regular` and `.accessory`.
- Window becomes `Window(id: "main")` so the menubar can re-open it
  after close.

### Phase 7 — Drag and drop (commit `4a3f99a`)
- Object rows draggable with `S3ObjectRef` Transferable payload
  under custom UTI `za.co.digitalfreedom.bucketeer.object-ref`.
- Drop targets on bucket cards and the object list accept URL
  (Finder file) and S3ObjectRef (intra-app object).
- Always-copy semantics — `⌘` modifier intentionally ignored.

### Phase 6 — Preview + Quick Look (commit `d598277`)
- `PreviewCache` (actor, SHA-256 keyed by
  `accountID|bucket|key|etag`, 2 GiB LRU, sandbox temp dir).
- Inline `QLPreviewView` in the detail pane; spacebar opens
  `QLPreviewPanel` via `QuickLookPanelController`.
- 50 MiB auto-download threshold.

### Phase A — Azure Blob Storage (commit `7b9a7e1`)
- `AzureSharedKeySigner` (CryptoKit HMAC-SHA256), `AzureRequestBuilder`,
  `AzureListXMLParser`, `AzureCredentialsCache`, `AzureBlobObjectStore`,
  `AzureBlobTransporter` (block-blob multipart, ranged-parallel
  download).
- `ProviderRouter` fans out `S3Browsing` per `account.provider.family`.
- `AddEditAccountSheet` gains Azure-aware labels and hides region /
  path-style for Azure.

### Phases 0–5 — pre-rename
- Project scaffold, sandbox + privacy manifest, Soto SPM, localised
  display name in 10 languages, deployment target lowered from 26 to
  14, app renamed from "S3 Browser" to "Bucketeer", Soto-backed
  browser, multipart upload/download queue, object actions
  (delete/rename/create-folder), connection test, Touch ID reveal,
  eye toggle, Civo path-style migration, DNS error mapping, Help and
  About menus.

---

## [v1.0.0] — not yet released

The first Mac App Store version will land here once:

- [ ] App Group + Keychain Sharing identifiers are registered at
  developer.apple.com.
- [ ] File Provider extension target is added per `PHASE_9_SETUP.md`.
- [ ] App Store Connect IAP `za.co.digitalfreedom.bucketeer.pro.lifetime`
  is created.
- [ ] App-icon source ≥1024×1024 PNG is supplied and processed into
  the iconset.
- [ ] Xcode Cloud workflows are configured per
  `~/Developer/projects/wiki/apple-native-apps.md` Model A.
- [ ] First `test` branch push succeeds end-to-end (Archive →
  TestFlight Internal).
