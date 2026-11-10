# App Store Metadata — Bucketeer v1.0

Drafts for App Store Connect. Update price and screenshots after the
first TestFlight cycle. The v1.0 marketing surface includes the 13.x
feature block (activity log, soft-delete trash, dashboard, versions
browser, metadata editor, auto-tagging, resumable transfers, deep
links + Shortcuts, Spotlight indexing, cross-account copy, client-
side encryption, hardware-key preview).

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
> analytics or tracking SDKs, and no Bucketeer server. Bucketeer
> connects directly to the object storage you configure, plus Apple's
> App Store (StoreKit) for the Bucketeer Pro trial, purchase and
> restore.
>
> ### What you can do
>
> - **Three-pane Finder layout** with inline metadata and Quick Look
>   preview
> - **Drag and drop in every direction** — Finder ↔ Bucketeer, even
>   across accounts and providers
> - **Mount buckets as Finder drives** via the File Provider
>   extension *(Bucketeer Pro)*. Buckets with client-side encryption
>   cannot be mounted in this version
> - **Background sync jobs** between any two locations, including
>   S3 ↔ Azure, with copy / move / mirror modes plus **watch
>   folders** that auto-upload on every change *(Bucketeer Pro)*
> - **Menubar mode** keeps mounts and sync alive when the main window
>   is closed *(Bucketeer Pro)*
> - **Resumable multipart upload and download** — interrupted ≥ 50 MB
>   uploads pick up where they left off after a crash or sleep
> - **Bandwidth throttle** with sensible presets so transfers don't
>   saturate your uplink during calls
> - **Client-side AES-256-GCM encryption per bucket** with keys in
>   your local Keychain. Encrypted uploads are transparently sealed
>   on the way out and unsealed on the way back in
> - **Soft-delete trash** with one-click restore from a local cache
>   you control (default cap 100 MB per object, 30-day retention)
> - **Bucket dashboard** with object count, total size, top-10
>   largest, and an honest monthly-cost estimate per provider
> - **Object version browser**, **metadata + tags editor**, and a
>   read-only **lifecycle / CORS / policy viewer** for the buckets
>   that expose them
> - **Auto-tagging rules** — glob + MIME matchers apply tags and
>   metadata automatically after every successful upload
> - **Activity log** of every operation, searchable, CSV-exportable
> - **`bucketeer://` deep links** plus **Spotlight indexing**
>   (opt-in) and four built-in **Shortcuts / Siri intents** — list
>   buckets, generate a presigned URL, upload a file, run a sync job
> - **Cross-account copy / move** between any two configured
>   accounts, server-side when endpoints match, local round-trip
>   otherwise — automatically picks the right path
> - **Touch ID / password gate** for revealing stored secrets;
>   YubiKey / smartcard support shipped as technical preview
> - **Localised in 20 locales** — English (US and UK), Czech, Danish,
>   Dutch, Finnish, French, German, Greek, Hungarian, Italian, Japanese,
>   Korean, Norwegian, Polish, Portuguese (Brazil and Portugal), Russian,
>   Spanish, Swedish
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

## Support period (draft)

Status: draft for planned first placement. Marcello confirmed
2026-11-09 Europe/Rome that v1.0 is planned for November 2026 (not
yet live). Five-year floor: at least November 2031. Once the listing
is live, replace "planned" with the verified release month and year
in this listing, in the About window and in
`docs/SUPPORT_AND_UPDATE.md`. Baseline: legal
`shared/SUPPORT_AND_UPDATE_POLICY.en.md` version 2.0.0, EULA section 9.

Proposed copy for the end of the Description:

> ### Support period
>
> Bucketeer v1.0 receives security and conformity updates until at
> least November 2031, five years from the planned first market
> placement in November 2026. The support period covers security
> fixes and the fixes needed to keep the app working as described. It
> does not promise new features, support for macOS versions Apple no
> longer supports, or that the app stays on sale. Details in the
> EULA, section 9.

Do not upload this block until the November 2026 placement is live
and the month has been verified against the App Store release date.

## Keywords (100 chars max — comma-separated, no spaces around commas)

`s3,azure,blob,object,storage,aws,r2,backblaze,wasabi,minio,sync,mount,finder,encrypt,shortcuts`

## What's New (4000 chars max)

