# Phase 9 + 9.5 — File Provider Extension setup

After Phase 9.5 the host-side code is fully wired. The extension code
under `Bucketeer File Provider/` does **live** S3 and Azure traffic via
the shared `BucketeerCore` Swift package. The remaining one-time setup:

1. Register two identifiers at developer.apple.com (App Group + shared
   Keychain group).
2. Add the extension target in Xcode 16 and point it at the existing
   `Bucketeer File Provider/` directory.
3. Add the `BucketeerCore` local package as a dependency on the
   extension target.

That's it — the host's SwiftData store has already been migrated to the
App Group container; the extension's `ExtensionContainer` reads it
read-only on init.

## What's already in place

| File | Purpose |
|---|---|
| `BucketeerCore/Package.swift` | Local SPM package with shared models + services |
| `BucketeerCore/Sources/BucketeerCore/Models/*.swift` | Sendable value types (S3Account, S3Provider, S3Object, ...) + `@Model S3AccountRecord` |
| `BucketeerCore/Sources/BucketeerCore/Services/*` | KeychainStore, AccountStore, S3ClientFactory, S3Service, Azure stack, ProviderRouter, ServiceProtocols, AppEnvironment |
| `Bucketeer File Provider/ExtensionContainer.swift` | Sendable composition root for the extension — instantiates KeychainStore (shared access group), AccountStore (App Group SwiftData), S3ClientFactory, AzureBlobObjectStore + AzureBlobTransporter, ProviderRouter |
| `Bucketeer File Provider/FileProviderExtension.swift` | `NSFileProviderReplicatedExtension` shell — every callback delegates to `FileProviderItemResolver` |
| `Bucketeer File Provider/FileProviderItemResolver.swift` | Live S3 / Azure traffic for item resolve / fetch / create / modify / delete; identifier ↔ key encoding; capability flags per Apple's HIG (allowsReading/Writing/Deleting/Renaming for files, allowsContentEnumerating/AddingSubItems/Deleting/Renaming for folders); contentType returns proper UTType including `.folder` |
| `Bucketeer File Provider/FileProviderEnumerator.swift` | Paginated listing via the existing `S3Browsing.listObjects` continuation token; per-call fresh sync anchor so the system never gets stuck on stale data |
| `Bucketeer File Provider/S3DirectFetch.swift` | Soto-backed upload / download for the extension (bypasses the host's TransferManager queue) |
| `Bucketeer File Provider/BucketeerFileProvider.entitlements` | App Group + shared Keychain group + sandbox + network client |
| `Bucketeer File Provider/Info.plist` | `NSExtensionPrincipalClass = FileProviderExtension`, enumeration on |
| `Bucketeer/Services/MountController.swift` | Host-side `NSFileProviderManager.add/remove` wrapper |
| `Bucketeer/Bucketeer.entitlements` | App Group + shared Keychain group on the host |
| `Bucketeer/Services/AppContainer.swift` | Idempotent SwiftData migration: copies the legacy sandbox store into the App Group container the first time the entitlement is provisioned (incl. WAL / SHM sidecar files) |

## Step 1 — register at developer.apple.com (once)

1. Identifiers → App Groups → `+` → **`group.za.co.digitalfreedom.bucketeer`**
2. Identifiers → Keychain Sharing → `+` → **`za.co.digitalfreedom.bucketeer.shared`**
3. Identifiers → App IDs → `za.co.digitalfreedom.Bucketeer` → enable
   **App Groups** and **Keychain Sharing**, link the two identifiers above
4. Identifiers → App IDs → `+` for the extension:
   **`za.co.digitalfreedom.Bucketeer.FileProvider`**, enable the same
   two capabilities and link the same identifiers
5. Provisioning profiles regenerate automatically when "Automatically
   manage signing" is on

## Step 2 — add the extension target in Xcode (once)

1. Open `Bucketeer.xcodeproj`
2. **File → New → Target → File Provider Extension**
3. Product name: **Bucketeer File Provider**, Language: Swift, Lifetime: macOS
4. After Xcode creates the target:
   - **Delete** the auto-generated `FileProviderExtension.swift` /
     `FileProviderEnumerator.swift` Xcode added (they are stubs that
     conflict with the live versions in this repo)
   - In the Project navigator, remove the references Xcode added under
     the new group
   - Drag the existing `Bucketeer File Provider/` folder onto the new
     target and choose **Create folder references** (this creates a
     `PBXFileSystemSynchronizedRootGroup` so every file in the folder
     gets auto-included)
   - Signing & Capabilities tab: set the entitlements file to
     `Bucketeer File Provider/BucketeerFileProvider.entitlements`
   - Build Settings: set `PRODUCT_BUNDLE_IDENTIFIER = za.co.digitalfreedom.Bucketeer.FileProvider`
   - Build Settings: set `INFOPLIST_FILE = Bucketeer File Provider/Info.plist`
5. **Add the BucketeerCore dependency**: select the extension target →
   General → Frameworks and Libraries → `+` → **BucketeerCore**. The
   package was added to the host in Phase 9.5 so it's already
   resolved; you only need to link the product into the extension.
6. Select the **Bucketeer** target → General → **Frameworks, Libraries,
   and Embedded Content** → `+` → add **Bucketeer File Provider.appex**
   → **Embed & Sign**
7. Build the host scheme — both targets sign and the extension lands
   inside `Bucketeer.app/Contents/PlugIns/`

## Step 3 — verify locally

Run the host scheme, add an account, right-click a bucket →
**Mount as Drive**. The bucket appears in Finder → Locations with the
name `<account>: <bucket>`. Open it — the system calls the extension's
enumerator, which lists blobs/objects via the shared `ProviderRouter`.
Read / create / modify / delete from Finder all route through
`FileProviderItemResolver`.

If you see `NSFileProviderError.providerNotFound`, the App Group is
not yet provisioned — go back to Step 1.

## v1.1 backlog

- `NSFileProviderManager.signalEnumerator()` from the host on
  bucket-write operations so Finder sees the change immediately
  (currently the system polls; the per-call sync anchor keeps caches
  short)
- Working-set enumerator (favourites, pending, recents) for richer
  Finder integration
- Promote keychain access group on the host from `nil` to
  `AppEnvironment.keychainAccessGroup` with a one-shot migration of
  existing entries — currently the host writes to the private namespace
  so the extension only sees credentials added *after* a provisioned
  build. Tracked as Codex review #10 follow-up.
- Flat-listing primitive on `S3Browsing` to skip the per-prefix recursion
  in the sync engine and the file provider walk for huge buckets
