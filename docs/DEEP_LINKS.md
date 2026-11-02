# `bucketeer://` deep links

Phase 13.11 introduces a system-wide URL scheme so other apps,
Shortcuts (Phase 13.12), and Spotlight (Phase 13.13) can route the
user directly into a bucket, an object's folder, or one of the
inspector windows.

## Grammar

| Host | Path | Effect |
|---|---|---|
| `account` | `/<accountUUID>` | Open the main window, focus the account's bucket list |
| `bucket` | `/<accountUUID>/<bucket>[/<prefix>…]` | Focus the bucket at the given prefix |
| `object` | `/<accountUUID>/<bucket>/<key…>` | Focus the bucket and navigate to the object's folder |
| `sync` | `/<jobUUID>` | Open the dedicated sync-job detail window |
| `activity` | *(empty)* | Open the Activity Log window |
| `trash` | *(empty)* | Open the Trash window |

Example:

```
bucketeer://object/11111111-2222-3333-4444-555555555555/photos/2026/05/img.jpg
```

`BucketeerDeepLink.url` builds these for you from `BucketeerCore`;
the canonical Swift API is `BucketeerDeepLink(url: URL)`.

## Registration

The scheme is registered system-wide via `Bucketeer/Info.plist`:

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLName</key>
    <string>za.co.digitalfreedom.bucketeer.deeplink</string>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>bucketeer</string>
    </array>
    <key>CFBundleTypeRole</key>
    <string>Viewer</string>
  </dict>
</array>
```

The project keeps `GENERATE_INFOPLIST_FILE = YES` alongside
`INFOPLIST_FILE = Bucketeer/Info.plist` — Xcode merges the file
keys, the `INFOPLIST_KEY_*` build settings, and the auto-generated
version stamps into the final Info.plist.

## Verifying the handler

After Bucketeer has launched once on the user's Mac (Launch Services
indexes the URL scheme at install time):

```bash
open "bucketeer://activity"
open "bucketeer://bucket/<accountUUID>/<bucket>"
```

Should focus the App and route to the named destination.

`DeepLinkRouter` additionally installs an `NSAppleEventManager`
handler at startup so URLs that arrive while the App is in
menu-bar (`.accessory`) mode still route — the handler is the
in-process fallback to the system-wide registration.

## Sync-job detail window

`bucketeer://sync/<jobUUID>` opens `SyncJobDetailWindow` (a
SwiftUI `WindowGroup(id: "sync-job", for: UUID.self)`). The window
shows identity (name, mode, schedule, enabled flag), the two
endpoints with friendly account names, live phase + progress, and
a Run Now / Cancel / Open-in-List action row.

Status comes from `SyncStatusBroker` — a `@MainActor @Observable`
multicast wrapper around `SyncEngine.statuses`. Both the sync
list view model and the detail window read from the broker, so
they don't race the single AsyncStream iterator. The detail
window reloads its `SyncJob` snapshot from the store on terminal
phase transitions (`finished` / `failed` / `cancelled`) so
`lastRunAt` and `lastRunSummary` refresh when the in-flight run
completes.