> Bucketeer v1.0 — the first public release.
>
> - Browse buckets and objects across AWS S3, Azure Blob, Civo,
>   Cloudflare R2, Backblaze B2, Wasabi, DigitalOcean Spaces, Storj
>   and any S3-compatible endpoint
> - Upload, download, delete, rename, create folders, with multipart
>   transfers and live progress
> - Resumable uploads for files ≥ 50 MB — interruptions cost a single
>   in-flight part on the next launch
> - Inline Quick Look preview plus Spacebar full-window preview
> - Drag and drop between Finder and Bucketeer, plus intra-app and
>   cross-account drags
> - Mount buckets as Finder drives (Pro); buckets with client-side
>   encryption cannot be mounted in this version
> - Background sync between any two locations across providers (Pro),
>   plus watch folders that auto-upload on every change
> - Client-side AES-256-GCM encryption per bucket — keys live in
>   your Keychain only, never in the cloud
> - Soft-delete trash with one-click restore from a local cache
> - Bucket dashboard, version browser, metadata + tags editor,
>   lifecycle / CORS / policy viewer
> - Auto-tagging rules (glob + MIME) applied after every upload
> - Activity log with CSV export, opt-in Spotlight indexing,
>   `bucketeer://` deep links, Shortcuts + Siri intents
> - Cross-account copy / move with automatic server-side or round-
>   trip path selection
> - Bandwidth throttle, menubar background mode (Pro)
> - 14-day Pro trial, then €14.99 one-time purchase for lifetime Pro
>   — Family Sharing included

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
telemetry. The host-only activity log, soft-delete trash, encryption
keys, resumable-upload checkpoints, and auto-tag rules all live on
the user's Mac and are never transmitted to the Publisher.

## Encryption

`ITSAppUsesNonExemptEncryption = NO` in Info.plist. Bucketeer v1.0 is
not offered in France (deselect France under Pricing and
Availability), so no ANSSI declaration is needed and, per Apple's
documentation, the app is exempt from providing documentation; App
Store Connect does not ask the questionnaire per build. US
classification of the client-side AES-256-GCM encryption (Phase
13.15): ECCN 5D992.c mass market, self-classified under 15 CFR
§740.17(b)(1), no CCATS, no annual report for an end-user app
(86 FR 16482). Provider and exporter: DigitalFreedom Global LLC.
Full reasoning and the steps for adding France later:
`docs/EXPORT_COMPLIANCE.md`.

France is one of five deselected markets. The full availability
matrix, with Mainland China, Egypt, Saudi Arabia and Russia from the
legal baseline, is in `docs/AVAILABILITY.md`; the pre-submission check
is in `docs/RELEASE_v1.0.md` section 2.

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
3. Sync Jobs list with one active job mid-transfer and one watch
   folder (eye icon in the row)
4. Bucket Dashboard sheet with stats grid + cost estimate + largest
   objects list visible
5. Activity Log window with rows for upload, delete, sync run,
   encryption apply
6. Settings → Encryption tab with one or two registered BYOK keys
   visible
7. Settings → Pro tab with the price visible
8. Finder window showing a mounted bucket under Locations
9. Menubar popover with two transfers in flight and the Activity
   Log shortcut visible

Capture on macOS 26 or current public release in light and dark mode.
Use a real account against a public-read bucket (or seed a personal
one) so the data looks plausible.

---

## v1.0 launch checklist

- [ ] App Store Connect: create app record with bundle id
      `za.co.digitalfreedom.Bucketeer`
- [ ] Upload Bucketeer Pro IAP (see table above)
- [ ] Add 20 InfoPlist.strings translations (already in repo)
- [ ] Add localised App Store descriptions (drafts above are en/de;
      the other 18 store locales follow the same convention)
- [ ] Upload one screenshot set per locale
- [ ] Fill in the support period end month and year from the verified
      release date (see "Support period (draft)" above and
      `docs/SUPPORT_AND_UPDATE.md`)
- [ ] **Xcode manual step**: register `CFBundleURLTypes` for the
      `bucketeer://` scheme (see `docs/DEEP_LINKS.md` §
      "Mac App Store packaging requirement")
- [ ] **Xcode manual step**: add the File Provider Extension target
      (see `PHASE_9_SETUP.md`)
- [ ] Set up Xcode Cloud workflows per
      `~/Developer/projects/wiki/apple-native-apps.md`
- [ ] First push to `test` → verify TestFlight upload
- [ ] Promote `test` → `beta` for external testers
- [ ] Promote `beta` → `main` for production submission

---

## ASO draft recommendations (not live)

Research from ticket #2, captured 2026-11-09. Nothing in this section
has been written to App Store Connect. Evidence, metric sources and
open questions: [`ASO_KEYWORD_RESEARCH.md`](ASO_KEYWORD_RESEARCH.md).

App Store Connect already holds draft name, subtitle, keywords,
promotional text and description for all 20 store locales (version
1.0, `PREPARE_FOR_SUBMISSION`, not public). Those drafts differ from
the Subtitle and Keywords sections above; ASC is the copy that would
ship.

Proposed en-US drafts, pending approval:

| Field | Draft | Length |
|---|---|---|
| Name | `Bucketeer: S3 & Azure Storage` | 29 of 30 |
| Subtitle | `Browse, sync & mount buckets` | 28 of 30 |
| Keywords (approved direction) | `aws,cloud,object,blob,r2,b2,backblaze,wasabi,minio,upload,transfer,client,drive,encryption,backup` | 97 of 100 bytes |

Marcello 2026-11-09 Europe/Rome: include everything (provider names
and generic terms, including `backup`). Still draft only; no App Store
Connect write. Drop `s3` and `azure` from the keyword field where the
name already carries them. German drafts and other locales: research
document, same direction.
