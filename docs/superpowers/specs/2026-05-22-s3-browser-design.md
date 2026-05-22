# S3 Browser — Design Spec

**Date:** 2026-05-22
**Author:** Marcel R. G. Berger
**Status:** Approved for v1 implementation

---

## 1. Overview

A native macOS 26 app for browsing, transferring, mounting, and synchronising S3-compatible object storage across multiple providers and credentials. Built as Build-in-Public (source-available on GitHub) and distributed exclusively through the Mac App Store under a no-redistribution license.

**Primary use cases:**

- Day-to-day browsing and management of buckets across many accounts (AWS, Civo, R2, B2, Wasabi, DO Spaces, Storj, MinIO/custom)
- Drag-and-drop transfers between Finder and S3 in both directions
- Mounting buckets in Finder under "Locations" like iCloud Drive
- Background sync/copy jobs between two S3 locations (cross-provider supported)
- Quick Look–style previews for every Mac-native file type

---

## 2. Scope

### 2.1 In Scope (v1)

- **Account management** — add/edit/delete, 8 provider presets, free Custom-Endpoint mode
- **Browser UI** — 3-pane `NavigationSplitView` (Sidebar | Object list | Detail/Preview), search, breadcrumb navigation, virtual folders via `/` delimiter
- **Object operations** — Upload, Download, Delete (with confirm), Rename (server-side `Copy` + `Delete`), Create Folder (`<prefix>/` zero-byte object)
- **Multipart Upload** — automatic for files ≥ 5 MB, 8 MB part size, parallel parts
- **Drag-and-drop** — Finder ↔ App in both directions, App ↔ App (intra- and inter-account)
- **Preview** — Inline `QLPreviewView` in detail pane + system Quick Look on Spacebar via `QLPreviewPanel`. Auto-download ≤ 50 MB, larger files require explicit click. ETag-keyed temp cache, LRU eviction
- **Mount-as-Drive** — File Provider Extension exposes mounted buckets under Finder → Locations; one `NSFileProviderDomain` per mounted bucket
- **Menubar background mode** — runtime-toggleable activation policy, `NSStatusItem` with SwiftUI popover, app stays alive when main window closes
- **Sync Engine** — Copy / Move / one-way Mirror jobs, intra- and cross-provider, manual/on-launch/interval scheduling
- **Quality** — Light/Dark, full localisation (10 wiki-standard languages via `.xcstrings`), full keyboard navigation, VoiceOver labels, Privacy Manifest

### 2.2 Out of Scope (v1)

- Bidirectional sync (conflict resolution is its own project — v1.2 if ever)
- Bucket create / delete / lifecycle / CORS / ACL editor
- Object versioning UI
- SSE configuration on upload
- STS / role-assume / SSO / IAM Identity Center
- Cron-style scheduling (v1.1)
- Resumable transfers across app restarts (v1.1)
- CLI / scripting interface
- iOS/iPadOS port

### 2.3 Decision Log

| # | Decision | Rationale |
|---|---|---|
| 1 | App Store via Xcode Cloud, App Sandbox required | User directive — Build in Public, App Store-only binary distribution |
| 2 | Soto-S3 (community Swift SDK) | Lean, S3-focused, custom endpoints, active maintenance, idiomatic async/await |
| 3 | 8 Provider presets + Custom | AWS, Civo, Cloudflare R2, Backblaze B2, Wasabi, DigitalOcean Spaces, Storj, MinIO/Custom |
| 4 | 3-pane Finder-style layout | Familiar mental model; inline preview enables passive browsing |
| 5 | File Provider Extension (not FUSE) | Only App-Store-compatible mount mechanism on macOS |
| 6 | One File Provider domain per mounted bucket | Clearer Finder UX than one-domain-per-account |
| 7 | Menubar mode runtime-toggleable | Avoids fixed `LSUIElement` lock-in; activation policy switches dynamically |
| 8 | Drag-and-drop default is Copy | Move requires explicit menu action; S3 has no atomic move, accidental ⌘-drags are expensive |
| 9 | Bidirectional sync excluded from v1 | Conflict resolution is its own design problem |
| 10 | Mirror delete-propagation off by default | Confirm dialog + dry-run preview required on first run |
| 11 | Deployment target macOS 26.0+ | Liquid Glass adoption, modern SwiftUI APIs, File Provider improvements |
| 12 | Swift 6 strict concurrency | Future-proof, surfaces races at compile time |

