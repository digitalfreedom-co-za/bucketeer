# Bucketeer — Architecture

This document is the canonical architectural reference: how the host
app, the BucketeerCore Swift package, and the File Provider extension
fit together; how the four sync-routing paths land; how the entitlement
state machine moves; where the provisioning identifiers live; and how
the Phase 13.x feature block layers on top. The per-release history is
in [`CHANGELOG.md`](../CHANGELOG.md).

---

## 1. Module composition

Bucketeer ships as one Mac App Store binary made of three buildable
units. `BucketeerCore` is the seam everything cross-cuts on; the host
and the (yet-to-be-target-wired) File Provider extension both link it.

```mermaid
graph LR
    subgraph BucketeerCore["BucketeerCore<br/>(local Swift package)"]
        Models["Models<br/>S3Account · S3Provider · S3Object · S3Page<br/>AccountCredentials · BucketeerError · TransferTask<br/>SyncJob · S3AccountRecord · ActivityEntry<br/>ObjectVersion · ObjectMetadata · BucketStats<br/>BucketInsights · TrashedItem · MultipartUploadCheckpoint<br/>AutoTagRule · BucketEncryptionKey"]
        S3Layer["S3 layer<br/>S3ClientFactory (actor) · S3Service<br/>S3ResumableUploader (Phase 13.10)<br/>via SotoS3"]
        AzureLayer["Azure layer<br/>AzureSharedKeySigner · AzureRequestBuilder<br/>AzureListXMLParser · AzureCredentialsCache<br/>AzureBlobObjectStore · AzureBlobTransporter<br/>AzureSASBuilder"]
        Storage["Persistence (all @ModelActor)<br/>KeychainStore · AccountStore · ActivityLogStore<br/>TrashStore · CheckpointStore · AutoTagRuleStore<br/>EncryptionKeyStore · SyncJobStore"]
        Sync["Sync helpers<br/>SyncPlanner (pure) · LocalFolderEnumerator<br/>LocalFolderWriter (incl. safeChildURL)<br/>LocalFolderWatcher (FSEvents)"]
        Routing["Routing<br/>ProviderRouter (S3Browsing facade)"]
        Trial["Entitlements<br/>TrialBookkeeping (pure, DI store)"]
        Crypto["Encryption (13.15)<br/>BucketeerEnvelope (AES-GCM + AAD)<br/>EncryptionError"]
        AutoTag["Auto-tagging (13.8)<br/>AutoTagRuleEvaluator (pure, glob+MIME)"]
        Stats["Stats (13.5)<br/>BucketStatsCollector · ProviderPricing"]
        Bandwidth["Throttling (13.2)<br/>BandwidthLimiter (token bucket)"]
        DeepLink["Deep link (13.11)<br/>BucketeerDeepLink"]
        Env["AppEnvironment + ServiceProtocols"]
    end

    subgraph HostApp["Bucketeer.app<br/>(host target)"]
        Container["AppContainer<br/>@MainActor @Observable composition root<br/>+ static .shared for App Intents"]
        ViewModels["ViewModels<br/>AccountList · Browser · TransferQueue · SyncJobList<br/>ActivityLog · Trash · BucketDashboard<br/>ObjectVersions · ObjectMetadata · AutoTagRules<br/>EncryptionKeys"]
        Views["SwiftUI Views<br/>Sidebar · Browser · Sync · Paywall · Menubar · About<br/>Activity · Trash · Settings (General · Transfers · Rules<br/>· Encryption · Security · Pro)"]
        HostOnly["Host-only services<br/>EntitlementManager (StoreKit) · MountController<br/>DragDropCoordinator · TransferManager (actor)<br/>SyncEngine (actor) · SyncStatusBroker (multicast)<br/>PreviewCache · AppActivationController<br/>TrashCoordinator · BandwidthSettings · TrashSettings<br/>AutoTagCoordinator · DeepLinkRouter · CrossAccountCopyCoordinator<br/>SpotlightIndexer · SpotlightSettings · BucketEncryptionGate<br/>HardwareKeyAvailability · HardwareKeySettings"]
        AppIntents["App Intents (13.12)<br/>AccountEntity · AppIntentsBridge<br/>ListBucketsIntent · GeneratePresignedURLIntent<br/>UploadFileIntent · RunSyncJobIntent<br/>BucketeerShortcuts (AppShortcutsProvider)"]
    end

    subgraph FPExt["Bucketeer File Provider.appex<br/>(manual Xcode target — PHASE_9_SETUP.md)"]
        FPCallbacks["NSFileProviderReplicatedExtension callbacks<br/>FileProviderExtension · FileProviderEnumerator<br/>FileProviderItemResolver · S3DirectFetch"]
        FPContainer["ExtensionContainer (Sendable)"]
    end

    HostApp -- "import BucketeerCore" --> BucketeerCore
    FPExt -- "import BucketeerCore" --> BucketeerCore

    Container --> ViewModels
    Container --> HostOnly
    Container --> AppIntents
    HostOnly -- "uses" --> S3Layer
    HostOnly -- "uses" --> AzureLayer
    HostOnly -- "uses" --> Storage
    HostOnly -- "uses" --> Sync
    HostOnly -- "uses" --> Routing
    HostOnly -- "uses" --> Crypto
    HostOnly -- "uses" --> AutoTag
    HostOnly -- "uses" --> Stats
    HostOnly -- "uses" --> Bandwidth
    HostOnly -- "uses" --> DeepLink
    HostOnly -- "TrialBookkeeping" --> Trial

    FPCallbacks --> FPContainer
    FPContainer --> Storage
    FPContainer --> S3Layer
    FPContainer --> AzureLayer
    FPContainer --> Routing
```

