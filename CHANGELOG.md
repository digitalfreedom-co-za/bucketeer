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

### Phase 13.7 — Metadata + tags editor
- `ObjectMetadata` Sendable struct holds HTTP headers
  (Content-Type, Cache-Control, Content-Disposition, Content-
  Encoding), `x-amz-meta-*` user metadata, object tags, and a
  read-only storage class.
- `S3Browsing` gains `loadMetadata` + `saveMetadata`. `S3Service`
  loads via parallel HeadObject + GetObjectTagging; saves via
  `copyObject(metadataDirective: .replace)` followed by
  `putObjectTagging`. `AzureBlobObjectStore` returns
  `.featureNotSupported` for now — Azure metadata + tag semantics
  are different enough to deserve their own phase.
- `ObjectMetadataViewModel` (`@Observable @MainActor`) snapshots
  the loaded value as `original` so `hasChanges` is a simple
  equality check. `ObjectMetadataSheet` renders four `Form`
  sections (HTTP / user metadata / tags / storage class) with
  add/remove rows, key-format validation (lower-case ASCII +
  dashes), and a hard 10-tag cap.
- Browser context menu gains **Metadata & Tags…** for single-
  object selections; sheet sits next to the existing versions /
  share / rename sheets in ObjectListView.
- 17 localised strings × 10 languages.

### Phase 13.6 — Object versions browser
- `ObjectVersion` Sendable struct in BucketeerCore covering both
  recorded versions and S3 delete markers (`isDeleteMarker`).
- `BucketeerError.featureNotSupported(featureKey:)` for providers
  that don't implement a requested operation.
- `S3Browsing` gains `listVersions`, `restoreVersion`,
  `deleteVersion`. `S3Service` implements them via Soto
  (`listObjectVersions`, version-aware `copyObject`,
  `deleteObject(versionId:)`); `AzureBlobObjectStore` returns
  `.featureNotSupported` (snapshot semantics are sufficiently
  different that they get their own phase later); `ProviderRouter`
  fans out.
- `ObjectVersionsViewModel` (`@Observable @MainActor`) wraps the
  three operations with per-row in-flight tracking.
- `ObjectVersionsSheet` shows a Table with Modified / Size /
  Version-ID / Actions columns, "Latest" tag, "Delete marker"
  badge, Restore + Delete-version confirmations, and a clear
  "feature not supported" empty state for Azure.
- Browser context menu gains **Show Versions…** for single-object
  selections.
- 19 localised strings × 10 languages.

### Phase 13.5 — Bucket dashboard
- BucketeerCore: `BucketStats` Sendable struct (object count, folder
  count, total bytes, top-N largest, last modified, truncated flag);
  `BucketStatsCollector` walks every `listObjects` page with a
  `pageCap` (default 100 pages = ~100k objects) and a single-pass
  top-N largest tracker; `ProviderPricing` table with USD per
  GB-month per provider (AWS S3 0.023, Azure Hot 0.0184, R2 0.015,
  B2 0.006, Wasabi 0.00585, DO Spaces 0.020, Civo 0.005,
  Storj 0.004, Custom → nil).
- 6 new unit tests covering `insertLargest` (under-capacity, evict
  smallest, ignore-too-small) and `ProviderPricing` (every concrete
  provider has a rate, AWS GB rate matches, zero bytes → zero cost).
  Total Core test count: 103.
- Host: `BucketDashboardViewModel` (`@Observable @MainActor`) runs
  the collector in a cancellable task; `BucketDashboardSheet`
  surfaces a 2×2 stats grid, monthly-cost estimate GroupBox with a
  scope disclaimer, top-10 largest objects list, truncation hint
  when the cap was hit, and an error banner.
- Browser toolbar gets a **Dashboard** button alongside the existing
  new-folder + upload buttons; sheet is presented and the view
  model is cancelled on dismiss.
- 11 localised strings × 10 languages.

### Phase 13.4 — Trash / soft-delete
- New host-only `BucketeerTrash.store` SwiftData container + a
  parallel `Trash/` cache directory in sandbox Application Support.
  Kept separate from the App Group + activity stores.
- BucketeerCore: `TrashedItem` (Sendable snapshot) + `TrashCacheStatus`
  enum + `TrashRecord` (`@Model`) + `TrashStoring` protocol. Impl is a
  manual `actor TrashStore: TrashStoring, ModelActor` (custom init
  takes a `cacheRootURL`, hence no `@ModelActor` macro). Every code
  path that removes a row also removes the cached file.
- `TrashSettings` (`@Observable @MainActor`) holds three knobs in
  UserDefaults: master toggle, per-object cache cap (MB), retention
  (days, default 30).
- `TrashCoordinator` (`@MainActor`) glues the trash to the existing
  browser + transfer manager:
  - `recordDeletion(...)` is called by `BrowserViewModel.delete(keys:)`
    *before* the provider delete; it HEADs every key, records a
    metadata row, and downloads cacheable payloads in parallel via
    a `TaskGroup` + `TransferManager.enqueueDownload`. Capture
    happens before the delete so the bytes are guaranteed readable.
  - `restore(item:)` re-uploads the cached payload via the transfer
    manager and forgets the entry on success.
  - `forget(item:)` / `empty()` pass through to the store.
- `TrashViewModel` + `TrashView` window: Table with Object / Account /
  Size / Cache status / Deleted-at / Actions columns; Restore /
  Forget per row; Empty Trash with confirmation; refresh button.
