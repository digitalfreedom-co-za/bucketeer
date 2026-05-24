# Bucketeer — Developer Setup

How to take a fresh clone of this repository to a running Bucketeer
binary on your Mac. The legal binary distribution path is the Mac App
Store; what's below is the developer / contributor workflow.

---

## 1. Prerequisites

| Tool | Minimum | Used for |
|---|---|---|
| **macOS** | 14.0 | Runtime + Xcode 16 host |
| **Xcode** | 16.0 | Build the host app + extension targets |
| **Swift toolchain** | 6.0 | Bundled with Xcode 16; `swift test` for the Core package |
| **Apple Developer account** | Free for local debug, paid for shared App Group / Keychain / IAP work | Code signing for any signed run |
| Optional: **codex CLI** | 0.130+ | Multi-agent code review (`codex exec`) |
| Optional: **jq, python3** | system-default | The legal-doc and translation merge scripts use both |

The repository ships no Homebrew dependency. Everything else is Swift
Package Manager (`Bucketeer.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`).

---

## 2. Clone + first build

```bash
git clone https://github.com/digitalfreedom-co-za/bucketeer.git
cd bucketeer

# Resolve packages once. Xcode does this automatically on open;
# CLI builds need it explicit.
xcodebuild -resolvePackageDependencies -project Bucketeer.xcodeproj

# Debug build, no code signing (fastest, fine for unsigned runs):
xcodebuild build \
  -project Bucketeer.xcodeproj \
  -scheme Bucketeer \
  -configuration Debug \
  -destination 'generic/platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
```

Or open `Bucketeer.xcodeproj` in Xcode and Cmd+R.

The product lands at:
`~/Library/Developer/Xcode/DerivedData/Bucketeer-*/Build/Products/Debug/Bucketeer.app`.

---

## 3. Run the Core test suite

`BucketeerCore` is a local Swift package with an SPM test target. No
Xcode test bundle required.

```bash
cd BucketeerCore
swift test
```

Expected output: **84 tests in 8 suites, all green**, ~25 ms wall.

Suites:

| Suite | Tests | What it covers |
|---|---|---|
| `AzureSharedKeySigner` | 10 | Azure Shared-Key HMAC-SHA256 signing |
| `AzureRequestBuilder` | 9 | URL composition + block-blob XML |
| `AzureListXMLParser` | 6 | container + blob XML parsing |
| `S3ClientFactory.endpoint` | 12 | per-provider URL templates |
| `S3Provider` | 11 | defaults + family routing |
| `SyncPlanner` | 19 | diff plans, mirror deletes, local-folder paths |
| `TrialBookkeeping` | 11 | trial bookkeeping incl. clamp + sticky marker |
| `LocalFolderWriter.safeChildURL` | 6 | path-traversal guard |

Add new test files alongside the existing ones under
`BucketeerCore/Tests/BucketeerCoreTests/`. Use Swift Testing
(`import Testing`, `@Test`, `#expect`) — not XCTest.

---

## 4. Daily build commands

Aliases that pay off if you build often:

```bash
# Build, no code signing (unsigned binary, fastest):
bktbuild() {
  xcodebuild build \
    -project ~/Developer/projects/bucketeer/Bucketeer.xcodeproj \
    -scheme Bucketeer -configuration Debug \
    -destination 'generic/platform=macOS' \
    CODE_SIGNING_ALLOWED=NO
}

# Quick Core test loop:
bkttest() {
  ( cd ~/Developer/projects/bucketeer/BucketeerCore && swift test )
}

# Codex-style multi-agent review of the unstaged diff:
bktreview() {
  ( cd ~/Developer/projects/bucketeer
    codex exec --skip-git-repo-check "Review the unstaged diff for correctness, production-readiness, Apple guidelines, dead code." )
}
```

---

## 5. Scheme situation

No `.xcscheme` files are committed. Xcode auto-generates schemes from
target names, so `-scheme Bucketeer` is canonical.

