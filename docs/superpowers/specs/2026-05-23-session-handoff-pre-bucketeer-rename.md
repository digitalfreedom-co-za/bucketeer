# Session Handoff — pre-Bucketeer-rename state

**Date:** 2026-05-23
**Branch:** `development`
**Last commit before rename:** see `git log --oneline | head -1` at the time this file was committed
**Repo:** still `digitalfreedom-co-za/s3-browser` at this snapshot — about to be renamed to `digitalfreedom-co-za/bucketeer`
**Local path:** still `/Users/marcelrgberger/Developer/projects/S3 Browser/` at this snapshot — about to be renamed to `/Users/marcelrgberger/Developer/projects/bucketeer/`

---

## Why this document exists

The next session begins **after** a wholesale rename of the project to **Bucketeer**. To make sure the new session can pick up without re-discovery, this file captures exactly what is done, what is in flight, and what comes next.

---

## What works today (Phases 0 – 5, plus polish)

- **Project scaffold** — license, EULA, Privacy Policy, Impressum, Open Source Notices bundled. Privacy manifest with required-reason API codes. Localizable.xcstrings seeded en/de. Soto-S3 7.14 wired via SPM. App icon generated at all 10 macOS sizes. Display name set via `INFOPLIST_KEY_CFBundleDisplayName`. macOS 26.4 deployment target. Swift 6 strict concurrency. App Sandbox + user-selected RW.
- **Domain models** — `S3Provider` (now nine cases, the ninth `.azureBlob` is planned), `S3Account`, `S3Bucket`, `S3Object`, `S3Page`, `TransferTask`, `TransferState`, `TransferDirection`, `AccountCredentials`, `S3BrowserError`. All Sendable, all `nonisolated` by default (the project no longer forces MainActor isolation globally).
- **Account CRUD** — SwiftData `S3AccountRecord` in Application Support, Keychain for credentials (no shared access group until Phase 9), `AccountStore` as `@ModelActor`, `KeychainStore` as plain actor. Add/Edit sheet with provider-aware region pickers, hide-path-style toggle on AWS, strict http/https endpoint parsing, async commit with inline error and progress overlay, lastUsedAt preserved on edit, `hasHydrated` guard so provider `onChange` does not race the initial hydration.
- **Touch-ID / password reveal** — `AddEditAccountSheet` opens with non-secret fields prefilled; secret fields blank by default; a "Reveal stored credentials" button gates on `LAContext.deviceOwnerAuthentication`; on success access key, secret and session token populate. Eye buttons (`RevealableSecureField`) toggle between obfuscated and plaintext for secret and session token.
- **Connection test** — Test Connection button on the Add/Edit sheet; builds a throwaway `AWSClient`, calls `listBuckets`, shuts it down. Inline ✓ / ✗ result in the sheet.
- **S3 connectivity** — `S3ClientFactory` actor caches one `S3` client per account, re-checks the cache after the Keychain await to avoid leaking duplicates. Civo defaults to path-style. `s3ForceVirtualHost` opt-in for the other AWS-style hyperscalers. Endpoint construction per provider in one pure function.
- **Browsing** — `S3BrowserService` does `listBuckets`, `listObjectsV2` with delimiter, `head`, `copy`, `deleteObject` + `deleteObjects` (inspects `response.errors` for per-key failures), `putObject` zero-byte for create-folder. Typed Soto error mapping (`S3ErrorType`, `AWSErrorType`, `AWSRawError` with status + body excerpt, `NoSuchRecord` / `CannotFindHost` → friendly DNS message with the Path-Style hint).
- **Browser UI** — `BrowserViewModel` with monotonic `requestGeneration` guard against navigation races, `BucketListView` (card grid), `ObjectListView` (`Table` with selection, search, breadcrumb bar, pagination button), `BreadcrumbBar`, `ObjectDetailView` (metadata for single, count + cumulative size for multi).
- **Transfers** — `TransferManager` actor with `AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))` for the public `tasks` snapshot. Multipart threshold 5 MB, part size 8 MB, max 4 concurrent. Upload via `multipartUpload(filename:)` or `putObject(buffer:)`. Download routes on size: zero-byte → write empty file; <5 MB → single-shot `getObject` + `body.collect`; ≥5 MB → `multipartDownload`. Pre-removes target file. Security-scoped resource wrapping for the picked URLs. `terminated: Set<UUID>` so late progress / completion cannot overwrite `.cancelled`. `cancelAll(for: accountID)` called from `AccountListViewModel.delete` before the client is invalidated. Transfers sidebar section becomes a `NavigationLink` with active-count badge; `TransferListView` shows progress, byte counters, cancel, and clear-finished.
- **Object actions** — Delete (single + multi with confirmation dialogs that adapt copy to selection count), Rename (server-side `CopyObject` + `DeleteObject`, name-validation, hint about the 5 GB single-request limit), New Folder (zero-byte prefix with `⇧⌘N` shortcut), all routed through `BrowserViewModel.delete / rename / createFolder` with an `actionError` alert.
- **Migrations** — `AppContainer.runMigrations(_:)` on every launch flips any Civo `S3AccountRecord` still carrying the old default `usesPathStyle == false` to `true`, idempotent and best-effort.
- **App menu** — replaces `.appInfo` and `.help` command groups. Custom multi-section About window (About, License, EULA, Privacy, Open Source, Impressum) renders the bundled markdown via `MarkdownView` (block-aware: headings, paragraphs, bullet lists, inline bold/italic/code/links). Help window renders `Resources/Help/QuickStart.md`. Help menu also has GitHub / Issue / Website links and convenience entries for Privacy Policy and EULA.
- **Privacy** — no data collection by the publisher, declared in the Privacy Policy bundled in-app and in `PrivacyInfo.xcprivacy`.
- **Code review** — Codex was invoked for Phases 2, 3, 4 and 5, every finding (six per phase on average) addressed before push.

