# App Store Metadata — Bucketeer v1.0

Drafts for App Store Connect. Update price and screenshots after the
first TestFlight cycle. The v1.0 marketing surface includes the 13.x
feature block (activity log, soft-delete trash, dashboard, versions
browser, metadata editor, auto-tagging, resumable uploads, deep
links + Shortcuts, Spotlight indexing, cross-account copy, client-
side encryption). Hardware-key unlock is deferred to v1.1.

This file is the single source for all store descriptions (Marcello,
2026-11-22 11:04 Europe/Rome, decision log #14). The Name, Subtitle
and Keywords below are the adopted v1.0 source texts for en-US (en-GB
uses the same copy) as of 2026-11-22. They are not live: nothing has
been written to App Store Connect, which still holds the older drafts
until the write on ticket #22. Per-locale values for all 21 store
locales: "Store locales (21)" below.

---

## Name (30 chars max)

`Bucketeer: S3 & Azure Storage` (29 of 30)

## Subtitle (30 chars max)

`Browse, sync & mount buckets` (28 of 30)

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
> - **Resumable multipart uploads** (S3-compatible providers,
>   unencrypted buckets) — interrupted uploads of 50 MB or more
>   continue from the last completed part when the same file is added
>   to the same folder again
> - **Bandwidth throttle** with sensible presets so transfers don't
>   saturate your uplink during calls
> - **Client-side AES-256-GCM encryption per bucket** with keys in
>   your local Keychain, optionally exportable as a passphrase-protected
>   backup. Encrypted uploads are transparently sealed
>   on the way out and unsealed on the way back in. File contents are
>   encrypted; object names, paths and sizes are not
> - **Soft-delete trash** with one-click restore from a local cache
>   you control (default cap 100 MiB per object, 30-day retention)
> - **Bucket dashboard** with object count, total size, top-10
>   largest, and an honest monthly-cost estimate for known providers
>   (none for custom endpoints)
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
> - **Touch ID / password gate** for revealing stored secrets
> - **Localised in 21 locales** — English (US and UK), Czech, Danish,
>   Dutch, Finnish, French, German, Greek, Hungarian, Italian, Japanese,
>   Korean, Norwegian, Polish, Portuguese (Brazil and Portugal), Russian,
>   Spanish, Swedish, Turkish
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

## Keywords (100 bytes max — comma-separated, no spaces around commas)

`aws,cloud,object,blob,r2,b2,backblaze,wasabi,minio,upload,transfer,client,drive,encryption,backup`
(97 of 100 bytes)

Adopted en-US (and en-GB) source text as of 2026-11-22, not live in
App Store Connect. `s3`, `azure` and `storage` are left out because
the name already carries them.

## What's New (4000 chars max)

> Bucketeer v1.0 — the first public release.
>
> - Browse buckets and objects across AWS S3, Azure Blob, Civo,
>   Cloudflare R2, Backblaze B2, Wasabi, DigitalOcean Spaces, Storj
>   and any S3-compatible endpoint
> - Upload, download, delete, rename, create folders, with multipart
>   transfers and live progress
> - Resumable uploads for files ≥ 50 MB (S3-compatible providers,
>   unencrypted buckets) — add the same file to the same folder again
>   to continue from the last completed part
> - Inline Quick Look preview plus Spacebar full-window preview
> - Drag and drop between Finder and Bucketeer, plus intra-app and
>   cross-account drags
> - Mount buckets as Finder drives (Pro); buckets with client-side
>   encryption cannot be mounted in this version
> - Background sync between any two locations across providers (Pro),
>   plus watch folders that auto-upload on every change
> - Client-side AES-256-GCM encryption per bucket — keys live in
>   your Keychain and can optionally be exported as a
>   passphrase-protected backup. File contents are encrypted; object
>   names, paths and sizes are not
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
> - Privacy Policy updated to version 1.0.3
> - End User License Agreement updated to version 1.0.1

## Support URL

`https://support.apps.digitalfreedom.co.za/`

## Marketing URL

`https://digitalfreedom.co.za`

## Privacy policy URL

`https://github.com/digitalfreedom-co-za/bucketeer/blob/main/Bucketeer/Resources/Legal/PRIVACY_POLICY.md`

---

## Store locales (21)

Source texts per App Store locale as of 2026-11-22. All 21 locales
match the app UI. Turkish (tr) was added on 2026-11-22 as a store
locale (decision log #14); the app UI gained Turkish in #72
(`tr.lproj`, Turkish strings in every string catalog, Turkish in-app
help).
Nothing in this table has been written to App Store Connect; the
write is ticket #22. App Store Connect holds no tr localization yet.

Limits: name and subtitle 30 characters, keywords 100 bytes (UTF-8),
promotional text 170 characters, description 4000 characters.
Lengths below were checked with a script on 2026-11-22.

### Adopted or drafted in this file

| Locale | Name | Subtitle | Keywords | Promotional text and description | Status |
|---|---|---|---|---|---|
| en-US | `Bucketeer: S3 & Azure Storage` (29) | `Browse, sync & mount buckets` (28) | `aws,cloud,object,blob,r2,b2,backblaze,wasabi,minio,upload,transfer,client,drive,encryption,backup` (97 bytes) | English sections above | adopted 2026-11-22 |
| en-GB | `Bucketeer: S3 & Azure Storage` (29) | `Browse, sync & mount buckets` (28) | `aws,cloud,object,blob,r2,b2,backblaze,wasabi,minio,upload,transfer,client,drive,encryption,backup` (97 bytes) | English sections above | adopted 2026-11-22, same copy as en-US |
| de-DE | `Bucketeer: S3 & Azure Speicher` (30) | `Sync & Mount für Buckets` (24) | `aws,cloud,sync,blob,object,r2,b2,backblaze,wasabi,upload,laufwerk,datei,backup,verschlüsselung` (95 bytes) | not yet in this file; ASC draft only | name, subtitle, keywords adopted 2026-11-22; German promotional text and description still to be brought into this file |
| tr | `Bucketeer: S3 & Azure Depolama` (30) | `Bucket'ları gez, eşitle, bağla` (30) | `aws,bulut,nesne,blob,r2,b2,backblaze,wasabi,yükleme,aktarım,dosya,sürücü,şifreleme,yedekleme` (98 bytes) | "Turkish (tr) source texts" below | new locale, draft 2026-11-22; native Turkish proofread before #22 |

Open point for de-DE: the adopted keyword field contains `sync`,
which the adopted subtitle `Sync & Mount für Buckets` already
carries. Apple's search guidance advises against repeating subtitle
words; dropping `sync` would free 5 bytes. Left as adopted pending a
decision before #22.

### Waiting on a native pass

ASO research section 7.3 proposes no name, subtitle or keyword
rewrite for these 17 locales: no storefront measurements exist and
the en-US drafts must not be translated word by word. The adopted
method:

1. Zero-risk keyword fix: drop `s3`, `azure` and, where the subtitle
   contains it, `blob` from the current ASC keyword field. Fill the
   freed bytes with a locale-native generic term chosen by a native
   speaker. The current per-locale keyword strings are recorded only
   in App Store Connect, not in the repo (lengths in
   `ASO_KEYWORD_RESEARCH.md` section 4.2); bring each string into this
   file before the #22 write.
2. Name: en-US changes from `Bucketeer – Object Storage` to
   `Bucketeer: S3 & Azure Storage`. Each locale still needs a native
   decision: keep English `Storage` or use the local word, as de-DE
   uses `Speicher`. If the name carries `S3 & Azure`, the current
   subtitles below repeat both words and should be rewritten in the
   same pass.
3. Measure the storefront in Astro before rewriting subtitle and
   keywords, then have a native speaker write the copy.

Promotional text and description for these locales exist only as ASC
drafts. Under decision #14 this file is their source, so they must be
copied here and reviewed before #22 writes them.

| Locale | Name | Subtitle (current draft, not yet rewritten) | Keywords: zero-risk fix | Status |
|---|---|---|---|---|
| cs | native decision pending | `Prohlížeč souborů S3 a Azure` | current ASC string minus `s3`, `azure` | native pass required before #22 |
| da | native decision pending | `Filbrowser til S3 og Azure` | current ASC string minus `s3`, `azure` | native pass required before #22 |
| el | native decision pending | `Περιήγηση αρχείων S3 και Azure` | current ASC string minus `s3`, `azure` | native pass required before #22 |
| es-ES | native decision pending | `Explorador de S3 y Azure Blob` | current ASC string minus `s3`, `azure`, `blob` | native pass required before #22 |
| fi | native decision pending | `Tiedostoselain: S3 ja Azure` | current ASC string minus `s3`, `azure` | native pass required before #22 |
| fr-FR | native decision pending | `Navigateur S3 et Azure Blob` | current ASC string minus `s3`, `azure`, `blob` | native pass required before #22 |
| hu | native decision pending | `Fájlböngésző: S3 és Azure` | current ASC string minus `s3`, `azure` | native pass required before #22 |
| it | native decision pending | `File browser per S3 e Azure` | current ASC string minus `s3`, `azure` | native pass required before #22 |
| ja | native decision pending | `S3とAzure Blobのファイルブラウザ` | current ASC string minus `s3`, `azure`, `blob` | native pass required before #22 |
| ko | native decision pending | `S3 및 Azure Blob 파일 브라우저` | current ASC string minus `s3`, `azure`, `blob` | native pass required before #22 |
| nl-NL | native decision pending | `Bestandsbrowser: S3 en Azure` | current ASC string minus `s3`, `azure` | native pass required before #22 |
| no | native decision pending | `Filleser for S3 og Azure Blob` | current ASC string minus `s3`, `azure`, `blob` | native pass required before #22 |
| pl | native decision pending | `Przeglądarka plików S3 i Azure` | current ASC string minus `s3`, `azure` | native pass required before #22 |
| pt-BR | native decision pending | `Navegador para S3 e Azure Blob` | current ASC string minus `s3`, `azure`, `blob` | native pass required before #22 |
| pt-PT | native decision pending | `Navegador para S3 e Azure Blob` | current ASC string minus `s3`, `azure`, `blob` | native pass required before #22 |
| ru | native decision pending | `Файловый браузер S3 и Azure` | current ASC string minus `s3`, `azure` | native pass required before #22 |
| sv | native decision pending | `Filbläddrare för S3 och Azure` | current ASC string minus `s3`, `azure` | native pass required before #22 |

Subtitles are the ASC drafts read on 2026-11-09
(`ASO_KEYWORD_RESEARCH.md` section 4.2). The current ASC name in
every locale is `Bucketeer – Object Storage`.

## Turkish (tr) source texts

Draft 2026-11-22, written in Turkish from the English texts above,
same facts, informal "sen" address as in Apple's Turkish marketing.
No Astro measurement exists for the Turkish storefront; keyword
choice is expert judgment following the adopted en-US direction.
Needs a native Turkish proofread before the #22 write.

Name, 30 of 30 characters:

`Bucketeer: S3 & Azure Depolama`

Subtitle, 30 of 30 characters:

`Bucket'ları gez, eşitle, bağla`

Keywords, 98 of 100 bytes (no word from the name, subtitle or the
category names):

`aws,bulut,nesne,blob,r2,b2,backblaze,wasabi,yükleme,aktarım,dosya,sürücü,şifreleme,yedekleme`

Promotional text, 151 of 170 characters:

> AWS S3, Azure Blob ve yedi sağlayıcı daha için nesne depolamada gez,
> dosya aktar, bucket'ları bağla ve eşitle. Hepsi tek bir yerel macOS
> uygulamasında.

Description, 3887 of 4000 characters as plain text, counted with
the line wraps and indentation as written. With the markdown emphasis
kept, the same count is 4011 and over the limit, so paste the plain
text:

> Bucketeer, nesne depolamayla çalışan herkes için bir macOS
> uygulamasıdır. **AWS S3, Azure Blob Storage, Civo, Cloudflare
> R2, Backblaze B2, Wasabi, DigitalOcean Spaces, Storj ve S3 uyumlu her
> uç noktadaki** bucket ve container'larında tek Finder tarzı
> pencereden gez.
>
> **Yerel, hızlı, gizliliğe saygılı.** Tamamen Swift 6 ve SwiftUI ile
> geliştirildi. Kimlik bilgilerin macOS Anahtar Zinciri'nde saklanır.
> Telemetri yok, analiz veya izleme SDK'sı yok, Bucketeer sunucusu yok.
> Bucketeer doğrudan yapılandırdığın nesne depolamaya ve Pro denemesi,
> satın alma ve geri yükleme için App Store'a (StoreKit) bağlanır.
>
> ### Neler yapabilirsin
>
> - **Üç bölmeli Finder düzeni**, satır içi meta veri ve Hızlı Bakış
>   önizlemesi
> - **Her yöne sürükle bırak**: Finder ile Bucketeer arasında, hesap ve
>   sağlayıcılar arasında bile
> - **Bucket'ları Finder'da sürücü olarak bağla**: File Provider
>   uzantısıyla *(Bucketeer Pro)*. İstemci tarafında şifrelenen
>   bucket'lar bu sürümde bağlanamaz
> - **Arka planda eşitleme işleri**: S3 ile Azure dahil iki konum
>   arasında kopyalama, taşıma ve aynalama; ayrıca her değişiklikte
>   otomatik yükleme yapan **izlenen klasörler** *(Bucketeer Pro)*
> - **Menü çubuğu modu**: ana pencere kapalıyken de bağlı sürücüler ve
>   eşitleme sürer *(Bucketeer Pro)*
> - **Kaldığı yerden devam eden çok parçalı yüklemeler** (S3 uyumlu
>   sağlayıcılar, şifrelenmemiş bucket'lar): yarıda kalan 50 MB ve
>   üzeri yüklemeler, aynı dosyayı aynı klasöre yeniden eklersen son
>   tamamlanan parçadan sürer
> - **Bant genişliği sınırı**: hazır ön ayarlarla aktarımlar görüşme
>   sırasında hattını tıkamaz
> - **Bucket başına istemci tarafı AES-256-GCM şifreleme**: anahtarlar
>   yerel Anahtar Zinciri'nde durur, istersen parolalı bir yedek olarak
>   dışa aktarılır. Şifreli yüklemeler giderken şeffafça mühürlenir,
>   gelirken açılır. Dosya içerikleri şifrelenir; nesne
>   adları, yollar ve boyutlar şifrelenmez
> - **Geri alınabilir silme (çöp sepeti)**: kontrolü sende olan yerel
>   önbellekten tek tıkla geri yükleme (varsayılan sınır nesne
>   başına 100 MiB, 30 gün saklama)
> - **Bucket panosu**: nesne sayısı, toplam boyut, en büyük 10 nesne ve
>   bilinen sağlayıcılar için dürüst aylık maliyet tahmini (özel uç
>   noktalar için yok)
> - **Nesne sürümü tarayıcısı**, **meta veri ve etiket düzenleyicisi**
>   ve destekleyen bucket'lar için salt okunur **yaşam döngüsü / CORS
>   / politika görüntüleyicisi**
> - **Otomatik etiketleme kuralları**: glob ve MIME eşleştiricileri her
>   başarılı yüklemeden sonra etiket ve meta verileri otomatik uygular
> - **Etkinlik günlüğü**: her işlem kayıtlı, aranabilir, CSV olarak
>   dışa aktarılabilir
> - **`bucketeer://` derin bağlantıları**, **Spotlight dizinleme**
>   (isteğe bağlı) ve dört yerleşik **Kestirmeler / Siri eylemi**:
>   bucket'ları listele, önceden imzalanmış URL oluştur, dosya yükle,
>   eşitleme işi çalıştır
> - **Hesaplar arası kopyalama / taşıma**: yapılandırılmış iki hesap
>   arasında; uç noktalar eşleşirse sunucu tarafında, değilse yerel
>   gidiş-dönüşle; doğru yol otomatik seçilir
> - **Touch ID / parola koruması**: kayıtlı gizli bilgileri göstermek
>   için
> - **Uygulama 21 dilde yerelleştirildi**: İngilizce (ABD ve
>   İngiltere), Çekçe, Danca, Felemenkçe, Fince, Fransızca, Almanca,
>   Yunanca, Macarca, İtalyanca, Japonca, Korece, Norveççe, Lehçe,
>   Portekizce (Brezilya ve Portekiz), Rusça, İspanyolca, İsveççe,
>   Türkçe.
>
> ### Fiyatlandırma
>
> Bucketeer'ı **14 gün ücretsiz, tüm özellikler açık olarak dene**.
> Denemeden sonra temel tarayıcı ücretsiz kalır; Pro özellikleri
> (sürücü olarak bağlama, eşitleme motoru, hesaplar arası kopyalama,
> menü çubuğu modu) Aile Paylaşımı'nı da kapsayan **14,99 € tutarında
> tek seferlik bir satın almayla** açılır. Abonelik yok,
> otomatik yenileme yok, v1.x için ileride ücretli yükseltme yok.
>
> ### Herkese açık geliştirme
>
> Bucketeer'ın kaynak kodu GitHub'da incelenebilir
> (github.com/digitalfreedom-co-za/bucketeer). Tek resmi derleme
> yalnızca Mac App Store'da dağıtılır. Lisansı, EULA'yı ve Gizlilik
> Politikası'nı uygulamadaki Hakkında penceresinde oku.

Notes for review:

- The UI-language bullet ("Uygulama 21 dilde yerelleştirildi") lists
  the 21 app UI locales including Turkish, matching the English
  "Localised in 21 locales" bullet. The app UI is Turkish since #72.
- The price mirrors the English `€14.99`. The Turkish storefront shows
  the local price of the Tier 15 IAP.
- What's New and the "Support period" block are not drafted in
  Turkish. The support period block stays on hold as described above.

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

| Field | Value |
|---|---|
| Reference name | Bucketeer Pro 14-day Trial |
| Product ID | `za.co.digitalfreedom.bucketeer.pro.trial` |
| Type | Non-Consumable |
| Price tier | Free |
| Family Sharing | Disabled |

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
- [ ] Upload both Bucketeer Pro IAPs (see tables above)
- [ ] Add 21 InfoPlist.strings translations (already in repo, one per
      app UI locale, including Turkish)
- [ ] Add localised App Store metadata for all 21 store locales from
      "Store locales (21)" above, including the new tr localization.
      en-US, en-GB and de-DE name, subtitle and keywords are adopted;
      tr is drafted here; of the other 19 locales after en-US and
      de-DE, the 17 besides en-GB and tr still need a native pass and
      their descriptions brought into this file (ticket #22)
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

## ASO decision (adopted, not live)

Research from ticket #2, captured 2026-11-09. Evidence, metric
sources and open questions:
[`ASO_KEYWORD_RESEARCH.md`](ASO_KEYWORD_RESEARCH.md).

Marcello adopted the name, subtitle and keywords proposal on
2026-11-22 11:04 Europe/Rome (decision log #14), added Turkish (tr)
as a 21st store locale, and made this file the single source for all
store descriptions. The adopted texts are the Name, Subtitle and
Keywords sections at the top and the per-locale table in "Store
locales (21)".

| Locale | Name | Subtitle | Keywords |
|---|---|---|---|
| en-US, en-GB | `Bucketeer: S3 & Azure Storage` (29 of 30) | `Browse, sync & mount buckets` (28 of 30) | `aws,cloud,object,blob,r2,b2,backblaze,wasabi,minio,upload,transfer,client,drive,encryption,backup` (97 of 100 bytes) |
| de-DE | `Bucketeer: S3 & Azure Speicher` (30 of 30) | `Sync & Mount für Buckets` (24 of 30) | `aws,cloud,sync,blob,object,r2,b2,backblaze,wasabi,upload,laufwerk,datei,backup,verschlüsselung` (95 of 100 bytes) |

Earlier decision, Marcello 2026-11-09 Europe/Rome: include everything
in the keyword field (provider names and generic terms, including
`backup`); drop `s3` and `azure` where the name already carries them.

Nothing has been written to App Store Connect. ASC still holds the
older drafts for 20 store locales (version 1.0,
`PREPARE_FOR_SUBMISSION`, not public) and no tr localization. The ASC
write is ticket #22, from the texts in this file. The Turkish texts
and the other 17 locales are draft or pending a native pass, see
"Store locales (21)".