**Why this layout:** the design spec §3 wanted shared `Models` + `Services`
between host and extension. Phase 9.5 extracted them into
`BucketeerCore` so neither side duplicates code and a test target can
hammer the storage / network / signing / encryption surface without a
UI. The 13.x block keeps adding to Core whenever the logic is
deterministic / unit-testable (planner, evaluator, envelope,
fingerprint, deep-link parser) and to the host whenever it depends on
live state (transfer manager, coordinators, view models).

### 1.1 SwiftData container topology

The host now owns **six** SwiftData containers. The shared App Group
container is read by the File Provider extension; everything else stays
host-private so the extension never has to load schemas it has no use
for.

```mermaid
graph TB
    Group["App Group<br/>group.za.co.digitalfreedom.bucketeer"]
    GroupStore["Bucketeer.store<br/>S3AccountRecord · SyncJobRecord"]
    Group --> GroupStore

    HostSandbox["Host sandbox<br/>~/Library/Application Support"]
    Activity["BucketeerActivity.store<br/>ActivityRecord (Phase 13.1)"]
    Trash["BucketeerTrash.store<br/>TrashRecord (Phase 13.4)<br/>+ Trash/ cache dir"]
    AutoTag["BucketeerAutoTags.store<br/>AutoTagRuleRecord (Phase 13.8)"]
    Checkpoint["BucketeerCheckpoints.store<br/>MultipartUploadRecord (Phase 13.10)"]
    Encryption["BucketeerEncryptionKeys.store<br/>BucketEncryptionKeyRecord (Phase 13.15)<br/>+ Keychain (.cse service) for raw bytes"]
    Staging["CrossAccountStaging/<br/>bucketeer-roundtrip-* (Phase 13.14)<br/>scavenged at launch"]

    HostSandbox --> Activity
    HostSandbox --> Trash
    HostSandbox --> AutoTag
    HostSandbox --> Checkpoint
    HostSandbox --> Encryption
    HostSandbox --> Staging

    FPExt["File Provider .appex"]
    FPExt -. "reads only" .-> GroupStore
```

The 5 host-only stores live in the sandbox so each can grow / shrink /
purge independently. None of them are needed by the extension's
mount-callbacks path. Auto-purge runs on launch for the activity log
(180 days), the trash (user-configured retention, default 30 days),
and the cross-account staging directory (any leftover file).

---

## 2. Sync routing — Phase 9.8 four-way matrix

Each side of a `SyncJob` is one of two cases:

```swift
public enum SyncEndpoint: Codable, Hashable, Sendable {
    case s3(accountID: UUID, bucket: String, prefix: String)
    case localFolder(bookmark: Data, displayPath: String)
}
```

`SyncEngine.execute(upsert:job:context:)` switches over
`(job.source, job.destination)` and routes to one of four execution
paths. Local-folder sides resolve their security-scoped bookmark
once per run (start before the loop, guaranteed `stop` via `defer`).

