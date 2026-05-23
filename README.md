# S3 Browser

A native macOS app for browsing, transferring, mounting, and synchronising
S3-compatible object storage across multiple providers and credentials.

Built in public. Source available. Distributed exclusively through the
Mac App Store.

---

## Features (v1)

- Nine provider presets — AWS S3, Azure Blob Storage, Civo,
  Cloudflare R2, Backblaze B2, Wasabi, DigitalOcean Spaces, Storj,
  MinIO / Custom (Azure lands as Phase A between Phase 5 and Phase 6)
- Finder-style three-pane browser with inline Quick Look preview
- Drag-and-drop in every direction — Finder ↔ App, App ↔ App
- Mount buckets as drives in Finder via File Provider extension
- Background menubar mode that keeps mounts and sync alive
- S3-to-S3 copy / move / one-way mirror with optional scheduling
- Multipart upload, parallel transfers, progress tracking
- Localised in ten languages
- Privacy by design — credentials live in Keychain, nothing leaves your Mac
  apart from S3 traffic

See [`docs/superpowers/specs/2026-05-22-s3-browser-design.md`](docs/superpowers/specs/2026-05-22-s3-browser-design.md)
for the full design spec.

---

## Status

🚧 In active development. v1 implementation in progress on the
`development` branch. Not yet available on the App Store.

---

## Building locally

Requirements:

- macOS 26.0 or later
- Xcode 26 or later

```bash
git clone https://github.com/marcelrgberger/S3-Browser.git
cd "S3 Browser"
open "S3 Browser.xcodeproj"
```

Select the **S3 Browser** scheme and ⌘R to run.

Local builds are permitted for personal, non-commercial use under the
[Source-Available License](LICENSE).

---

## Architecture

Swift 6 strict concurrency. SwiftUI for the host app. Soto-S3 for the
provider abstraction. SwiftData for account metadata (in the App Group
container). Keychain for credentials (in a shared access group). File
Provider replicated extension for Finder mounts.

```
S3 Browser/          host app target
S3 Browser File Provider/   .appex (added in Phase 9)
S3 Browser Core/     embedded framework (added in Phase 9)
```

---

## Legal

This project is governed by three separate documents:

| File | Scope |
|---|---|
| [`LICENSE`](LICENSE) | Source-Available License governing this **source code** |
| [`S3 Browser/Resources/Legal/EULA.md`](S3%20Browser/Resources/Legal/EULA.md) | End User License Agreement governing the **App binary** |
| [`S3 Browser/Resources/Legal/PRIVACY_POLICY.md`](S3%20Browser/Resources/Legal/PRIVACY_POLICY.md) | Privacy Policy |
| [`S3 Browser/Resources/Legal/IMPRESSUM.md`](S3%20Browser/Resources/Legal/IMPRESSUM.md) | Impressum (German legal notice) |
| [`S3 Browser/Resources/Legal/OPEN_SOURCE_NOTICES.md`](S3%20Browser/Resources/Legal/OPEN_SOURCE_NOTICES.md) | Third-party open-source attributions |

**Build in Public, not open source.** You may read, fork for study, and
contribute back. You may not redistribute, ship binaries, or publish
derivatives to any app store. The single canonical binary distribution is
the App Store version published by the author.

---

## Contributing

Issues and pull requests are welcome. Contributions are accepted under the
[Source-Available License](LICENSE) — by submitting a PR you assign your
contribution to the Publisher and license it back to yourself under the
same terms as the rest of the source.

For bug reports please include macOS version, app version, and reproduction
steps.

---

## Publisher

DigitalFreedom — a brand of Berger & Rosenstock GbR
Dieselstr. 22e, 61231 Bad Nauheim, Germany
Contact: hello@digitalfreedom.co.za
Website: https://digitalfreedom.co.za