---

## 3. Architecture

### 3.1 Layers

```
Views (SwiftUI, @MainActor)
  ↓ bind to
ViewModels (@Observable, @MainActor)
  ↓ call
Services (protocols, Sendable, async/await)
  ↓ act on
Models (value types, Sendable)
```

Strict isolation: services don't know about views; view models don't import SwiftUI types beyond `@Observable`. Provider-specific quirks (endpoint templates, addressing style) live exclusively in `S3Provider` and `S3ClientFactory`.

### 3.2 Targets

| Target | Type | Bundle ID | Purpose |
|---|---|---|---|
| **S3 Browser** | `.app` | `za.co.digitalfreedom.s3-browser` | Host app — Browser UI, account mgmt, menubar, sync engine |
| **S3 Browser File Provider** | `.appex` | `za.co.digitalfreedom.s3-browser.fileprovider` | File Provider extension exposing mounted buckets to Finder |
| **S3 Browser Core** | `.framework` (embedded) | `za.co.digitalfreedom.s3-browser.core` | Shared Models + Services consumed by both targets |

The Core framework is the contract between host and extension; it cannot import SwiftUI.

### 3.3 Source Layout

```
S3 Browser/                          # Host target source dir
  App/                               # @main, window scenes, app-level config
  Models/                            # Sendable value types (S3Account, S3Object, ...)
  Services/                          # KeychainStore, AccountStore, S3ClientFactory,
                                     # S3Browser, TransferManager, PreviewCache, SyncEngine
  ViewModels/                        # @Observable @MainActor view models
  Views/                             # SwiftUI views
    Sidebar/
    Browser/
    Accounts/
    Transfers/
    Sync/
    Menubar/
    Settings/
  Utilities/                         # Logger, ByteFormatter, HumanDate, AsyncStreamHelpers
  Resources/
    Assets.xcassets
    Localizable.xcstrings
    *.lproj/InfoPlist.strings
    PrivacyInfo.xcprivacy
  Info.plist (or INFOPLIST_KEY_*)
  S3 Browser.entitlements

S3 BrowserTests/                     # Unit tests (Swift Testing)
S3 Browser File Provider/            # Extension target source dir
S3 Browser Core/                     # Framework target source dir (shared services + models)
```

Phase 1 begins with the host target only and the Models/Services living in `S3 Browser/`. The Core framework is extracted in Phase 9 (when the File Provider extension is added) — until then, premature extraction would create churn.

---

## 4. Data Model

### 4.1 Value Types (all `Sendable`)

```swift
enum S3Provider: String, Codable, CaseIterable, Sendable {
    case awsS3, civo, cloudflareR2, backblazeB2,
         wasabi, digitalOceanSpaces, storj, custom
}

struct S3Account: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var provider: S3Provider
    var region: String
    var endpointOverride: URL?       // Custom only
    var accountID: String?           // R2: Cloudflare account ID
    var defaultBucket: String?
    var usesPathStyle: Bool
    var lastUsedAt: Date?
}

struct S3Bucket: Hashable, Sendable {
    let name: String
    let createdAt: Date?
    let region: String?
}

struct S3Object: Hashable, Identifiable, Sendable {
    var id: String { key }
    let key: String
    let displayName: String
    let size: Int64
    let lastModified: Date
    let etag: String
    let contentType: String?
    let storageClass: String?
    let isFolder: Bool               // true for "common prefix" pseudo-folders
}

enum TransferDirection: Sendable { case upload, download }

enum TransferState: Sendable {
    case queued
    case running(bytesTransferred: Int64, totalBytes: Int64)
    case completed
    case failed(message: String)
    case cancelled
}

struct TransferTask: Identifiable, Sendable {
    let id: UUID
    let direction: TransferDirection
    let accountID: UUID
    let bucket: String
    let key: String
    let localURL: URL
    var state: TransferState
    let startedAt: Date
}
```

