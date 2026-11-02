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

## Step 2 — extension target (DONE — committed in the project)

The extension target is now part of `Bucketeer.xcodeproj`, added
programmatically via `scripts/add_file_provider_target.rb` (uses the
`xcodeproj` gem, so no hand-edited pbxproj). Re-running the script is a
no-op once the target exists. What it wired:

- Target **Bucketeer File Provider**, product type app-extension,
  bundle id `za.co.digitalfreedom.Bucketeer.FileProvider`
- The five source files in `Bucketeer File Provider/` in its Sources
  phase; links **SotoS3** + **BucketeerCore** (same package refs the
  host uses)
- `INFOPLIST_FILE = Bucketeer File Provider/Info.plist`,
  `GENERATE_INFOPLIST_FILE = NO`,
  `CODE_SIGN_ENTITLEMENTS = Bucketeer File Provider/BucketeerFileProvider.entitlements`,
  `APPLICATION_EXTENSION_API_ONLY = YES`
- **`MACOSX_DEPLOYMENT_TARGET = 14.1`** for the extension (the host
  stays 14.0). `NSFileProviderError.providerDomainNotFound` is a
  FileProvider API-v6.0 symbol = macOS 14.1, so the extension needs
  14.1. Consequence: Mount-as-Drive requires macOS 14.1+; the rest of
  the app runs on 14.0. This split is App-Store-legal.
- Host: target dependency on the extension + an *Embed Foundation
  Extensions* copy-files phase (PlugIns) that bundles the `.appex`

Verified: `xcodebuild … CODE_SIGNING_ALLOWED=NO build` succeeds and
`Bucketeer.app/Contents/PlugIns/Bucketeer File Provider.appex` is
present. Final archive-time code signing still needs the identifiers
from Step 1 registered at developer.apple.com.

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
  build.
- Flat-listing primitive on `S3Browsing` to skip the per-prefix recursion
  in the sync engine and the file provider walk for huge buckets
