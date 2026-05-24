# Bucketeer

A native macOS app for browsing, transferring, mounting and synchronising
object storage across every major provider — including Amazon S3, every
S3-compatible service, **and Azure Blob Storage**.

Built in public. Source available. Distributed exclusively through the
Mac App Store.

---

## Features

- **Nine provider presets** — AWS S3, **Azure Blob Storage**, Civo,
  Cloudflare R2, Backblaze B2, Wasabi, DigitalOcean Spaces, Storj,
  MinIO / Custom Endpoint
- **Finder-style three-pane browser** with inline metadata pane
- **Quick Look preview** for any macOS-supported file type *(roadmap Phase 6)*
- **Drag-and-drop in every direction** — Finder ↔ App, App ↔ App,
  cross-account, cross-provider *(roadmap Phase 7)*
- **Mount buckets and containers as Finder drives** via the File
  Provider extension *(roadmap Phase 9)*
- **Menubar background mode** that keeps mounts and sync alive when
  the main window is closed *(roadmap Phase 8)*
- **S3-to-S3, S3-to-Azure and Azure-to-S3** copy / move / one-way
  mirror with optional scheduling *(roadmap Phase 10)*
- **Multipart upload and download**, parallel transfers, live progress
- **Touch ID / password gate** for revealing stored secrets
- **Localised in 10 languages** — English, German, Spanish, French,
  Italian, Japanese, Korean, Dutch, Polish, Brazilian Portuguese
- **Privacy by design** — credentials live in your macOS Keychain,
  nothing leaves your Mac apart from the object-storage traffic you
  configure

---

## Pricing

Bucketeer is **free to evaluate for 14 days** with every feature
unlocked, then converts to a **Free tier** that keeps the core
browser usable, with **Bucketeer Pro** unlocked by a single
**€14.99 lifetime in-app purchase** (no subscription).

---

## Status

🚧 In active development. v1 implementation in progress on the
`development` branch. Not yet available on the App Store.

Phases 0 – 12, A, B and 9.5 – 9.10 are merged on `development`. The
`13.x` feature block ships incrementally — each phase lands as one
commit so the development history reads as a phase-by-phase log.

| Phase | Title | Status |
|------:|---|---|
| 0–5 | Scaffold → browser → transfers → object actions → reveal | ✅ |
| A | Azure Blob Storage via `ProviderRouter` | ✅ |
| 6 | Preview + Quick Look | ✅ |
| 7 | Drag and drop | ✅ |
| 8 | Menubar background mode | ✅ |
| 9 | File Provider scaffold | ✅ |
| 9.5 | Core SPM package + live File Provider | ✅ |
| 9.6 | Core test target (Swift Testing, 92 tests) | ✅ |
| 9.7 | Trial bookkeeping tests | ✅ |
| 9.8 | Local folder ↔ S3 sync | ✅ |
| 9.9 | Presigned download URLs (S3 + Azure SAS) | ✅ |
| 9.10 | Sync-on-change via FSEvents | ✅ |
| 10 | Sync engine | ✅ |
| 11 | Localisation finalisation | ✅ |
| B | Paywall (StoreKit 2, lifetime IAP) | ✅ |
| 12 | Hardening | ✅ |
| 13.1 | Activity log | ✅ |
| 13.2 | Bandwidth limit | ✅ |
| 13.3 | Watch folder → bucket | ✅ |
| 13.4 | Trash / soft-delete | ✅ |
| 13.5 | Bucket dashboard | ✅ |
| 13.6 | Versions browser | ✅ |
| 13.7 | Metadata / tags editor | ✅ |
| 13.8 | Auto-tagging rules | ✅ |
| 13.9 | Lifecycle / policy / CORS viewer | ✅ |
| 13.10 | Resumable transfers | ⏳ |
| 13.11 | `bucketeer://` URL scheme | ⏳ |
| 13.12 | App Intents (Shortcuts / Siri) | ⏳ |
| 13.13 | Spotlight indexing | ⏳ |
| 13.14 | Server-side copy across accounts | ⏳ |
| 13.15 | Client-side encryption per bucket | ⏳ |
| 13.16 | Hardware-key unlock (CryptoTokenKit) | ⏳ |

See [`CHANGELOG.md`](CHANGELOG.md) for the per-phase history and
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the architectural
reference.

**Documentation map:**