### 4.2 Persistence

**SwiftData** for account metadata and sync job definitions:

```swift
@Model
final class S3AccountRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var providerRaw: String
    var region: String
    var endpointOverrideRaw: String?
    var accountID: String?
    var defaultBucket: String?
    var usesPathStyle: Bool
    var lastUsedAt: Date?
    var sortIndex: Int
    init(...) { ... }
}

@Model
final class SyncJobRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var modeRaw: String
    var sourceAccountID: UUID
    var sourceBucket: String
    var sourcePrefix: String
    var destAccountID: UUID
    var destBucket: String
    var destPrefix: String
    var diffStrategyRaw: String
    var includeGlobs: [String]
    var excludeGlobs: [String]
    var deletePropagation: Bool
    var storageClassOverride: String?
    var scheduleRaw: String
    var concurrency: Int
    var lastRunAt: Date?
    var lastRunResultRaw: String?
    var enabled: Bool
    init(...) { ... }
}
```

The SwiftData store lives in the **App Group container** (`group.za.co.digitalfreedom.s3-browser`) so the File Provider extension can read account metadata.

**Keychain** for secrets only. Per-account JSON value:

```swift
struct AccountCredentials: Codable, Sendable {
    let accessKey: String
    let secretKey: String
    let sessionToken: String?
}
```

Keychain item:
- `kSecClass = kSecClassGenericPassword`
- `kSecAttrService = "za.co.digitalfreedom.s3-browser"`
- `kSecAttrAccount = "<S3Account.id.uuidString>"`
- `kSecAttrAccessGroup = "$(AppIdentifierPrefix)za.co.digitalfreedom.s3-browser.shared"`
- `kSecAttrAccessible = kSecAttrAccessibleWhenUnlocked`
- `kSecAttrSynchronizable = false`
- Value: JSON-encoded `AccountCredentials`

Account deletion cascades: SwiftData record + Keychain item + any File Provider domains using that account.

---

## 5. Provider Abstraction

| Provider | Endpoint Template | Default Region | Path-Style | Notes |
|---|---|---|---|---|
| AWS S3 | `s3.{region}.amazonaws.com` | `us-east-1` | virtual-host | |
| Civo | `objectstore.fra1.civo.com` | `fra1` | virtual-host | Wiki standard endpoint |
| Cloudflare R2 | `{accountID}.r2.cloudflarestorage.com` | `auto` | virtual-host | Account ID required |
| Backblaze B2 | `s3.{region}.backblazeb2.com` | `us-west-002` | virtual-host | |
| Wasabi | `s3.{region}.wasabisys.com` | `eu-central-1` | virtual-host | |
| DigitalOcean Spaces | `{region}.digitaloceanspaces.com` | `fra1` | virtual-host | |
| Storj | `gateway.storjshare.io` | `global` | **path** | Gateway is path-style |
| Custom (MinIO etc.) | user-specified | user-specified | **path** (default) | Toggle available |

`S3ClientFactory.makeClient(for: S3Account, credentials: AccountCredentials) throws -> S3` builds a configured `SotoS3.S3` instance. The factory holds a small actor-protected cache keyed by `account.id` so that successive operations on the same account reuse the underlying `AWSClient` (which manages a connection pool).

Disposal: cached clients are released on account delete and on app quit (`AWSClient.shutdown()` is awaited so connections drain cleanly).

