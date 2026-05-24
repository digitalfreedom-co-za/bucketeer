# App Store Metadata — Bucketeer v1.0

Drafts for App Store Connect. Update price and screenshots after the
first TestFlight cycle.

---

## Subtitle (30 chars max)

`Object storage at hand`

## Promotional text (170 chars max)

> Browse, transfer, mount and sync object storage across AWS S3,
> Azure Blob and seven more providers — all in one native macOS app.

## Description (4000 chars max)

> Bucketeer is the macOS app for everyone who lives in object storage.
> Browse buckets and containers across **AWS S3, Azure Blob Storage,
> Civo, Cloudflare R2, Backblaze B2, Wasabi, DigitalOcean Spaces, Storj
> and any S3-compatible endpoint** — all from one Finder-style window.
>
> **Native, fast, private.** Built entirely with Swift 6 and SwiftUI.
> Your credentials live in the macOS Keychain. No telemetry, no
> analytics, no third-party SDKs. The only network traffic Bucketeer
> creates is the object-storage traffic you configure.
>
> ### What you can do
>
> - **Three-pane Finder layout** with inline metadata and Quick Look
>   preview
> - **Drag and drop in every direction** — Finder ↔ Bucketeer, even
>   across accounts and providers
> - **Mount any bucket as a Finder drive** via the File Provider
>   extension *(Bucketeer Pro)*
> - **Background sync jobs** between any two locations, including
>   S3 ↔ Azure, with copy / move / mirror modes *(Bucketeer Pro)*
> - **Menubar mode** keeps mounts and sync alive when the main window
>   is closed *(Bucketeer Pro)*
> - **Multipart upload and download** with parallel parts and live
>   progress
> - **Touch ID / password gate** for revealing stored secrets
> - **Localised in 10 languages** — English, German, Spanish, French,
>   Italian, Japanese, Korean, Dutch, Polish, Brazilian Portuguese
>
> ### How pricing works
>
> Bucketeer is **free to evaluate for 14 days with every feature
> unlocked**. After the trial the core browser stays free; the Pro
> pillars (Mount as Drive, Sync Engine, cross-account copy, Menubar
> mode) unlock with a single **€14.99 one-time purchase** that covers
> Family Sharing. No subscription, no auto-renew, no future paid
> upgrades for v1.x.
>
> ### Built in public
>
> Bucketeer is source-available on GitHub
> (github.com/digitalfreedom-co-za/bucketeer). The single canonical
> binary ships exclusively through the Mac App Store. Read the License,
> EULA and Privacy Policy in-app via Bucketeer → About.

## Keywords (100 chars max — comma-separated, no spaces around commas)

`s3,azure,blob,object,storage,aws,civo,r2,backblaze,wasabi,spaces,storj,minio,sync,mount,finder`

## What's New (4000 chars max)

> Bucketeer v1.0 — the first public release.
>
> - Browse buckets and objects across AWS S3, Azure Blob, Civo,
>   Cloudflare R2, Backblaze B2, Wasabi, DigitalOcean Spaces, Storj
>   and any S3-compatible endpoint
> - Upload, download, delete, rename, create folders, with multipart
>   transfers and live progress
> - Inline Quick Look preview plus Spacebar full-window preview
> - Drag and drop between Finder and Bucketeer, plus intra-app and
>   cross-account drags
> - Mount any bucket as a Finder drive (Pro)
> - Background sync between any two locations across providers (Pro)
> - Menubar background mode (Pro)
> - 14-day Pro trial, then €14.99 one-time purchase for lifetime Pro

## Support URL

`https://support.apps.digitalfreedom.co.za/`

## Marketing URL

`https://digitalfreedom.co.za`

## Privacy policy URL

`https://github.com/digitalfreedom-co-za/bucketeer/blob/main/Bucketeer/Resources/Legal/PRIVACY_POLICY.md`

---

## App category

- **Primary**: Developer Tools
- **Secondary**: Utilities

## Age rating

4+

## Content rights

> Does the App use, access, collect, transmit, analyze, or share data
> about people, locations, or activities?

**No** — Bucketeer reads only the buckets the user authenticates to
and stores credentials in the macOS Keychain. No analytics, no
telemetry.

## Encryption

`ITSAppUsesNonExemptEncryption = false` in Info.plist (already set).
Bucketeer uses only platform-provided TLS / CryptoKit primitives that
qualify for the standard export-compliance exemption.

## In-App Purchases

| Field | Value |
|---|---|
| Reference name | Bucketeer Pro Lifetime |
| Product ID | `za.co.digitalfreedom.bucketeer.pro.lifetime` |
| Type | Non-Consumable |
| Cleared for sale | Yes |
| Price tier | Tier 15 (~€14.99) |
| Family Sharing | Enabled |

Promotion image: 1024×1024 px PNG with Bucketeer Pro badge.

---

## Screenshots

Required: 16:10 macOS screenshots, at least one per locale Apple
displays. Suggested set (1280×800 minimum):

1. Browser window with a populated bucket, inline Quick Look preview
   of a PDF in the detail pane
2. Add-account sheet showing the provider picker (highlight Azure
   among the nine presets)
3. Sync Jobs list with an active job mid-transfer
4. Settings → Pro tab with the price visible
5. Finder window showing a mounted bucket under Locations
6. Menubar popover with two transfers in flight

Capture on macOS 26 or current public release in light and dark mode.
Use a real account against a public-read bucket (or seed a personal
one) so the data looks plausible.

---

## v1.0 launch checklist

- [ ] App Store Connect: create app record with bundle id
      `za.co.digitalfreedom.Bucketeer`
- [ ] Upload Bucketeer Pro IAP (see table above)
- [ ] Add 10 InfoPlist.strings translations (already in repo)
- [ ] Add localised App Store descriptions (drafts above are en/de;
      es/fr/it/ja/ko/nl/pl/pt-BR translations follow same convention)
- [ ] Upload one screenshot set per locale
- [ ] Set up Xcode Cloud workflows per
      `~/Developer/projects/wiki/apple-native-apps.md`
- [ ] First push to `test` → verify TestFlight upload
- [ ] Promote `test` → `beta` for external testers
- [ ] Promote `beta` → `main` for production submission