Build is clean under Swift 6 strict concurrency on `xcodebuild build -configuration Debug -destination 'generic/platform=macOS'`.

---

## Pending design decisions (carry over)

### Phase A (Azure Blob Storage)

The plan lives at `docs/superpowers/specs/2026-05-23-phase-a-azure-blob-storage.md`. Three open questions in §8:

1. **Auth modes**: my default for v1.0 is Account Name + Account Key only. SAS Token deferred to v1.1, OAuth2 / Entra ID to v2. **Awaiting user confirm.**
2. **Hierarchical namespace (ADLS Gen2)**: my default is skip in v1.0 — flat namespace mirrors S3 UX. **Awaiting user confirm.**
3. **Folder semantics**: my default is `/`-delimiter flat namespace identical to S3. **Awaiting user confirm.**

Once confirmed, Phase A.1 (Azure foundation: signer, request builder, list/head/delete/copy) can start.

### After Bucketeer rename

- **Phase A** vs **Phase 6 (Preview / Quick Look)** ordering — my recommendation in the Phase A plan is to do Azure first (provider router shapes the rest of the work). User has not chosen yet.
- App Store Connect record needs to be created under the new name **Bucketeer**.
- Xcode Cloud workflows need to be recreated for the renamed bundle ID.

---

## Roadmap as of this snapshot

```
Phase 0  Scaffold / Legal / SPM / Icon ............................. ✓
Phase 1  Sendable Models + Service protocols ....................... ✓
Phase 2  Account CRUD (SwiftData + Keychain) + Sidebar ............. ✓
Phase 3  S3 connectivity (Soto, browser service, browser VM) ....... ✓
Phase 4  Transfers (multipart up/down, queue, UI) .................. ✓
Phase 5  Object actions (delete / rename / new folder)
         + connection test + Touch-ID reveal + eye toggle
         + DNS error mapping + Civo path-style migration .......... ✓
         (extended polish — Help / About menus added) ............. ✓
─────────────────────────────────────────────────────────────────────
        ⇩ Bucketeer rename happens here ⇩
─────────────────────────────────────────────────────────────────────
Phase A  Azure Blob Storage (provider router + Azure backend) ..... planned
Phase 6  Preview cache + Quick Look (inline + spacebar) ........... planned
Phase 7  Drag-and-drop (Finder ↔ App, App ↔ App) .................. planned
Phase 8  Menubar background mode .................................. planned
Phase 9  File Provider Extension + App Group + shared Keychain .... planned
Phase 10 Sync Engine (S3↔S3, S3↔Azure copy/move/mirror) ........... planned
Phase 11 Localisation finalisation (en, de, es, fr, it, ja, ko,
         nl, pl, pt-BR) ........................................... planned
Phase 12 Hardening (accessibility, performance, App Store metadata,
         Privacy Manifest verification) ........................... planned
```

---

## Where to look in the codebase

