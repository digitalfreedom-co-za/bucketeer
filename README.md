# Bucketeer

A native macOS app for browsing, transferring, mounting and synchronising
object storage: Amazon S3, every S3-compatible service and Azure Blob
Storage.

Built in public. Source available. Distributed exclusively through the
Mac App Store.

---

## Status

**Bucketeer 1.0 for the Mac App Store.** The 1.0 feature set is complete
on the `development` branch and goes through the release branches
`test → beta → main` before submission. See [`CHANGELOG.md`](CHANGELOG.md)
for the development history.

---

## Features

### Accounts and security

- **Nine provider presets**: AWS S3, Azure Blob Storage, Civo,
  Cloudflare R2, Backblaze B2, Wasabi, DigitalOcean Spaces, Storj and
  Custom (MinIO or any other S3-compatible endpoint), with path-style
  addressing where the provider needs it
- **Credentials in the macOS Keychain**, never in the app's database
- **Touch ID or Mac password** before stored secrets are shown again
- **Hardware key (technical preview)**: Settings → Security lists
  connected smart-card readers; unlocking still uses Touch ID or the
  Mac password in 1.0
- **Client-side encryption per bucket**: AES-256-GCM on the Mac before
  upload, decryption on download, key kept in the Keychain and not
  exportable

### Browsing and transfers

- **Three-pane browser** with breadcrumbs, search and a details pane
- **Quick Look preview** for any file type macOS can show
- **Drag and drop** between Finder and Bucketeer
- **Multipart upload and download** with parallel parts and live progress
- **Resumable transfers**: an interrupted upload continues where it stopped
- **Bandwidth limit** for all transfers
- **Object actions**: new folder, rename, delete, download
- **Presigned links**: S3 presigned URLs and Azure SAS links, signed
  locally with an expiry you choose

### Insight and housekeeping

- **Bucket dashboard**: object count, total size, largest objects and a
  rough monthly cost estimate
- **Lifecycle, bucket policy and CORS viewer** (read-only)
- **Versions browser**: list, restore and delete object versions
- **Metadata and tags editor**: HTTP headers, user metadata, tags,
  storage class
- **Auto-tagging rules** for new uploads by file name pattern or MIME type
- **Trash**: optional local copy of deleted objects with restore and a
  retention period
- **Activity log** of transfers, deletes, sync runs, share links and
  account changes, with CSV export

### macOS integration

- **`bucketeer://` deep links** to accounts, buckets, objects, sync jobs,
  the activity log and the trash
- **Shortcuts and Siri (App Intents)**: list buckets, upload a file,
  create a presigned link, run a sync job
- **Spotlight** (opt-in): object names you browse become searchable;
  contents are never indexed
- **Localised in 20 locales**: English (US and UK), Czech, Danish, Dutch,
  Finnish, French, German, Greek, Hungarian, Italian, Japanese, Korean,
  Norwegian, Polish, Portuguese (Brazil and Portugal), Russian, Spanish,
  Swedish. The in-app help is translated into all of them.

### Bucketeer Pro

- **Mount as Drive**: use a bucket or container in Finder through the
  File Provider extension (macOS 14.1 or later). Buckets with
  client-side encryption cannot be mounted in this version.
- **Sync jobs**: copy, move or mirror between buckets, across accounts
  and providers (S3 ↔ Azure included), or between a local folder and a
  bucket; run by hand, at launch, on a schedule or when the local folder
  changes
- **Watch folders**: upload every new file in a local folder to a bucket
- **Copy to other account**: server-side copy when both accounts share
  provider and endpoint and neither bucket is encrypted, otherwise a
  download and upload through the Mac
- **Menu bar mode**: keeps mounts and sync jobs running with the main
  window closed

### Privacy

No Bucketeer server, no user account, no analytics, no tracking SDKs.
Account metadata, logs and caches stay on the Mac. Network traffic goes
only to the storage endpoints you configure and to Apple for purchases.
Details in the [Privacy Policy](Bucketeer/Resources/Legal/PRIVACY_POLICY.md).

---

## Free and Pro

| | Free | Pro |
|---|:---:|:---:|
| Accounts, all nine provider presets | ✅ | ✅ |
| Browse, Quick Look, search | ✅ | ✅ |
| Upload, download, drag and drop, resumable transfers, bandwidth limit | ✅ | ✅ |
| Rename, delete, new folder, presigned links | ✅ | ✅ |
| Dashboard, versions, metadata and tags, lifecycle / policy / CORS viewer | ✅ | ✅ |
| Trash, activity log, auto-tagging rules | ✅ | ✅ |
| Client-side encryption | ✅ | ✅ |
| Deep links, Shortcuts and Siri, Spotlight | ✅ | ✅ |
| Mount as Drive | | ✅ |
| Sync jobs and watch folders | | ✅ |
| Copy to other account | | ✅ |
| Menu bar mode | | ✅ |

Bucketeer Pro is a single one-time in-app purchase through the App Store,
with no subscription. The App Store shows the price in your currency.

