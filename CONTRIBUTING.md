# Contributing to Bucketeer

Thanks for taking the time to look. Bucketeer is **source-available,
not OSI-open-source**: the canonical binary ships on the Mac App
Store under the Publisher's name. Contributions are welcome and merge
under the same Source-Available License (see `Bucketeer/Resources/Legal/LICENSE.md`)
— by sending a PR you agree to that licensing.

---

## 1. Issues vs Pull Requests

| Kind | Where |
|---|---|
| Bug report or feature request | <https://support.apps.digitalfreedom.co.za/> |
| Code contribution | GitHub Pull Request against the `development` branch |
| Security disclosure | `data-protection@digitalfreedom.co.za` (private; please don't open a public issue) |

GitHub Issues on this repo are **not** the support channel — use the
support site for that. The repo issue tracker is for development
coordination (`development → test → beta → main` branch chain).

---

## 2. Branch model

```
development → test → beta → main
```

- `development` is the integration branch. Open every PR against it.
- `test` triggers the Xcode Cloud TestFlight-internal build.
- `beta` triggers the TestFlight-external build.
- `main` triggers the App Store submission build.

Promote with fast-forward merges (no squash, no rebase) so the
commit history stays linear across the chain.

---

## 3. Local setup

See `docs/DEVELOPER_SETUP.md`. Two-line summary:

```bash
xcodebuild build -project Bucketeer.xcodeproj -scheme Bucketeer \
  -configuration Debug -destination 'generic/platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
( cd BucketeerCore && swift test )    # 84 tests, ~25 ms
```

---

## 4. Standards we hold ourselves to

Three rules apply to every change:

1. **No dead code.** Don't add helpers without a call site. Remove
   stale comments referencing removed paths. Strip unused imports
   (especially `import BucketeerCore` in host files that don't touch
   Core symbols).
2. **Apple guidelines.** Follow Swift API Design Guidelines, App Store
   Review Guidelines, the macOS HIG, and the framework-specific
   contracts (NSFileProviderReplicatedExtension capabilities /
   itemVersion, StoreKit 2 transaction lifecycle, Privacy Manifest
   reason codes, App Sandbox minimalism).
3. **Production-ready.** No TODO stubs, no `try?` swallowing
   meaningful errors, no `_ = …` discards of error returns. Surface
   failures through the existing error sinks (`@Observable lastError`,
   `BucketeerError`).

PRs that introduce dead code, swallow errors, or skip Apple
contracts get review feedback before merge.

---

## 5. Architecture overview

Read `docs/ARCHITECTURE.md` once before opening a PR that touches more
than one file. The Mermaid diagrams there are the canonical map of
how `BucketeerCore`, the host app, and the (manually-wired) File
Provider extension fit together.

Key seams:

- **`BucketeerCore`** holds shared models + storage + S3/Azure
  services + sync planner + trial logic. Pure-logic extraction is
  the preferred way to make host code testable (`SyncPlanner`,
  `TrialBookkeeping` are the pattern).
- **Host** holds composition (`AppContainer`), ViewModels, SwiftUI,
  StoreKit (`EntitlementManager`), File Provider host
  (`MountController`), DragDrop coordinator, TransferManager queue,
  SyncEngine.
- **File Provider extension** is a separate target you add manually
  per `PHASE_9_SETUP.md`; the code lives in `Bucketeer File Provider/`
  and uses the same `BucketeerCore` services as the host.

---

## 6. Coding conventions

- **Swift 6 strict concurrency** is on. Don't suppress sendability
  diagnostics with `@unchecked Sendable` unless there's a clear note
  explaining the invariants.
- **Existentials**: use `any P` everywhere a protocol is used as a
  type (not the bare `P` form). Codex review #1 enforced this across
  the codebase.
- **Public surface**: in `BucketeerCore`, prefer `internal` unless a
  type is actually consumed by the host or the extension. The bulk-
  `public` script that ran during the Core extraction over-exposed a
  lot of types; subsequent passes tightened them. If in doubt, leave
  it `internal`.
- **Comments**: explain *why*, not *what*. The "why" line in our
  comments usually points at the bug, race, or design constraint
  that the code mitigates (e.g. "Codex blocker #3 — load+save race").
- **Localised strings**: every user-facing string goes through
  `Localizable.xcstrings` with all 10 standard languages. No
  hard-coded English strings in views or view models.
- **German UI never genders.** Use the generic masculine. Same rule
  mirrors to other locales where they have a similar choice.

---

## 7. Testing

- Pure logic goes into `BucketeerCore` and gets a Swift Testing test
  in `BucketeerCore/Tests/BucketeerCoreTests/`.
- UI behaviour gets a manual smoke test in the description of your PR
  ("opened the menubar popover, verified the badge", etc.).
- For host-only async logic that's hard to unit-test today, extract
  the pure core into a helper inside `BucketeerCore` (like we did
  with `SyncPlanner` and `TrialBookkeeping`).

---

## 8. Commit messages

Conventional Commits style:

```
feat(scope): short summary
fix(scope): short summary
refactor(scope): short summary
test(scope): short summary
docs(scope): short summary
chore: short summary
```

Body wraps at 72 cols. Reference the design spec phase, Codex finding
number, or issue ID where it helps a future reader. Co-author
trailers and AI references are intentionally absent (`Marcel R. G.
Berger` is the only author).

---

## 9. Code review expectations

- **One reviewer** is required (the Publisher). For substantive
  changes, the workflow runs **two passes of `codex exec` review**
  before the human review, and any blocker/high finding is fixed
  before merge.
- Style nits get fixed inline, not blocked on.

---

## 10. License

By contributing you agree that your contribution is licensed to the
Publisher (Berger & Rosenstock GbR, trading as DigitalFreedom) under
the [Source-Available License](Bucketeer/Resources/Legal/LICENSE.md).
The canonical binary ships exclusively on the Mac App Store. There is
no CLA beyond what this paragraph and the License together establish.

---

## 11. Contact

For anything you'd rather not file publicly:

- Code / architecture questions → open a PR draft and tag the
  Publisher for an early read.
- Private contact → hello@digitalfreedom.co.za
- Privacy / security disclosure → data-protection@digitalfreedom.co.za