```mermaid
flowchart LR
    Plan["SyncPlanner.makePlan"]
    Plan --> Route{{"switch (source, destination)"}}

    Route -->|"s3 → s3"| Path1["executeS3ToS3<br/>same account → ProviderRouter.copy<br/>different account → TransferManager<br/>(download to staging → upload)"]
    Route -->|"s3 → localFolder"| Path2["executeS3ToLocal<br/>TransferManager.download → staging file<br/>LocalFolderWriter.install (safeChildURL +<br/>replaceItemAt = atomic)"]
    Route -->|"localFolder → s3"| Path3["executeLocalToS3<br/>safeChildURL(sourceRoot, key)<br/>TransferManager.upload from folder file"]
    Route -->|"localFolder → localFolder"| Path4["executeLocalToLocal<br/>safeChildURL on both sides<br/>copyItem → sibling temp →<br/>replaceItemAt = atomic"]

    Path1 --> Track["registerActiveTransfer(jobID, transferID)<br/>cancelledJobIDs check closes race"]
    Path2 --> Track
    Path3 --> Track

    Track --> Await["TransferManager.awaitCompletion(id)<br/>per-ID continuation, no stream poll"]
    Path4 --> Done["Result&lt;Void, Error&gt;"]
    Await --> Done

    Done --> Tally["Tally per-entry success/failure<br/>plan.upserts → successfulEntries<br/>(move-mode source delete only on success)"]
```

**Sandbox lifecycle for local-folder endpoints:**

```mermaid
sequenceDiagram
    participant User
    participant Sheet as SyncJobSheet
    participant Engine as SyncEngine
    participant Bookmark as LocalFolderEnumerator
    participant FS as Filesystem

    User->>Sheet: "Choose folder…"
    Sheet->>FS: NSOpenPanel (canChooseDirectories)
    FS-->>Sheet: URL
    Sheet->>Sheet: url.bookmarkData(.withSecurityScope)
    Sheet->>Engine: SyncJob with .localFolder(bookmark, displayPath)

    Note over Engine: --- run starts ---
    Engine->>Bookmark: resolveBookmark(data)
    Bookmark-->>Engine: (url, isStale)
    Engine->>Engine: if isStale → throw sandboxAccessDenied
    Engine->>FS: url.startAccessingSecurityScopedResource()
    FS-->>Engine: didStart
    Engine->>Engine: if !didStart → throw sandboxAccessDenied
    Engine->>FS: enumerate / copy / write
    Note over Engine: defer { releaseSecurityScope(...) }
    Engine->>FS: url.stopAccessingSecurityScopedResource()
```

**Status fan-out — `SyncStatusBroker`:** `SyncEngine.statuses`
is an `AsyncStream<[SyncJobStatus]>` and its iterator only
delivers each emission to *one* awaiter. As soon as the sync
list view model and the `bucketeer://sync/<id>` detail window
both want to read, they need a multicaster. `SyncStatusBroker`
(`@MainActor @Observable`) is the single consumer: it owns one
pump task, normalises each snapshot to `[UUID: SyncJobStatus]`,
and republishes via its `@Observable` property. View models and
windows read `broker.statuses[jobID]` directly — SwiftUI's
observation tracking re-renders them when the broker's snapshot
changes. The pump-task handle is held `nonisolated(unsafe)` so
`deinit` can cancel it without a main-actor hop.

---

## 3. File Provider replicated-extension contract

The extension lives at `Bucketeer File Provider/`. One
`NSFileProviderDomain` per mounted bucket, identifier
`"<accountID>::<bucket>"`. Every callback is bridged through
`Progress.cancellationHandler` so Finder cancellations actually stop
the network traffic.

```mermaid
sequenceDiagram
    participant Finder
    participant System as macOS FP system
    participant Ext as FileProviderExtension
    participant Resolver as FileProviderItemResolver
    participant Container as ExtensionContainer
    participant Core as BucketeerCore<br/>(Router / Direct fetcher)

    Finder->>System: open mounted bucket
    System->>Ext: enumerator(for: rootContainer)
    Ext->>Resolver: paginated listObjects via ProviderRouter
    Resolver-->>System: didEnumerate(items)
    Resolver-->>System: finishEnumerating(upTo: nextPage)

    Finder->>System: double-click file
    System->>Ext: fetchContents(itemIdentifier, progress)
    Ext->>Ext: Task with progress.cancellationHandler = task.cancel()
    Ext->>Resolver: fetchContents(... in: domain, container: ...)
    Resolver->>Container: head + downloadObject
    alt S3 family
        Container->>Core: S3DirectFetch.download (Soto, multipart on size)
    else Azure
        Container->>Core: AzureBlobTransporter.download (ranged parallel)
    end
    Core-->>Resolver: staged URL
    Resolver-->>System: (url, item, nil)
    System-->>Finder: file content

    Note over Finder, Ext: Delete folder = recursive list + chunked DeleteObjects<br/>(safeChildURL guards on local destinations)
```