There's a leftover `S3 Browser.xcscheme_^#shared#^_` entry in
`xcuserdata/.../xcschememanagement.plist` from before the rename. No
actual scheme file backs it — ignore it.

---

## 6. App-Sandbox-aware testing tips

The App is sandboxed even in Debug. Practical implications when you
run from Xcode:

- **Account credentials** live in the macOS Keychain. Debug runs
  without provisioned shared-group entitlement fall back to the
  private namespace, so the File Provider extension (if you wire it
  up) cannot read them across processes. Add accounts after enabling
  the shared group to test the extension path end-to-end.
- **Local-folder sync** asks for security-scoped bookmarks via
  NSOpenPanel. Bookmarks resolved from the previous session will
  surface `isStale` if you've moved the folder — the engine throws
  `sandboxAccessDenied` so you re-pick.
- **Preview cache** lives in `~/Library/Containers/za.co.digitalfreedom.Bucketeer/Data/tmp/BucketeerPreviews/`
  while debug-running.
- **App Group SwiftData store** lands at
  `~/Library/Group Containers/group.za.co.digitalfreedom.bucketeer/Bucketeer.store`
  once the entitlement is provisioned; otherwise the fallback path
  inside the sandbox container is used (see
  `AppContainer.resolveStoreURL`).

---

## 7. Working on the File Provider extension

The host-side code, MountController, ExtensionContainer, resolvers
and entitlements file are all in the tree. The extension **target**
itself is the only piece not committed to the project — adding an
appex target via raw `project.pbxproj` editing is fragile, so the
manual Xcode step is documented in `PHASE_9_SETUP.md`. Follow that
file when you want to bring the mount feature to life.

---

## 8. StoreKit testing

Phase B paywall uses StoreKit 2. The Mac App Store IAP product
`za.co.digitalfreedom.bucketeer.pro.lifetime` must exist in App Store
Connect before TestFlight or production builds will see it.

Local testing uses `Bucketeer/Bucketeer.storekit`, which the scheme
references (Xcode → Edit Scheme → Run → Options → StoreKit
Configuration). Reset the local entitlement via Xcode → Debug →
StoreKit → Manage Transactions during runs.

The 14-day trial timer persists in `UserDefaults` with keys
`bucketeer.trial.start` and `bucketeer.trial.consumed`. To restart a
trial during development, delete both — the consumed-marker is
specifically sticky in production to block the trial-reset bypass.

---

## 9. Adding a new language

`Localizable.xcstrings` is the single string catalog at
`Bucketeer/Resources/Localizable.xcstrings`. The standard supported
languages are `en, de, es, fr, it, ja, ko, nl, pl, pt-BR`.

To add another language:

1. In Xcode, open the catalog file, click **+** at the bottom-left to
   add the new locale. Xcode marks every key untranslated.
2. Translate. The catalog UI shows untranslated counts and lets you
   filter by state.
3. Add a matching `<lang>.lproj/InfoPlist.strings` with
   `CFBundleDisplayName = "Bucketeer";`
4. Verify by building the host with the new locale set in
   `Run → Options → App Language`.

The German UI never genders — generic masculine throughout. Same rule
mirrors to other locales.

---

## 10. Useful entry points

| What you want to look at | Where |
|---|---|
| End-to-end architecture diagrams | `docs/ARCHITECTURE.md` |
| Per-phase design specs | `docs/superpowers/specs/` |
| File Provider manual setup | `PHASE_9_SETUP.md` |
| App Store metadata draft | `docs/APP_STORE_METADATA.md` |
| Composition root | `Bucketeer/Services/AppContainer.swift` |
| Sync engine | `Bucketeer/Services/Sync/SyncEngine.swift` |
| BucketeerCore public surface | `BucketeerCore/Sources/BucketeerCore/` |
| All legal docs | `Bucketeer/Resources/Legal/` |
| Contributing rules | `CONTRIBUTING.md` |
| Per-phase changelog | `CHANGELOG.md` |