| Concern | File |
|---|---|
| App entry, menus, About / Help windows | `S3 Browser/App/S3_BrowserApp.swift` (will become `Bucketeer/App/BucketeerApp.swift`) |
| Composition root + migrations | `S3 Browser/Services/AppContainer.swift` |
| Provider matrix + endpoints | `S3 Browser/Models/S3Provider.swift` + `S3 Browser/Services/S3/S3ClientFactory.swift` |
| Soto-backed S3 ops + error mapping | `S3 Browser/Services/S3/S3BrowserService.swift` |
| Transfer queue | `S3 Browser/Services/Transfers/TransferManager.swift` |
| Sidebar | `S3 Browser/Views/Sidebar/SidebarView.swift` |
| Add/Edit account + biometric reveal + eye toggle | `S3 Browser/Views/Accounts/AddEditAccountSheet.swift` |
| Bucket / Object list / Breadcrumb / Detail | `S3 Browser/Views/Browser/*` |
| Transfer queue UI | `S3 Browser/Views/Transfers/TransferListView.swift` |
| About / Help windows | `S3 Browser/Views/About/AboutWindow.swift`, `S3 Browser/Views/Help/HelpWindow.swift`, `S3 Browser/Views/MarkdownView.swift` |
| Strings | `S3 Browser/Resources/Localizable.xcstrings` |
| Bundled docs | `S3 Browser/Resources/Legal/*.md`, `S3 Browser/Resources/Help/QuickStart.md` |
| Phase plans | `docs/superpowers/specs/*` |

After the rename all `S3 Browser/...` paths become `Bucketeer/...`. The contract above does not otherwise change.

---

## Identifiers that change in the rename

| Before | After |
|---|---|
| App display name `S3 Browser` | `Bucketeer` |
| Bundle ID `za.co.digitalfreedom.S3-Browser` | `za.co.digitalfreedom.bucketeer` |
| Swift `@main struct S3_BrowserApp` | `BucketeerApp` |
| `S3BrowserError` | `BucketeerError` |
| `S3BrowserService` | `S3Service` (drops the app-specific Browser suffix; keeps the S3 protocol prefix) |
| App Group `group.za.co.digitalfreedom.s3-browser` | `group.za.co.digitalfreedom.bucketeer` (in code constants; not yet provisioned at Apple) |
| Keychain service `za.co.digitalfreedom.s3-browser` | `za.co.digitalfreedom.bucketeer` |
| Keychain access group suffix `.s3-browser.shared` | `.bucketeer.shared` |
| SwiftData store filename `S3Browser.store` | `Bucketeer.store` |
| Xcode project `S3 Browser.xcodeproj` | `Bucketeer.xcodeproj` |
| Source dir `S3 Browser/` | `Bucketeer/` |
| Entitlements file `S3 Browser.entitlements` | `Bucketeer.entitlements` |
| GitHub repo `digitalfreedom-co-za/s3-browser` | `digitalfreedom-co-za/bucketeer` |
| Local path `~/Developer/projects/S3 Browser/` | `~/Developer/projects/bucketeer/` |

S3-protocol domain types (`S3Account`, `S3Provider`, `S3Bucket`, `S3Object`, `S3Page`, `S3Browsing`, `S3ClientFactory`, `S3AccountRecord`) keep the `S3` prefix — that prefix refers to Amazon S3, not to the app name.

---

## What the new session should pick up

The user has indicated the next chunk after the rename is open between:

- **Phase A** (Azure) — needs the three §8 confirms before starting
- **Phase 6** (Preview / Quick Look) — can start immediately

Recommend: do Phase A first so subsequent phases speak both protocols natively. Either way, this handoff document, the design spec at `docs/superpowers/specs/2026-05-22-s3-browser-design.md` (will be renamed in-place) and the Phase A plan are the entry points.

---

## Operational notes for the new session

- **Branches**: `main`, `development`, `test`, `beta` all exist on origin. Work continues on `development`.
- **Build**: `xcodebuild build -project Bucketeer.xcodeproj -scheme Bucketeer -configuration Debug -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO` from the project root.
- **Multi-agent review**: per `~/.claude/CLAUDE.md`, Codex review is mandatory for substantive phases. Run `codex exec --skip-git-repo-check "..."` against the new Phase work.
- **Commit cadence**: per user directive, commit and push regularly — not in one big lump.
- **Local data**: SwiftData store moves with the App Sandbox container (bundle-ID-keyed). The bundle-ID change means existing accounts created under the old `za.co.digitalfreedom.S3-Browser` container will not be visible to the new `Bucketeer` build. On first launch the user will need to re-add accounts. The Keychain entries from the old bundle are similarly orphaned. This is unavoidable for a bundle-ID rename.

*End of handoff.*