**Capability rules per item type** (Codex medium #10 fix):

| Item | Capabilities |
|---|---|
| `.rootContainer` | `[.allowsContentEnumerating, .allowsAddingSubItems]` — bucket itself can't be renamed/deleted |
| folder (`key.hasSuffix("/")`) | `[.allowsContentEnumerating, .allowsAddingSubItems, .allowsDeleting, .allowsRenaming]` |
| file | `[.allowsReading, .allowsWriting, .allowsDeleting, .allowsRenaming]` |

---

## 4. Entitlement state machine (Phase B)

`TrialBookkeeping` (Core, pure) drives the state; `EntitlementManager`
(host, `@MainActor @Observable`) wraps it with the StoreKit lifecycle.

```mermaid
stateDiagram-v2
    [*] --> Trial: first launch<br/>(trialStartKey written)
    Trial --> Trial: daysRemaining() polled
    Trial --> Free: 14 days elapsed<br/>(trialConsumedKey set, sticky)
    Trial --> Pro: Transaction.currentEntitlements<br/>verified + unrevoked
    Free --> Pro: purchasePro() → verified
    Free --> Free: StoreKit .unverified<br/>throws EntitlementError.unknown
    Pro --> Free: Apple revokes entitlement<br/>(refund / charge-back)
    Pro --> Pro: refresh() polled

    note right of Trial
      Future-date clamp:
      rawStart > now → use now,
      rewrite persisted start.
      Sticky consumed marker
      survives plist deletion.
    end note

    note right of Free
      isUnlocked(_:) returns false for
      mountDrive / syncEngine / s3ToS3Copy / menubarBackground
      Gated UI surfaces the PaywallSheet.
    end note
```

---

## 5. Account add / edit transactional flow

Saves Keychain first, then SwiftData. Codex high #7 ensures rollback
distinguishes edit (restore previous credentials) from create
(delete the new orphan).

```mermaid
sequenceDiagram
    participant UI as AddEditAccountSheet
    participant VM as AccountListViewModel
    participant Keychain as KeychainStore
    participant SwiftData as AccountStore

    UI->>VM: save(account, credentials)
    VM->>Keychain: load(for: account.id)
    Keychain-->>VM: previous credentials (nil if create)
    VM->>VM: isEdit = previous != nil
    VM->>VM: effective = resolveCredentials(form, existing)
    VM->>Keychain: save(effective)
    alt Keychain succeeds
        VM->>SwiftData: upsert(account)
        alt SwiftData succeeds
            VM->>VM: invalidateAllCaches(account.id)
            VM-->>UI: nil (success)
        else SwiftData fails
            alt isEdit
                VM->>Keychain: save(previous) — restore
            else create
                VM->>Keychain: delete — drop orphan
            end
            VM-->>UI: BucketeerError
        end
    else Keychain fails
        VM-->>UI: BucketeerError
    end
```

---

## 6. Multipart transfer flow (Soto / Azure / resumable / encrypted)

`TransferManager` is the actor-backed queue with bounded
concurrency, the snapshot stream the UI consumes, and the per-ID
`awaitCompletion(id:)` API the sync engine + drag-drop coordinator
suspend on. Cancellation routes through `setState` so waiters get
resumed (Codex blocker #2 fix). The 13.x block layered three
optional transforms on top: bandwidth throttling, transparent
client-side encryption, and resumable multipart uploads.

```mermaid
flowchart TD
    Enqueue["enqueueUpload / enqueueDownload<br/>UUID generated, item added to order[]<br/>(13.4) trash bypassDecryption flag carried"]
    Enqueue --> Pump["pump()<br/>start up to maxConcurrent workers"]
    Pump --> Worker["startWorker(item)<br/>setState .running"]
    Worker --> EncryptGate{{"(13.15) BucketEncryptionGate<br/>has key for (account, bucket)?"}}
    EncryptGate -->|"yes — upload only"| Seal["BucketeerEnvelope.seal<br/>AES-GCM with header as AAD<br/>writes temp file, rebuilds QueuedItem"]
    EncryptGate -->|"no"| Route
    Seal --> Route
    Route{{"item.account.provider.family"}}
    Route -->|"s3"| Size{{"item.fileSize"}}
    Route -->|"azureBlob"| Azure["AzureBlobTransporter<br/>(8 MiB blocks, ≤4 parallel,<br/>ranged 206-only download)<br/>(13.2) limiter charged per block"]
    Size -->|"≥ 50 MB"| Resumable["(13.10) S3ResumableUploader<br/>createMultipartUpload → listParts →<br/>uploadPart loop with per-part<br/>SwiftData checkpoint + mtime fingerprint<br/>→ completeMultipartUpload"]
    Size -->|"5–50 MB"| Soto["Soto multipartUpload helper<br/>(13.2) limiter charged per progress delta"]
    Size -->|"< 5 MB"| SinglePut["putObject single shot<br/>(13.2) limiter charged once"]
    Resumable --> Progress
    Soto --> Progress
    SinglePut --> Progress
    Azure --> Progress
    Progress["setState .running(bytesTransferred, totalBytes)<br/>publishes snapshot to tasks AsyncStream"]
    Progress --> DownloadGate{{"download AND envelope on disk<br/>AND key available AND<br/>NOT bypassDecryption?"}}
    DownloadGate -->|"yes"| Open["BucketeerEnvelope.open<br/>AES-GCM verify header AAD<br/>rewrite file in place"]
    DownloadGate -->|"no"| Terminal
    Open --> Terminal
    Terminal["setState .completed / .failed / .cancelled<br/>terminalCache[id] = state<br/>resume every waiters[id]<br/>(13.1) recordTerminal → activity log<br/>cleanup temp envelope file"]
    Cancel["cancel(id)"] --> SetCancel["workers[id]?.cancel()<br/>setState .cancelled"]
    SetCancel --> Terminal

    Await["awaitCompletion(id)<br/>SyncEngine / DragDropCoordinator<br/>TrashCoordinator / CrossAccountCopy"]
    Await --> CheckCache{{"terminalCache[id] set?"}}
    CheckCache -->|"yes"| ReturnCached["return cached state"]
    CheckCache -->|"no"| Suspend["withCheckedContinuation<br/>waiters[id] += continuation"]
    Terminal --> Suspend
```

### 6.1 Trash, cross-account, auto-tag co-tenants

Three host services hang off the same TransferManager + activity-log
bus. None of them ever bypass the encryption gate or the bandwidth
limiter unless they explicitly opt in (e.g. trash capture sets
`bypassDecryption: true` so the local cache holds the raw envelope
instead of plaintext — Codex audit fix high #2).

```mermaid
flowchart LR
    Browser["BrowserViewModel.delete(keys)"]
    Browser --> TC["TrashCoordinator.recordDeletion<br/>HEAD + parallel cached downloads<br/>(bypassDecryption: true)"]
    TC --> ProviderDelete["S3Browsing.delete on provider"]
    Browser -. provider delete .-> ProviderDelete

    ContextMenu["ObjectListView context menu<br/>Copy to other account…"]
    ContextMenu --> CrossSheet["CrossAccountCopySheet"]
    CrossSheet --> CACoord["CrossAccountCopyCoordinator<br/>(13.14)"]
    CACoord --> EncryptionCheck{{"CSE on either side?<br/>(audit fix high #1)"}}
    EncryptionCheck -->|"yes"| RoundTrip["enqueueDownload + enqueueUpload<br/>via TransferManager (re-encrypts)"]
    EncryptionCheck -->|"no"| ServerCheck{{"same endpoint?"}}
    ServerCheck -->|"yes"| ServerCopy["S3Browsing.copy<br/>server-side CopyObject"]
    ServerCheck -->|"no"| RoundTrip

    Upload["TransferManager upload completion<br/>(any path)"]
    Upload --> AutoTag["AutoTagCoordinator (13.8)<br/>observes .tasks stream<br/>evaluates rules → saveMetadata"]
    Upload --> Activity["ActivityLogStore (13.1)<br/>recordTerminal"]
```

---

## 7. Provisioning and signing topology

What lives where (App Sandbox + entitlements + provisioning):

```mermaid
flowchart LR
    subgraph DevApple["developer.apple.com"]
        AppID["App ID<br/>za.co.digitalfreedom.Bucketeer"]
        FPAppID["App ID<br/>za.co.digitalfreedom.Bucketeer.FileProvider"]
        AppGroup["App Group<br/>group.za.co.digitalfreedom.bucketeer"]
        KCGroup["Keychain Sharing<br/>za.co.digitalfreedom.bucketeer.shared"]
    end

    subgraph HostBundle["Bucketeer.app<br/>(Mac App Store binary)"]
        HostEnt["Bucketeer.entitlements<br/>app-sandbox, network.client,<br/>files.user-selected.read-write,<br/>files.downloads.read-write,<br/>App Group, Keychain Sharing"]
        HostBin["host binary"]
    end

    subgraph FPBundle["Bucketeer File Provider.appex<br/>(embedded in host)"]
        FPEnt["BucketeerFileProvider.entitlements<br/>app-sandbox, network.client,<br/>App Group, Keychain Sharing"]
        FPBin["extension binary"]
    end

    subgraph SharedAtRuntime["Shared at runtime"]
        Container["App Group container<br/>SwiftData store: S3AccountRecord + SyncJobRecord"]
        Keychain["Keychain shared group<br/>per-account AccountCredentials JSON"]
    end

    subgraph AppStoreConnect["App Store Connect"]
        IAP["Non-Consumable IAP<br/>za.co.digitalfreedom.bucketeer.pro.lifetime<br/>€14.99 · Family Sharing"]
    end

    AppID -.- AppGroup
    AppID -.- KCGroup
    FPAppID -.- AppGroup
    FPAppID -.- KCGroup
    HostEnt -.- AppGroup
    HostEnt -.- KCGroup
    FPEnt -.- AppGroup
    FPEnt -.- KCGroup

    HostBin -->|reads/writes| Container
    HostBin -->|reads/writes| Keychain
    FPBin -->|reads only| Container
    FPBin -->|reads| Keychain

    HostBin -->|StoreKit| IAP
```

---

## 8. Test architecture

Tests live in `BucketeerCore/Tests/BucketeerCoreTests/`. `swift test`
runs them in ~25 ms; no Xcode test target is required.

| Suite | Tests | What it locks |
|---|---|---|
| `AzureSharedKeySigner` | 10 | StringToSign construction, canonical headers/resource, GET vs PUT Content-Length, signed Authorization shape |
| `AzureRequestBuilder` | 9 | URL composition, slash preservation, percent encoding, block-ID equal-length invariant, blockListXML body |
| `AzureListXMLParser` | 6 | container listing, blob listing with BlobPrefix + NextMarker, error envelope parse |
| `S3ClientFactory.endpoint` | 12 | per-provider URL templates (AWS, Civo, R2, B2, Wasabi, DO, Storj, Azure default + sovereign, Custom) |
| `S3Provider` | 11 | defaults, family routing, picker visibility flags, accountID requirements |
| `SyncPlanner` | 19 | plan computation, prefix relocation, name+size vs name+ETag, mirror deletes respect globs, 5 local-folder cases |
| `TrialBookkeeping` | 11 | trial start, expiry, sticky consumed marker, future-date clamp, custom length |
| `LocalFolderWriter.safeChildURL` | 6 | empty / absolute / `..` / `.` / legitimate paths |
| `BandwidthLimiter` (13.2) | 5 | unlimited fast-path, sub-burst, deficit-sleep loop, mid-flight toggle, `currentLimit` |
| `BucketStatsCollector` + `ProviderPricing` (13.5) | 6 | top-N maintenance, every provider rate, AWS GB precision, zero bytes |
| `AutoTagRuleEvaluator` (13.8) | 6 | empty list, disabled rules, empty-matches-all, `*`/`?` glob, case-insensitive MIME prefix, merge order |
| `BucketeerDeepLink` (13.11) | 9+4 | grammar round-trip per case, prefix variants, bad UUID, missing bucket, case-insensitive scheme, percent-encoded key, query string ignored |
| `BucketeerEnvelope` (13.15 + audit fix) | 9 | round-trip, header layout, wrong-key auth fail, garbage reject, prefix detection, tamper detection, **empty plaintext** (audit low #1), **version tamper** + **reserved tamper** (audit medium #1) |
| `TrashedItem.displayName` | 4 | multi-segment, single-segment, empty, trailing-slash folder-style |
| **Total** | **135** | |

Pure logic that lived in host classes was extracted to Core in three
waves (SyncPlanner, TrialBookkeeping, LocalFolderWriter) and then
incrementally per 13.x phase whenever the work was deterministic
(envelope, evaluator, fingerprint, parser). Core tests run in ~3 s
end-to-end; no Xcode test target is required.

---

## 9. Source-of-truth map

| Concern | File / dir |
|---|---|
| Composition root + SwiftData store URL migration | `Bucketeer/Services/AppContainer.swift` |
| App lifecycle (Window, MenuBarExtra, AppDelegate) | `Bucketeer/App/BucketeerApp.swift` |
| Provider endpoint matrix | `BucketeerCore/Sources/BucketeerCore/Models/S3Provider.swift` + `S3/S3ClientFactory.swift` |
| Azure signing | `BucketeerCore/Sources/BucketeerCore/Services/Azure/AzureSharedKeySigner.swift` |
| Per-family routing | `BucketeerCore/Sources/BucketeerCore/Services/ProviderRouter.swift` |
| Sync routing (4 paths) | `Bucketeer/Services/Sync/SyncEngine.swift` |
| Sync planning (pure) | `BucketeerCore/Sources/BucketeerCore/Services/Sync/SyncPlanner.swift` |
| Path-traversal guard | `BucketeerCore/Sources/BucketeerCore/Services/Sync/LocalFolderEnumerator.swift` (`LocalFolderWriter.safeChildURL`) |
| Trial logic | `BucketeerCore/Sources/BucketeerCore/Services/Entitlements/TrialBookkeeping.swift` |
| File Provider host coordinator | `Bucketeer/Services/MountController.swift` |
| File Provider extension | `Bucketeer File Provider/*` |
| Per-phase changelog | `CHANGELOG.md` |
| Manual setup checklist | `PHASE_9_SETUP.md` |
| App Store metadata draft | `docs/APP_STORE_METADATA.md` |
| Deep-link scheme + Info.plist requirement | `docs/DEEP_LINKS.md` |
| Audit log storage + recording hooks | `BucketeerCore/.../Services/Activity/ActivityLogStore.swift` + per-service `record(...)` calls |
| Soft-delete trash + cached restore | `BucketeerCore/.../Services/Trash/TrashStore.swift` + `Bucketeer/Services/Trash/TrashCoordinator.swift` |
| Resumable multipart upload | `BucketeerCore/.../Services/S3/S3ResumableUploader.swift` + `CheckpointStore.swift` |
| Client-side encryption envelope + key store | `BucketeerCore/.../Services/Encryption/ObjectEncryptor.swift` + `EncryptionKeyStore.swift` + `Bucketeer/Services/Encryption/BucketEncryptionGate.swift` |
| Bandwidth throttle | `BucketeerCore/.../Services/Transfers/BandwidthLimiter.swift` + `Bucketeer/Services/Transfers/BandwidthSettings.swift` |
| Auto-tag rule engine | `BucketeerCore/.../Services/AutoTag/AutoTagRuleEvaluator.swift` + `Bucketeer/Services/AutoTag/AutoTagCoordinator.swift` |
| Bucket dashboard + insights | `BucketeerCore/.../Services/Stats/BucketStatsCollector.swift` + `ProviderPricing.swift` + `Bucketeer/Views/Browser/BucketDashboardSheet.swift` |
| Cross-account copy / move | `Bucketeer/Services/CrossAccount/CrossAccountCopyCoordinator.swift` |
| `bucketeer://` deep links | `BucketeerCore/.../Services/DeepLink/BucketeerDeepLink.swift` + `Bucketeer/Services/DeepLink/DeepLinkRouter.swift` |
| App Intents (Shortcuts / Siri) | `Bucketeer/Services/AppIntents/*.swift` |
| Spotlight indexing | `Bucketeer/Services/Spotlight/SpotlightIndexer.swift` + `SpotlightSettings.swift` |
| Hardware-key detection (preview) | `Bucketeer/Services/HardwareKey/HardwareKeyAvailability.swift` + `HardwareKeySettings.swift` |