<!-- Trial wording: the only place in this README that describes the trial. -->
**Trial:** a time-limited trial of Bucketeer Pro may be offered. Its
length is shown in the app before it starts; when it ends, Bucketeer
continues on the Free tier and nothing is charged.

---

## Documentation

| Doc | Purpose |
|---|---|
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Architecture reference with 18 Mermaid diagrams: user-level feature overview, module composition, deep-link and App Intents routing, sync routing, sandbox lifecycle, File Provider sequence, mount and unmount with the encrypted-bucket refusal, entitlement state machine, StoreKit purchase / restore / offer codes, account save flow, Touch ID secret reveal, multipart transfer flow, encryption key lifecycle, provisioning topology |
| [`docs/DEVELOPER_SETUP.md`](docs/DEVELOPER_SETUP.md) | Clone, build and test |
| [`PHASE_9_SETUP.md`](PHASE_9_SETUP.md) | One-time setup for the File Provider extension identifiers |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | Branch model, coding standards, review process |
| [`CHANGELOG.md`](CHANGELOG.md) | Development history |
| [`docs/APP_STORE_METADATA.md`](docs/APP_STORE_METADATA.md) | App Store Connect copy and launch checklist |

---

## Building locally

Requirements:

- macOS 14.0 or later (Mount as Drive needs 14.1)
- Xcode 16 or later (Swift 6 strict concurrency)

```bash
git clone https://github.com/digitalfreedom-co-za/bucketeer.git
cd bucketeer
open Bucketeer.xcodeproj
```

Select the **Bucketeer** scheme and press ⌘R.

Local builds are permitted for personal, non-commercial use under the
[Source-Available License](LICENSE).

---

## Architecture

Swift 6 strict concurrency end to end. SwiftUI for the host app. Soto
for AWS and every S3-compatible provider, a purpose-built Azure backend
for Azure Blob Storage, both behind a `ProviderRouter` so the upper
layers stay protocol-agnostic. SwiftData for account metadata in the
App Group container shared with the File Provider extension. Keychain
for credentials and encryption keys. StoreKit 2 for the Pro purchase.

```
Bucketeer.xcodeproj/
Bucketeer/                          host app target
  App/                              @main BucketeerApp, menus, commands
  Models/                           host-only value types
  Services/                         actors and controllers (AppContainer,
                                    transfers, sync, mount, entitlements,
                                    encryption, trash, Spotlight, App Intents,
                                    deep links, hardware key)
  ViewModels/
  Views/                            Accounts, Browser, Sidebar, Transfers,
                                    Sync, Activity, Trash, Paywall, Settings,
                                    Menubar, About, Help
  Resources/
    Legal/                          EULA, Privacy Policy, Impressum,
                                    License, open-source notices
    Help/<lang>.lproj/QuickStart.md in-app help, 20 locales
    Localizable.xcstrings           string catalog, 20 locales
    PrivacyInfo.xcprivacy
  <lang>.lproj/InfoPlist.strings    per-language CFBundleDisplayName
  Bucketeer.storekit                StoreKit configuration for local testing
Bucketeer File Provider/            File Provider extension (Mount as Drive)
BucketeerCore/                      local Swift package: models, S3, Azure,
                                    Keychain, sync planning, encryption
BucketeerTests/                     host test target
```

---

## Legal

| File | Scope |
|---|---|
| [`LICENSE`](LICENSE) | Source-Available License governing this **source code** |
| [`Bucketeer/Resources/Legal/EULA.md`](Bucketeer/Resources/Legal/EULA.md) | End User License Agreement governing the **app binary** |
| [`Bucketeer/Resources/Legal/PRIVACY_POLICY.md`](Bucketeer/Resources/Legal/PRIVACY_POLICY.md) | Privacy Policy |
| [`Bucketeer/Resources/Legal/IMPRESSUM.md`](Bucketeer/Resources/Legal/IMPRESSUM.md) | Legal notice (Impressum) |
| [`Bucketeer/Resources/Legal/OPEN_SOURCE_NOTICES.md`](Bucketeer/Resources/Legal/OPEN_SOURCE_NOTICES.md) | Third-party open-source attributions |

**Source-available, not OSI open source.** You may read the code, fork
it for study and contribute back. You may not redistribute it, ship
binaries or publish derivatives to any app store. The only binary
distribution is the App Store version published by DigitalFreedom
Global LLC.

The same documents are reachable in the app via **Bucketeer → About**
and the **Help** menu.

---

## Contributing

Issues and pull requests are welcome. Contributions are accepted under
the [Source-Available License](LICENSE); by submitting a pull request
you license your contribution to the publisher under the same terms.

For bug reports please include the macOS version, the app version and
the steps to reproduce.

---

## Publisher

DigitalFreedom Global LLC
30 N Gould St, Ste N, Sheridan, WY 82801, United States
Contact: hello@digitalfreedom.co.za
Website: https://digitalfreedom.co.za
