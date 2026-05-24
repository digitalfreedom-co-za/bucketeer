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
| `sync` | `/<jobUUID>` | Open the main window (sync drill-down lands in v1.1) |
| `activity` | *(empty)* | Open the Activity Log window |
| `trash` | *(empty)* | Open the Trash window |

Example:

```
bucketeer://object/11111111-2222-3333-4444-555555555555/photos/2026/05/img.jpg
```

`BucketeerDeepLink.url` builds these for you from `BucketeerCore`;
the canonical Swift API is `BucketeerDeepLink(url: URL)`.

## Mac App Store packaging requirement

For `open bucketeer://…` from another app (Safari, Mail, Notes,
Terminal, …) to launch Bucketeer or focus it when it's already
running, the scheme **must be registered** in the App's Info.plist:

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

The project currently uses `GENERATE_INFOPLIST_FILE = YES`, so
this is a **manual Xcode step** before the next App Store build:

1. Open the Bucketeer target in Xcode.
2. **Info** tab → **URL Types** section → **+** button.
3. Identifier: `za.co.digitalfreedom.bucketeer.deeplink`
4. URL Schemes: `bucketeer`
5. Role: **Viewer**
6. Build once → Xcode writes the keys above into the generated
   Info.plist for you.

Without this step, deep links still work **inside a running
Bucketeer process** because `DeepLinkRouter` installs an
`NSAppleEventManager` handler at startup. Cold-launch from
`open` / Safari / Mail will silently no-op until the keys land
in Info.plist.

## Verifying the handler

After the app has launched once with the URL types registered:

```bash
open "bucketeer://activity"
open "bucketeer://bucket/<accountUUID>/<bucket>"
```

Should focus the App and route to the named destination.