- Menu entry **Window → Trash** (⌘⇧⌫); Settings → Transfers gains a
  **Trash** section.
- `purgeExpired()` runs at launch to drop rows past `retentionDays`.
- 39 localised strings × 10 languages.

### Phase 13.3 — Watch folder → bucket
- New streamlined `WatchFolderSheet` builds a `SyncJob` with a
  `.localFolder` source, an S3 / Azure destination, `.onLocalChange`
  schedule, and either `.copy` (keep local file) or `.move` (delete
  local after successful upload). Reuses the entire sync engine
  end-to-end — Phase 9.10 already wired the FSEvents watcher pump.
- `SyncJobListView` toolbar "+" becomes a Menu with **New Sync
  Job…** and **New Watch Folder…**. Empty state grew a second
  affordance.
- Watch-folder rows show an eye icon in the name column with a
  tooltip distinguishing them from scheduled sync jobs.
- `SyncEngine` pump task records `ActivityKind.watchFolderTriggered`
  before each `runNow` so the user can see in the activity log why
  a job started even when the run produces zero transfers.
- Legal docs (EULA / Privacy / Impressum / Source-Available License /
  Open Source Notices) redesigned with a consistent template: one-
  sentence italic lede, labeled metadata block, numbered title-case
  sections, bullets in place of tables (which the bundled MarkdownView
  doesn't structure-render), consistent contact + copyright footer.
- 20 localised strings × 10 languages.

### Phase 13.2 — Bandwidth limit
- `BandwidthLimiter` (Core): token-bucket actor with a `consume(bytes:)`
  drain pattern that converges for requests bigger than the bucket
  capacity. `0 bytes/s = unlimited`.
- 5 `BandwidthLimiterTests` covering the unlimited path, sub-burst,
  oversized requests with deficit sleep, mid-flight toggle to
  unlimited, and `currentLimit` reflection.
- `AzureBlobTransporter` charges the limiter per ranged GET, per block
  PUT, and per single-shot PUT — accurate end-to-end.
- `TransferManager` charges the limiter for the small-object PUT/GET
  paths and (best-effort) for Soto multipart via per-progress-delta
  charging through a per-transfer `multipartBytesCharged` cursor.
- `BandwidthSettings` (`@Observable @MainActor`) projects user-picked
  preset / custom MB/s into the limiter and persists to UserDefaults.
  Settings → **Transfers** tab exposes Unlimited, 256 KB/s, 1 MB/s,
  5 MB/s, 25 MB/s, Custom (1–512 MB/s).
- Localised across 10 languages with an explicit note that the cap is
  exact for Azure and approximate for Soto-backed S3 (Soto reports
  byte progress only in fractions).

### Phase 13.1 — Activity log
- Host-only SwiftData container `BucketeerActivity.store` in sandbox
  Application Support; kept out of the App Group so the File Provider
  extension does not load the audit schema.
- `ActivityRecord` (`@Model`) + `ActivityEntry` (Sendable snapshot) +
  `ActivityKind`/`ActivityStatus` enums in `BucketeerCore`.
- `ActivityLogging` protocol (record / recent / search / deleteAll /
  purgeExpired / count). Impl is a `@ModelActor` (`ActivityLogStore`)
  that silently swallows write errors — recording is observation and
  must never break the operation it observes.
- Recording hooks added to `TransferManager` (upload/download terminal
  transitions), `SyncEngine` (start / finish / fail / cancel per job),
  `AccountListViewModel` (add / update / delete), `BrowserViewModel`
  (delete / createFolder / rename) and `PresignedURLSheet` (signed-URL
  generation).
- `ActivityLogView` window — table with time, kind, status, account,
  target, details columns; free-text search, account filter,
  multi-select kind filter, CSV export via `.fileExporter`, Clear All
  with confirmation, 180-day auto-purge at launch.
- Window menu entry **Window → Activity Log** (⌘⌥0) plus a
  quick-access row in the menu-bar extra.
- 44 localised strings × 10 languages.

### Phase 9.10 — Sync-on-change FSEvents (commit `0d9746c`)
- `LocalFolderWatcher` (Core): FSEventStream wrapper with debounced
  `AsyncStream<Date>`, idempotent start/stop, deinit-safe cleanup.
- `SyncSchedule.onLocalChange` round-trips through SwiftData via
  `"onLocalChange"` rawValue.
- `SyncEngine.reconcileLocalChangeWatchers` runs on every `reload()`:
  start watchers for eligible jobs, replace stale ones when the
  bookmark changes, tear down deleted/disabled jobs. Events pump into
  the existing idempotent `runNow(id:)`.
- `SyncJobSheet` exposes the schedule option only when source kind is
  `.localFolder`; footnote explains debouncing. Localised across 10
  languages.

### Phase 9.9 — Presigned download URLs (commit `324977c`)
- `AzureSASBuilder` for the Azure Blob Service SAS (HMAC-SHA256,
  v2020-12-06+ 16-line StringToSign, HTTPS only).
- `S3Browsing.presignedDownloadURL` extended through the protocol and
  routed by `ProviderRouter` to Soto's `signURL` for the S3 family or
  the SAS builder for Azure.
- `PresignedURLSheet` (TTL picker + custom minutes, copy-to-clipboard,
  `NSSharingServicePicker` share sheet).
- 8 `AzureSASBuilderTests` covering query params, percent-encoding,
  signature determinism, TTL sensitivity.

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