---

## 6. Services

### 6.1 Service Protocols

```swift
protocol KeychainStoring: Sendable {
    func save(_ credentials: AccountCredentials, for accountID: UUID) async throws
    func load(for accountID: UUID) async throws -> AccountCredentials
    func delete(for accountID: UUID) async throws
}

protocol AccountStoring: Sendable {
    func all() async throws -> [S3Account]
    func upsert(_ account: S3Account) async throws
    func delete(id: UUID) async throws
    func touchLastUsed(id: UUID) async throws
}

protocol S3Browsing: Sendable {
    func listBuckets(account: S3Account) async throws -> [S3Bucket]
    func listObjects(account: S3Account, bucket: String,
                     prefix: String, continuationToken: String?) async throws -> S3Page
    func head(account: S3Account, bucket: String, key: String) async throws -> S3Object
    func delete(account: S3Account, bucket: String, keys: [String]) async throws
    func copy(account: S3Account, fromBucket: String, fromKey: String,
              toBucket: String, toKey: String,
              metadata: [String: String]?) async throws
    func createFolder(account: S3Account, bucket: String, prefix: String) async throws
}

protocol Transferring: Sendable {
    func enqueueUpload(account: S3Account, bucket: String, key: String,
                       localURL: URL, contentType: String?) async -> UUID
    func enqueueDownload(account: S3Account, bucket: String, key: String,
                         localURL: URL) async -> UUID
    func cancel(id: UUID) async
    var tasks: AsyncStream<[TransferTask]> { get }   // live state stream
}
```

### 6.2 TransferManager design

- One serial actor coordinates the queue; up to N (default 4, configurable) tasks run concurrently
- Multipart upload threshold: 5 MB. Part size: 8 MB. Up to 4 parts in flight per upload.
- Progress is reported by polling Soto's progress callback every 250 ms and pushing a snapshot through an `AsyncStream` consumed by view models.
- Cancellation is cooperative via `Task.cancel()` and an internal `aborted` flag; in-flight HTTP requests are cancelled by tearing down their `Task`.
- Failures are surfaced through state transitions; no automatic retry in v1 (manual retry button per task). v1.1 may add exponential backoff for transient (5xx, network) errors.

### 6.3 PreviewCache

- Backing dir: `FileManager.default.temporaryDirectory.appending("S3BrowserPreviews")`
- Key: SHA-256 of `"{accountID}|{bucket}|{key}|{etag}"` — collisions impossible in practice, allows safe caching across same-content objects
- Eviction: LRU by access time, cap **2 GB** total, cleaned on app launch and after each download
- Sandbox: temporary directory is always writable inside the app container, no entitlement required
- Quick Look: cache hands back the local file URL; the view binds it to `QLPreviewView` or hands it to `QLPreviewPanel`

### 6.4 SyncEngine

```swift
actor SyncEngine {
    func register(_ job: SyncJob) async
    func unregister(id: UUID) async
    func runNow(id: UUID) async throws
    func cancel(id: UUID) async
    var status: AsyncStream<[SyncJobStatus]> { get }
}
```

Per-job lifecycle:

1. **Plan** — enumerate source and destination in parallel, build diff list according to chosen strategy
2. **Confirm** (only on first mirror run with delete-propagation) — surface diff to UI, await user confirmation
3. **Execute** — for each diff entry, call `Transferring` or `S3Browsing.copy` (same-provider intra-region) or `Transferring` round-trip (cross-provider)
4. **Reconcile** — on completion, write `lastRunResult` back to `SyncJobRecord`