| Doc | Purpose |
|---|---|
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | End-to-end architecture with eight Mermaid diagrams (module composition, sync routing, sandbox lifecycle, File Provider sequence, entitlement state machine, account save flow, multipart transfer flow, provisioning topology) |
| [`docs/DEVELOPER_SETUP.md`](docs/DEVELOPER_SETUP.md) | Clone → build → test in five minutes |
| [`PHASE_9_SETUP.md`](PHASE_9_SETUP.md) | One-time manual setup for the File Provider extension target |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | Branch model, coding standards, review process |
| [`CHANGELOG.md`](CHANGELOG.md) | Per-phase development history |
| [`docs/APP_STORE_METADATA.md`](docs/APP_STORE_METADATA.md) | App Store Connect copy + launch checklist |

---

## Building locally

Requirements:

- macOS 14.0 or later
- Xcode 16 or later (Swift 6 strict concurrency)

```bash
git clone https://github.com/digitalfreedom-co-za/bucketeer.git
cd bucketeer
open Bucketeer.xcodeproj
```

Select the **Bucketeer** scheme and ⌘R to run.

Local builds are permitted for personal, non-commercial use under the
[Source-Available License](LICENSE).

---

## Architecture

Swift 6 strict concurrency end-to-end. SwiftUI for the host app.
Soto-S3 for the AWS family and every S3-compatible provider. A
purpose-built Azure backend (`AzureBlobObjectStore`, Phase A) for
Azure Blob Storage, dispatched through a `ProviderRouter` so the
upper layers stay protocol-agnostic. SwiftData for account metadata
(SwiftData store in the sandbox Application Support directory,
moving to an App Group container in Phase 9). Keychain for
credentials. File Provider replicated extension for Finder mounts.
LocalAuthentication for Touch-ID-gated secret reveal.

```
Bucketeer.xcodeproj/
Bucketeer/                          ← host app target
  App/                              @main BucketeerApp + menus
  Models/                           Sendable domain types
  Services/                         actors + protocols
    S3/                             Soto-backed S3Service
    Azure/                          (Phase A) URLSession + Shared Key
    Keychain/                       KeychainStore
    Account/                        AccountStore @ModelActor
    Transfers/                      TransferManager
  ViewModels/
  Views/
    Accounts/  Browser/  Sidebar/  Transfers/  About/  Help/
  Resources/
    Legal/                          EULA, Privacy, Impressum, License, OSS notices
    Help/                           QuickStart.md
    Localizable.xcstrings           10-language string catalog
    PrivacyInfo.xcprivacy
  <lang>.lproj/InfoPlist.strings    per-language CFBundleDisplayName
Bucketeer File Provider/            .appex (Phase 9)
Bucketeer Core/                     embedded framework (Phase 9)
```

---

## Legal

This project is governed by these documents:

| File | Scope |
|---|---|
| [`LICENSE`](LICENSE) | Source-Available License governing this **source code** |
| [`Bucketeer/Resources/Legal/EULA.md`](Bucketeer/Resources/Legal/EULA.md) | End User License Agreement governing the **App binary** |
| [`Bucketeer/Resources/Legal/PRIVACY_POLICY.md`](Bucketeer/Resources/Legal/PRIVACY_POLICY.md) | Privacy Policy |
| [`Bucketeer/Resources/Legal/IMPRESSUM.md`](Bucketeer/Resources/Legal/IMPRESSUM.md) | Impressum (German legal notice) |
| [`Bucketeer/Resources/Legal/OPEN_SOURCE_NOTICES.md`](Bucketeer/Resources/Legal/OPEN_SOURCE_NOTICES.md) | Third-party open-source attributions |

**Source-available, not OSI-open-source.** You may read, fork for
study, and contribute back. You may not redistribute, ship binaries,
or publish derivatives to any app store. The single canonical binary
distribution is the App Store version published by the author.

The same documents are reachable in-app via **Bucketeer → About**.

---

## Contributing

Issues and pull requests are welcome. Contributions are accepted
under the [Source-Available License](LICENSE) — by submitting a PR
you license your contribution to the Publisher under the same terms.

For bug reports please include macOS version, app version, and
reproduction steps.

---

## Publisher

DigitalFreedom — a brand of Berger & Rosenstock GbR
Dieselstr. 22e, 61231 Bad Nauheim, Germany
Contact: hello@digitalfreedom.co.za
Website: https://digitalfreedom.co.za
