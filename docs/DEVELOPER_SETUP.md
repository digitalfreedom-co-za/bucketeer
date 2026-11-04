# Bucketeer — Developer Setup

How to take a fresh clone of this repository to a running Bucketeer
binary on your Mac. The legal binary distribution path is the Mac App
Store; what's below is the developer / contributor workflow.

---

## 1. Prerequisites

| Tool | Minimum | Used for |
|---|---|---|
| **macOS** | 15.8 | Runtime (deployment target of every target and of BucketeerCore) |
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

## 3. Run the tests

Tests exist only where they pay for themselves: formulas, business
rules and flows, plus off-screen renders of every screen. No blanket
suites.

### Core package

`BucketeerCore` is a local Swift package with an SPM test target
(Swift Testing: `import Testing`, `@Test`, `#expect`).

```bash
swift test --package-path BucketeerCore               # all (~140 tests, ~3 s)
swift test --package-path BucketeerCore --filter SyncPlanner
```

### Host app (`BucketeerTests`)

An XCTest bundle **without a test host**: it compiles the host sources
(everything in `Bucketeer/` except `App/BucketeerApp.swift`) and the
string catalog, so running it never launches Bucketeer.app.

```bash
xcodebuild -project Bucketeer.xcodeproj -scheme BucketeerTests \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
# one suite:  -only-testing:BucketeerTests/SyncEngineSchedulingTests
```

- `*RenderTests` render each screen and sheet in empty / populated /
  error states into an off-screen window that is never shown, check the
  key content with Vision OCR and write PNGs for a visual check.
- `AppContainer(configuration:)` with `.inMemory` stores, an in-memory
  Keychain (`InMemoryKeychain`) and object store (`InMemoryS3Browser`,
  shared with the Core tests) keeps tests away from real data, the
  Keychain and real accounts.
- The target is created by `scripts/add_test_target.rb`.

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

One shared scheme is committed:
`Bucketeer.xcodeproj/xcshareddata/xcschemes/Bucketeer.xcscheme`, so
`-scheme Bucketeer` is canonical. It builds the app, its Test action
runs `BucketeerTests`, and only its Debug Run action carries the
StoreKit configuration (section 8). Profile and Archive use Release
without it.

There's a leftover `S3 Browser.xcscheme_^#shared#^_` entry in
`xcuserdata/.../xcschememanagement.plist` from before the rename. No
actual scheme file backs it — ignore it.

---

## 6. App-Sandbox-aware testing tips

The App is sandboxed even in Debug. Practical implications when you
run from Xcode:

- **Account credentials** live in the shared access group of the
  data-protection keychain, which host and File Provider extension
  both read. That keychain needs a signed build with the shared group
  provisioned; unsigned builds get `errSecMissingEntitlement` (-34018)
  when saving an account. Credentials that earlier builds stored in
  the file-based login keychain are copied over at launch.
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

The paywall uses StoreKit 2 with two non-consumable IAP products, both
of which must exist in App Store Connect before TestFlight or
production builds will see them:

- `za.co.digitalfreedom.bucketeer.pro.lifetime` (paid, Family Sharing on)
- `za.co.digitalfreedom.bucketeer.pro.trial` (price Free, Family Sharing off)

Local testing uses `Bucketeer/Bucketeer.storekit`, which the shared
scheme's Debug Run action references (Edit Scheme → Run → Options →
StoreKit Configuration). Reset the local entitlement via Xcode → Debug →
StoreKit → Manage Transactions during runs.

The file mirrors App Store Connect: `internalID`s are the ASC IAP ids,
names and descriptions are the en-US / de-DE texts, the price is €14.99
on the German storefront. Two rules keep it working and out of the
release:

- Localization locales must be full identifiers (`en_US`, `de_DE`).
  With bare `en` / `de` the local StoreKit server returns zero
  products, and the paywall only shows "Buy Bucketeer Pro".
- The file is excluded from the app target's membership in
  `project.pbxproj` (exception of the synchronized `Bucketeer` folder),
  so it never lands in the app bundle. The test bundle keeps it.

`SheetRenderTests.testPaywallWithStoreKitProducts` renders the paywall
with these products off screen (also the source of the in-app purchase
review screenshot). storekitagent refuses an `SKTestSession` for the
`xctest` tool itself, so the test skips under `xcodebuild test` and
needs a runner process with its own bundle id.

The trial is not stored locally. It runs for 14 days from the trial
transaction's original purchase date (`ProAccessResolver` in Core). To
test it again, delete the trial transaction in Manage Transactions; to
test the expiry, change the transaction's purchase date there.

### App Store screenshot demo mode

Debug builds contain a demo mode for the App Store screenshots
(`Bucketeer/Services/ScreenshotDemo/`, compiled out of Release). It
switches on only when **both** hold: the bundle id is
`za.co.digitalfreedom.Bucketeer.qa` (a re-signed copy of the Debug
build with its own sandbox container) and the app is launched with
`-BucketeerScreenshotDemo YES`. It then uses in-memory stores and an
in-memory Keychain, runs no launch work, seeds the JSON file given by
`-BucketeerDemoSeed <path>` and opens the screen named by
`-BucketeerDemoScreen` (`01_browser` … `09_pro`, `paywall`) in a
1440 × 900 pt window on a Retina display, in light appearance.

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
| Per-phase changelog | `CHANGELOG.md` |
| File Provider manual setup | `PHASE_9_SETUP.md` |
| App Store metadata draft | `docs/APP_STORE_METADATA.md` |
| Composition root | `Bucketeer/Services/AppContainer.swift` |
| Sync engine | `Bucketeer/Services/Sync/SyncEngine.swift` |
| BucketeerCore public surface | `BucketeerCore/Sources/BucketeerCore/` |
| All legal docs | `Bucketeer/Resources/Legal/` |
| Contributing rules | `CONTRIBUTING.md` |
| Per-phase changelog | `CHANGELOG.md` |