The engine ticker uses `Task.sleep(for: .seconds(intervalSeconds))` per scheduled job. Suspended while app is asleep (sandbox apps don't run when not active); on wake/launch the next-due check runs immediately. No `LaunchAgent` — would conflict with App Sandbox.

---

## 7. UI Design (macOS 26 / Liquid Glass)

### 7.1 Main Window

`NavigationSplitView` (three-column):

- **Sidebar** — list-style `.sidebar`, sections for "Accounts" (each account expandable to show buckets when selected), "Mounted Drives", "Sync Jobs", "Transfers"; floating Liquid Glass material auto-applies when compiled with Xcode 26
- **Content** — Object list as `Table` with columns: Name (icon + display name), Size, Type, Last Modified, Storage Class
- **Detail** — when one object selected: metadata + inline `QLPreviewView`; when multiple: count + cumulative size; when none: account/bucket dashboard

Toolbar (auto-Liquid-Glass in Xcode 26):
- Back / Forward (history navigation)
- Path breadcrumb (clickable segments)
- "New Folder" (`⇧⌘N`)
- "Upload…" (`⌘U`)
- View toggle (Icons / List / Columns) — v1.1 may add columns
- Search field (`.searchable`, scope: current prefix / current bucket / current account)

Inspector pane (right): toggleable, shows extended metadata + user metadata table.

Empty states use SF Symbols 7 + descriptive captions, all localised.

### 7.2 Menubar

`MenuBarExtra` (SwiftUI) holding a custom popover:

- Status icon: `externaldrive.connected.to.line.below` with badge variants (idle, syncing-animated, error-red)
- Sections:
  - Mounted drives — per drive: name, sync status, "Show in Finder", "Unmount"
  - Active transfers — count + progress, expand to list
  - Sync jobs — per job: name, last run, "Run Now", "Disable"
  - Actions — "Open Browser", "Pause All Transfers", "Settings…", "Quit"

Activation-policy switch (Settings → "Run in background"):
- On: `NSApp.setActivationPolicy(.accessory)` — dock icon hides, app stays alive in menubar
- Off: `.regular` — normal Dock app behaviour

Window-close behaviour: closing the main window calls `NSApp.hide(nil)` rather than terminating. Only `⌘Q` or menubar "Quit" terminates.

### 7.3 Sheets and Dialogs

- **AddEditAccountSheet** — provider picker, region (combo for fixed regions or free text for Custom), credentials fields (Secret-text-field for secret key), test-connection button
- **DeleteConfirmationDialog** — itemised list of what will be deleted, type-to-confirm bucket name only for batch ≥ 10 objects
- **MirrorFirstRunDialog** — dry-run table: "X to upload, Y to skip, Z to delete (if delete-prop enabled)", confirm or cancel
- **SyncJobWizard** — multi-step: Mode → Source → Destination → Options → Schedule → Review

### 7.4 Accessibility

- All controls labelled with `.accessibilityLabel`
- Full keyboard navigation; no mouse-only paths
- `⌘N` add account, `⌘⇧N` new folder, `⌘U` upload, `Space` quick look, `⌘W` close window, `⌘Q` quit, `⌫` delete (with confirmation), `↩` rename inline
- VoiceOver hints for non-obvious actions (e.g. "Drag to mount", "Pull right edge to reveal inspector")
- Respects Reduce Motion (transfer-progress animations stay simple)

---

## 8. Drag-and-Drop

### 8.1 Drag Sources

- **App object row** → produces both `NSFilePromiseProvider` (for cross-app drops to Finder; triggers on-demand download) and custom UTI `com.digitalfreedom.s3-browser.object-ref` JSON `{accountID, bucket, key}` (for intra-app drops)
- **App sidebar bucket** → not draggable in v1 (no use case yet)
- **Finder file** → standard `URL`-based drop accepted by app
- **Finder drop into mounted drive** → handled transparently by File Provider extension

### 8.2 Drop Targets and Actions

| Target | Source | Action |
|---|---|---|
| Sidebar bucket | Finder URL | Upload into bucket root |
| Sidebar bucket | App object-ref (same account) | Server-side `Copy` into bucket root |
| Sidebar bucket | App object-ref (other account) | Cross-account download → upload |
| Sidebar account header | anything | No-op (visual feedback only) |
| Folder row in list | Finder URL | Upload into that prefix |
| Folder row in list | App object-ref | Copy into that prefix |
| Empty list area | Finder URL | Upload at current prefix |
| Finder folder | App object row (drag out) | On-drop download via `NSFilePromiseProvider` |

### 8.3 Move vs Copy

Default is **always Copy**, regardless of ⌘ modifier. The `⌘`-drag modifier is intentionally ignored, because:

- S3 has no atomic Move — it's `Copy + Delete`, two requests, with a window where the object exists in both places (or in neither, if the Delete fails after the Copy succeeded but the user retried)
- Accidental ⌘-drags between buckets could trigger thousand-object deletes
- Move is exposed only via explicit menu: "Move to…", "Cut + Paste"

This is deliberately divergent from Finder behaviour and is called out in the in-app help.

---

## 9. File Provider Extension

### 9.1 Class Choice

`NSFileProviderReplicatedExtension` (introduced macOS 11; the modern replacement for the deprecated `NSFileProviderExtension`). The system manages the on-disk replica; we provide enumeration, fetch, create, modify, delete.

### 9.2 Domain Model

One `NSFileProviderDomain` per mounted bucket. Domain identifier encodes the link back: `"\(accountID.uuidString)::\(bucket)"`. The extension parses this on `init` and loads the corresponding `S3Account` (read from the shared SwiftData store) plus credentials (read from the shared Keychain access group).

Display name: `"\(account.name): \(bucket)"`.

### 9.3 Required Implementations

| Method | S3 Mapping |
|---|---|
| `enumerator(for: containerItemIdentifier, request:)` | `ListObjectsV2(prefix=, delimiter=/, continuationToken=)` — paginated as the system requests |
| `item(for: identifier, request:)` | `HeadObject` for files; synthetic item for folders |
| `fetchContents(for: identifier, version:, request:, completionHandler:)` | `GetObject` → stream into the temp file the system gives us, return URL + updated `NSFileProviderItem` |
| `createItem(basedOn:, fields:, contents:, options:, request:, completionHandler:)` | `PutObject` (or multipart for ≥ 5 MB), then return materialised item |
| `modifyItem(_:, baseVersion:, changedFields:, contents:, options:, request:, completionHandler:)` | Rename → `CopyObject` + `DeleteObject`; content change → `PutObject`; metadata change → `CopyObject` to self with new headers |
| `deleteItem(identifier:, baseVersion:, options:, request:, completionHandler:)` | `DeleteObject` (or batch `DeleteObjects` if the system batches) |

Working set / pending items / favorites / sync anchors: standard replicated-extension behaviour; we maintain a per-domain in-memory sync anchor monotonically incremented on every write so the system reliably re-enumerates after change events.

### 9.4 Lifecycle and Signalling

- Mount: host app calls `NSFileProviderManager.add(domain)` after credentials test passes
- Unmount: host app calls `NSFileProviderManager.remove(domain)`; the system tears down the extension
- Push notifications from S3 are not available (S3 doesn't push to clients) — we rely on user-initiated refresh (`enumerator.signalEnumerator()`) when the host app performs a write that the extension should reflect

### 9.5 App Store Considerations

File Provider extensions are App Store-approved (used by iCloud Drive, Dropbox, Google Drive, OneDrive, pCloud). No special review process required beyond standard App Review. Entitlements:

- Host app: `com.apple.developer.fileprovider.testing-mode` during dev (not in App Store builds); standard sandbox + network client
- Extension: `com.apple.developer.fileprovider.testing-mode` (dev only), `com.apple.security.application-groups`, network client, file-access entitlements automatically granted to FP extensions

---

## 10. Security & Sandbox

### 10.1 Entitlements (Host App)

```xml
<key>com.apple.security.app-sandbox</key>                       <true/>
<key>com.apple.security.network.client</key>                    <true/>
<key>com.apple.security.files.user-selected.read-write</key>    <true/>
<key>com.apple.security.files.downloads.read-write</key>        <true/>
<key>com.apple.security.application-groups</key>
<array><string>group.za.co.digitalfreedom.s3-browser</string></array>
<key>keychain-access-groups</key>
<array><string>$(AppIdentifierPrefix)za.co.digitalfreedom.s3-browser.shared</string></array>
```

### 10.2 Entitlements (File Provider Extension)

```xml
<key>com.apple.security.app-sandbox</key>                       <true/>
<key>com.apple.security.network.client</key>                    <true/>
<key>com.apple.security.application-groups</key>
<array><string>group.za.co.digitalfreedom.s3-browser</string></array>
<key>keychain-access-groups</key>
<array><string>$(AppIdentifierPrefix)za.co.digitalfreedom.s3-browser.shared</string></array>
```

### 10.3 Credentials Handling

- Credentials never written to disk in plaintext, never logged, never appear in error messages surfaced to the UI
- Logging uses `Logger` (os.log) with `privacy: .private` for any string derived from credentials
- Connection-test failures display generic "Authentication failed" with HTTP status — never raw response body that might echo headers
- Memory: `AccountCredentials` instances are not retained beyond the call site that builds the `AWSClient`; Soto's `CredentialProvider.static` holds them for the lifetime of the client (acceptable)

### 10.4 Network

- TLS 1.2+ enforced; ATS defaults respected (no exceptions added)
- IPv6 supported by default (URLSession + AsyncHTTPClient that Soto uses)
- No telemetry, no crash reporting, no analytics — privacy by design

---

## 11. Privacy Manifest

`PrivacyInfo.xcprivacy` declares:

- `NSPrivacyTracking` = false
- `NSPrivacyTrackingDomains` = empty
- `NSPrivacyCollectedDataTypes` = empty (we collect nothing)
- `NSPrivacyAccessedAPITypes`:
  - `NSPrivacyAccessedAPICategoryUserDefaults` — reason `CA92.1` (app's own preferences)
  - `NSPrivacyAccessedAPICategoryFileTimestamp` — reason `C617.1` (display item metadata to user)
  - `NSPrivacyAccessedAPICategoryDiskSpace` — reason `E174.1` (preview cache management)

If Soto-S3's transitive dependencies access additional reason APIs at runtime, the manifest is extended accordingly; verified during a release build sanity check.

---

## 12. Localisation

`Localizable.xcstrings` String Catalog with `sourceLanguage: "en"`. All UI strings via `LocalizedStringKey`. No `NSLocalizedString` macros except for notification-action titles.

Standard languages per wiki: `en`, `de`, `es`, `fr`, `it`, `ja`, `ko`, `nl`, `pl`, `pt-BR`.

`InfoPlist.strings` per language for `CFBundleDisplayName` and short app description.

---

## 13. License & Repository

### 13.1 License

Source-available but not OSI-Open-Source. Custom license modelled on Business Source License principles, with these terms:

- **Source available** on GitHub for reading, learning, building locally, and submitting PRs
- **Personal local builds** allowed for the contributor's own use
- **Re-distribution prohibited** — no forks published as separate apps, no binaries shared, no App Store submissions of derivatives
- **Single canonical binary** distributed exclusively by Marcel R. G. Berger on the Mac App Store

A `LICENSE` file in the repo root spells this out in unambiguous English plus German. A short blurb in `README.md` summarises and links to it.

### 13.2 Repository

- Public GitHub repo (Build in Public)
- Branches per wiki: `development` → `test` → `beta` → `main`
- Conventional Commits style commit messages
- Bug reports and PR contributions welcome (PRs governed by License)
- No CLA required in v1 — contributions are accepted under the project license; document this in `CONTRIBUTING.md` (v1.1)

---

## 14. CI/CD & Distribution

Per `apple-native-apps.md`, Model A (App Store via Xcode Cloud) workflows:

| Workflow | Branch | Actions | Target |
|---|---|---|---|
| 01. Development Build | `development` | Test + Analyze | Quality gate |
| 02. Testflight Build | `test` | Archive → TestFlight Internal | Internal testers |
| 03. Beta Release | `beta` | Archive → TestFlight External | External testers |
| 04. Release Build | `main` | Archive → App Store Submit | Public |

Setup happens after Phase 0 lands and a clean Debug build runs locally.

---

## 15. Testing Strategy

- **Unit tests** (Swift Testing): Provider endpoint construction (table-driven for all 8 presets), Sync diff strategies, Keychain encode/decode round-trip, Sandbox-safe path handling
- **Integration tests** (gated behind env var `S3_INTEGRATION_TEST=1`): MinIO via Docker, full upload/download/list/delete cycle, multipart, copy server-side, cross-provider sync
- **UI smoke tests** (XCUITest): add account → list buckets → open object → preview shows; menubar mode toggle; mount domain appears in Finder
- **Manual QA matrix** per release: each of the 8 provider presets exercised once against a real bucket

Test data sets live in `S3 BrowserTests/Fixtures/`. Integration tests provision a temporary bucket and delete it in a `defer` block.

---

## 16. Implementation Phases

The host app is built first to working state, then the extension and sync engine are added. Each phase is an isolated branch-and-merge unit on `development` with a green build and tests before proceeding.

| # | Phase | Deliverable |
|---|---|---|
| 0 | Project scaffold | License, README, branches, entitlements, Privacy Manifest, .xcstrings shell, Soto SPM, directory restructure, deployment target macOS 26, Swift 6 mode |
| 1 | Core models & service protocols | Sendable models, service protocols, in-memory stubs, compiles clean |
| 2 | Account CRUD | KeychainStore + AccountStore implementations, AddEditAccountSheet, sidebar list |
| 3 | Browsing | S3Browser implementation, ObjectListView with pagination, breadcrumbs, search |
| 4 | Transfers | TransferManager with multipart, progress UI, cancel |
| 5 | Object ops | Delete with confirm, rename, create folder |
| 6 | Preview | PreviewCache, inline QLPreviewView, Spacebar QLPreviewPanel |
| 7 | Drag-and-drop | All matrix entries from §8 |
| 8 | Menubar mode | MenuBarExtra, activation policy toggle, window-close-hides behaviour |
| 9 | File Provider extension | Extract Core framework, add extension target, implement replicated extension, mount/unmount UI |
| 10 | Sync engine | SyncEngine actor, SyncJobWizard, scheduling, mirror dry-run dialog |
| 11 | Localisation finalisation | Translations for all 10 languages, audit untranslated keys |
| 12 | Hardening | Accessibility audit, performance pass, privacy manifest verification, App Store metadata draft |

After Phase 12, version 1.0.0 ships to TestFlight internal via the `test` branch.

---

## 17. Open Questions Resolved

| Q | Resolution |
|---|---|
| App Store vs Direct? | App Store via Xcode Cloud |
| S3 SDK? | Soto-S3 (community Swift SDK) |
| Provider presets? | All 8: AWS, Civo, R2, B2, Wasabi, DO Spaces, Storj, MinIO/Custom |
| Preview UX? | Inline + Quick Look on Spacebar, ≤50 MB auto-download |
| Mount mechanism? | NSFileProviderReplicatedExtension, one domain per bucket |
| Menubar mode? | Runtime-toggleable activation policy with `MenuBarExtra` |
| Bidirectional sync? | Excluded from v1 |
| Mirror delete-propagation? | Off by default, per-job opt-in, dry-run confirm on first run |
| Drag move semantics? | Always Copy; Move via explicit menu only |
| Deployment target? | macOS 26.0+ |

---

*End of spec.*
