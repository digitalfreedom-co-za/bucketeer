# Phase 9 — File Provider Extension setup

The host-side code (mount controller, sidebar mount toggle, App Group
SwiftData store migration, entitlements) ships in the `development`
branch and builds without any further changes. The extension itself
needs a one-time manual setup because:

- Adding a `.appex` target to an Xcode 16 project with
  `PBXFileSystemSynchronizedRootGroup` requires Xcode UI (the schema
  for synced groups + a new target with cross-target embedding is
  fragile to script by hand).
- The App Group + shared Keychain access group must be registered at
  developer.apple.com before any signed build will accept the
  entitlements.

## What's already in place

| File | Purpose |
|---|---|
| `Bucketeer File Provider/FileProviderExtension.swift` | `NSFileProviderReplicatedExtension` shell with the seven required callbacks |
| `Bucketeer File Provider/FileProviderEnumerator.swift` | Per-prefix listing stub (returns empty in v1; real S3/Azure walk lands in v1.1 alongside the Core framework split) |
| `Bucketeer File Provider/FileProviderItemResolver.swift` | Async S3/Azure orchestration surface (stubbed in v1) |
| `Bucketeer File Provider/BucketeerFileProvider.entitlements` | App Group + shared Keychain group |
| `Bucketeer File Provider/Info.plist` | `NSExtensionPrincipalClass = FileProviderExtension`, enumeration on |
| `Bucketeer/Services/MountController.swift` | Host-side `NSFileProviderManager.add/remove` wrapper |
| `Bucketeer/Bucketeer.entitlements` | App Group + shared Keychain group on the host |
| `Bucketeer/Services/AppContainer.swift` | Idempotent migration that copies the sandbox SwiftData store into the App Group container the first time the entitlement is provisioned |

## Step 1 — register at developer.apple.com (once)

1. Identifiers → App Groups → `+` → **`group.za.co.digitalfreedom.bucketeer`**
2. Identifiers → Keychain Sharing → `+` → **`za.co.digitalfreedom.bucketeer.shared`**
3. Identifiers → App IDs → `za.co.digitalfreedom.Bucketeer` → enable **App Groups** and **Keychain Sharing**, link the two identifiers above
4. Identifiers → App IDs → `+` for the extension: **`za.co.digitalfreedom.Bucketeer.FileProvider`**, enable **App Groups** and **Keychain Sharing**, link the same two identifiers
5. Provisioning profiles regenerate automatically when "Automatically manage signing" is on

## Step 2 — add the extension target in Xcode (once)

1. Open `Bucketeer.xcodeproj`
2. File → New → Target → **File Provider Extension**
3. Product name: **Bucketeer File Provider**
4. Language: Swift, lifetime: macOS
5. After Xcode creates the target:
   - Delete the auto-generated `FileProviderExtension.swift` / `FileProviderEnumerator.swift` Xcode added (they are placeholders)
   - In Project navigator, **remove the references** Xcode added under the new group
   - In the Project navigator, drag the existing `Bucketeer File Provider/` folder onto the new target and choose **"Create folder references"** (PBXFileSystemSynchronizedRootGroup) — or in the Target's General tab, set "Resources Path" to point at the folder
   - In the target's Signing & Capabilities tab: set the entitlements file to `Bucketeer File Provider/BucketeerFileProvider.entitlements`
   - In Build Settings: set `PRODUCT_BUNDLE_IDENTIFIER = za.co.digitalfreedom.Bucketeer.FileProvider`
   - In Build Settings: set `INFOPLIST_FILE = Bucketeer File Provider/Info.plist`
6. Select the host **Bucketeer** target → General → **Frameworks, Libraries, and Embedded Content** → `+` → add the `Bucketeer File Provider.appex` and set **Embed Without Signing** → **Embed & Sign**
7. Build the host scheme — both targets sign and the extension lands inside `Bucketeer.app/Contents/PlugIns/`

## Step 3 — promote shared services to a Core framework (v1.1)

The current stubs in `FileProviderItemResolver` return errors because
`S3ClientFactory`, `AzureBlobObjectStore`, `KeychainStore` and
`AccountStore` live in the host module and can't be re-imported into
the extension target without duplication. v1.1 extracts the `Models/`
and `Services/` directories into a new **Bucketeer Core** framework
target that both the host and the extension link against. The wiring
in the extension then becomes a straight call into
`Container.shared.s3Browser.listObjects(...)`.

Until that lands, mounts appear as empty folders in Finder. The mount
UI surface is fully functional for testing the round-trip.

## Step 4 — verify locally

After Step 2 finishes, run the host scheme, add an account, right-click
a bucket → "Mount as Drive". The bucket appears in Finder → Locations
with the name `<account>: <bucket>`. Click "Unmount" to remove.

If you see `NSFileProviderError.providerNotFound`, the App Group is
not yet provisioned — go back to Step 1.

## v1.1 backlog

- Extract `Bucketeer Core` framework
- Wire the resolver stubs to live S3 / Azure traffic
- Flat-listing primitive on `S3Browsing` so the recursive enumeration
  in Phase 10 and the File Provider walk both stop fan-out (v1.1)
- `NSFileProviderManager.signalEnumerator()` calls from the host app on
  bucket-write operations so Finder sees the change immediately
