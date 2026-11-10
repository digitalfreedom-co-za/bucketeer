# ASO keyword research: Bucketeer v1.0

Research for ticket [#2](https://github.com/digitalfreedom-co-za/bucketeer/issues/2).
Captured on 2026-11-09. This document is research and draft
recommendations only. Nothing here has been written to App Store
Connect, submitted or published.

Every figure below comes from a named source with a capture date.
Where data could not be obtained it is marked UNAVAILABLE with the
reason. Priorities that are not backed by a measurement are labelled
expert judgment.

---

## 1. Platform

Verified: Bucketeer is a native macOS app distributed only through
the Mac App Store. No iOS, iPadOS or Android version is assumed or
planned in this document.

| Evidence | Source |
|---|---|
| "A native macOS app for browsing, transferring, mounting and synchronising object storage" | [`README.md`](../README.md) |
| "Distributed exclusively through the Mac App Store" | [`README.md`](../README.md) |
| Branch flow ends in the App Store release build, first Mac App Store release | [`docs/RELEASE_v1.0.md`](RELEASE_v1.0.md) |
| The only App Store version in App Store Connect is `1.0`, platform `MAC_OS` | ASC API `GET /v1/apps/6787542659/appStoreVersions`, read only, 2026-11-09 |

## 2. Listing status

| Item | Status | Source |
|---|---|---|
| App record | Exists. App ID `6787542659`, bundle id `za.co.digitalfreedom.Bucketeer`, SKU `bucketeer-macos`, primary locale en-US | RELEASE checklist section 2, confirmed by ASC API 2026-11-09 |
| Store name | `Bucketeer – Object Storage` (26 characters). Plain `Bucketeer` is taken by another App Store app | RELEASE checklist, ASC API |
| Version 1.0 state | `PREPARE_FOR_SUBMISSION`, never submitted | ASC API 2026-11-09 |
| Categories | Primary `DEVELOPER_TOOLS`, secondary `UTILITIES` | ASC API 2026-11-09 |
| Territories | 175 territories configured, 174 marked available, France `CANNOT_SELL` (matches the export compliance decision) | ASC API `GET /v2/appAvailabilities/6787542659/territoryAvailabilities`, 2026-11-09 |
| Public listing | Not live. `itunes.apple.com/lookup?id=6787542659` returns 0 results and `apps.apple.com/us/app/id6787542659` returns HTTP 404 | Fetched 2026-11-09 |
| Live metadata | None. Only draft metadata exists in ASC (section 4) | ASC API |
| Keyword rankings | UNAVAILABLE. An app without a public listing cannot rank. Astro tracks Bucketeer as temporary app 113 and reports rank 1000 (Astro's value for not ranked) for every keyword | Astro MCP, 2026-11-09 |
| Acquisition baseline (impressions, page views, conversion) | UNAVAILABLE. No public listing, so ASC App Analytics has no data to report | ASC listing state above |

The App Store Connect drafts were checked with read-only GET requests
through the ASC API key of the ASO toolkit. No write request was made.

## 3. Metadata languages

The product documentation lists 20 app locales: en-US, en-GB, cs, da,
nl, fi, fr, de, el, hu, it, ja, ko, no, pl, pt-BR, pt-PT, ru, es, sv
([`README.md`](../README.md)).

Verified on 2026-11-09: App Store Connect already holds app info
localizations (name, subtitle) and version localizations (keywords,
promotional text, description) for exactly these 20 store locales:
cs, da, de-DE, el, en-GB, en-US, es-ES, fi, fr-FR, hu, it, ja, ko,
nl-NL, no, pl, pt-BR, pt-PT, ru, sv.

The launch checklist in [`APP_STORE_METADATA.md`](APP_STORE_METADATA.md)
still lists "Add localised App Store descriptions" as open. The ASC
drafts show this work was done in ASC directly, so the repo document
is behind ASC. The ASC texts have not been reviewed by native speakers
as far as this research can tell; no review record was found.

## 4. Current draft baseline

### 4.1 Repo draft versus ASC draft

The repo document and the ASC drafts differ. ASC is the copy that
would ship, so the recommendations below start from ASC.

| Field | Apple limit | Repo `APP_STORE_METADATA.md` | ASC en-US draft (2026-11-09) |
|---|---|---|---|
| Name | 30 characters | not in the document | `Bucketeer – Object Storage` (26) |
| Subtitle | 30 characters | `Object storage at hand` (22) | `S3 and Azure Blob file browser` (30) |
| Keywords | 100 bytes | `s3,azure,blob,object,storage,aws,r2,backblaze,wasabi,minio,sync,mount,finder,encrypt,shortcuts` (95) | `s3,azure,blob,aws,bucket,r2,backblaze,b2,wasabi,minio,civo,spaces,storj,sync,mount,upload,cloud` (95 bytes) |
| Promotional text | 170 characters | 129 characters | 157 characters |
| Description | 4000 characters | about 3500 characters | 1883 characters |

Apple limits from Apple's
[app information reference](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information)
(name and subtitle 30 characters) and
[platform version reference](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information)
(keywords 100 bytes, promotional text 170 characters, description
4000 characters), fetched 2026-11-09.

ASC en-US promotional text: "Browse, transfer, sync and mount
buckets from AWS S3, Azure Blob Storage, Cloudflare R2, Backblaze B2
and other S3-compatible services in one native Mac app."

ASC en-US description themes, in order: provider list, browse and
transfer, organize (dashboard, versions, tags, trash, activity log),
security (Keychain, client-side encryption, Touch ID, no analytics),
automation (deep links, Spotlight, Shortcuts), Bucketeer Pro (mount,
sync, cross-account copy, menu bar), pricing, source availability.

### 4.2 All 20 ASC locales

Name length is 26 in every locale (the name is not localized).

| Locale | Subtitle | Subtitle chars | Keyword chars | Keyword bytes | Keyword terms also in name or subtitle |
|---|---|---|---|---|---|
| cs | Prohlížeč souborů S3 a Azure | 28 | 90 | 94 | s3, azure |
| da | Filbrowser til S3 og Azure | 26 | 97 | 97 | s3, azure |
| de-DE | Dateibrowser für S3 und Azure | 29 | 99 | 99 | s3, azure |
| el | Περιήγηση αρχείων S3 και Azure | 30 | 83 | 93 | s3, azure |
| en-GB | S3 and Azure Blob file browser | 30 | 95 | 95 | s3, azure, blob |
| en-US | S3 and Azure Blob file browser | 30 | 95 | 95 | s3, azure, blob |
| es-ES | Explorador de S3 y Azure Blob | 29 | 99 | 99 | s3, azure, blob |
| fi | Tiedostoselain: S3 ja Azure | 27 | 90 | 90 | s3, azure |
| fr-FR | Navigateur S3 et Azure Blob | 27 | 90 | 90 | s3, azure, blob |
| hu | Fájlböngésző: S3 és Azure | 25 | 94 | 98 | s3, azure |
| it | File browser per S3 e Azure | 27 | 98 | 98 | s3, azure |
| ja | S3とAzure Blobのファイルブラウザ | 22 | 62 | 92 | s3, azure, blob (by inspection) |
| ko | S3 및 Azure Blob 파일 브라우저 | 23 | 64 | 96 | s3, azure, blob |
| nl-NL | Bestandsbrowser: S3 en Azure | 28 | 96 | 96 | s3, azure |
| no | Filleser for S3 og Azure Blob | 29 | 99 | 99 | s3, azure, blob |
| pl | Przeglądarka plików S3 i Azure | 30 | 91 | 91 | s3, azure |
| pt-BR | Navegador para S3 e Azure Blob | 30 | 93 | 93 | s3, azure, blob |
| pt-PT | Navegador para S3 e Azure Blob | 30 | 93 | 93 | s3, azure, blob |
| ru | Файловый браузер S3 и Azure | 27 | 73 | 100 | s3, azure |
| sv | Filbläddrare för S3 och Azure | 29 | 96 | 96 | s3, azure |

All drafts are within Apple's limits. The ru keyword field sits at
exactly 100 bytes because Cyrillic letters take two bytes each.

Finding: every locale repeats `s3` and `azure` (and in ten locales
`blob`) in the keyword field although these words already appear in
the subtitle. Apple's
[search guidance](https://developer.apple.com/app-store/search/)
(fetched 2026-11-09) says: "Don't repeat any words included in your
app name, subtitle, or category." Removing the repeats frees 9 to 14
bytes per locale at no cost.

## 5. Competitor set

Source: Astro MCP `search_app_store`, US storefront, platform mac,
2026-11-09, cross-checked with Apple's public lookup API
(`itunes.apple.com/lookup`, 2026-11-09). Subtitles are the values
the App Store returns in search results. Competitors' keyword fields
are not public and therefore not known.

| App | App Store ID | Subtitle shown | Genre | Ratings (Astro) | Price and version (Apple lookup) |
|---|---|---|---|---|---|
| [Cyberduck](https://apps.apple.com/us/app/id409222199) (David Kocher) | 409222199 | FTP & cloud storage browser | Productivity | 4.0 from 119 | $23.99, 9.6.0 of 2026-11-06 |
| [Transmit 5](https://apps.apple.com/us/app/id1436522307) (Panic) | 1436522307 | Fast and easy file transfers | Developer Tools | 4.4 from 6922 | Free, 5.11.7 of 2026-10-01 |
| [CloudMounter: Cloud Manager](https://apps.apple.com/us/app/id1130254674) (Eltima) | 1130254674 | AWS S3,SFTP,FTP,WebDAV Client | Productivity | 4.5 from 879 | Free, 4.18 of 2026-06-17 |
| [Mountain Duck](https://apps.apple.com/us/app/id1024974133) (David Kocher) | 1024974133 | Mount remote storage as a disk | Productivity | 2.9 from 54 | Free, 5.4.0 of 2026-11-06 |
| [Bucketmate](https://apps.apple.com/us/app/id6754320368) (Tran Huu Dung) | 6754320368 | S3-compatible GUI client | Developer Tools | no ratings | Free, 1.4 of 2026-10-10 |
| [`S3 Client - Files location`](https://apps.apple.com/us/app/id6447647340) (Anders Borum) | 6447647340 | for AWS, Backblaze & MinIO | Productivity | 4.8 from 35 | Free, 2026.43 of 2026-11-08 |
| [`Bucketly – S3 Client & Browser`](https://apps.apple.com/us/app/id6761632927) | 6761632927 | File Manager: AWS, R2, MinIO | Developer Tools | no ratings | not looked up |
| [`R2Explorer - Bucket Manager`](https://apps.apple.com/us/app/id6761668362) | 6761668362 | Cloudflare R2 & S3 manager | Developer Tools | no ratings | not looked up |
| ForkLift (BinaryNights) | none | not on the Mac App Store | | | |

Notes:

- ForkLift was not found on the Mac App Store: Astro search for
  `forklift` (US, mac) and Apple's search API (`term=forklift`,
  `entity=macSoftware`) returned no ForkLift entry on 2026-11-09.
  [binarynights.com](https://binarynights.com/) offers "Try for free"
  and "Buy now" and lists Amazon S3 and Backblaze B2 among its remote
  connections. It competes for the same users but not for App Store
  search positions.
- Apple's lookup returned 0 ratings for the four mac-software
  entries, while Astro reports the counts above. The counts are
  Astro's figures; the discrepancy was not resolved.
- Bucketmate and S3 Client are returned by Apple's lookup as kind
  `software` rather than `mac-software`, which suggests iPhone and
  iPad binaries that also appear in Mac search. Not verified further.
- Top results for `s3` (US, mac, 2026-11-09): S3 Client, Browser for
  AWS S3 Buckets, S3 Browse, Transmit 5, S3 Manager, S3 Explorer,
  Bucketly, S3 File Manager. Most S3 specialists have no ratings, so
  the niche is crowded with new apps but has few established ones.
- Observed themes: protocol lists (FTP, SFTP, WebDAV), provider
  names in the subtitle (AWS, Backblaze, MinIO, R2), "client",
  "manager", "browser", and for Mountain Duck the mount use case.
  Live subtitles naming AWS, Backblaze, MinIO and Cloudflare R2 show
  that Apple currently accepts provider names in subtitles.
- Competitor app names (Cyberduck, Transmit, CloudMounter, Mountain
  Duck, ForkLift) must not go into Bucketeer's metadata. Apple's
  [App Review Guideline 2.3.7](https://developer.apple.com/app-store/review/guidelines/)
  forbids packing metadata with "popular app names", and the ASC
  keyword reference says "Names of other apps or companies aren't
  allowed."

## 6. Keyword evidence and shortlist

### 6.1 Source and metric definitions

| | |
|---|---|
| Tool | Astro (Mac app, MCP server `astro-mcp-server` 2026.14.1 build 330) |
| Storefronts | US and DE, platform mac |
| Date | 2026-11-09 unless a row says otherwise. Rows dated 2026-05-23 are older Astro values that were not refreshed in this run |
| Popularity | Astro's popularity score. Astro does not expose its definition through the MCP tool. Observed range in this run: 5 to 56. The value 5 is the floor Astro returned for many niche terms, so 5 means "no measurable demand at Astro's resolution", not a count |
| Difficulty | Astro's difficulty score; definition not exposed |
| Apps | Number of apps Astro counted for the term |

To obtain fresh values, candidate keywords were added to Astro's
temporary Bucketeer entry and removed again after reading. Astro's
tracking list is back to its previous 8 keywords. This changed only
the local Astro database, not App Store Connect.

What is UNAVAILABLE:

- True search volumes. Apple does not publish search counts. Apple
  Search Ads popularity was not accessed (no Search Ads account access
  verified for this ticket).
- Rankings for Bucketeer (no public listing).
- Conversion figures (no public listing, no ASC analytics).
- Measurements for the 18 storefronts other than US and DE. Only
  these two were measured in this run.

### 6.2 Measured values

Relevance is expert judgment based on the verified features in
`README.md`. It is not measured demand.

| Keyword | Relevance | US pop | US diff | US apps | DE pop | DE diff | Placement idea |
|---|---|---|---|---|---|---|---|
| sync | high (sync jobs, Pro) | 51 | 13 | 238 | 39 | 11 | subtitle |
| aws | high (AWS S3 preset) | 46 | 9 | 206 | 38 | 13 | keywords, variant A only |
| azure | high (Azure Blob backend) | 45 | 19 | 110 | 37 | 15 | name |
| cloud storage | medium (object storage is cloud storage, but the term also means Dropbox style apps) | 39 | 13 | 205 | | | `cloud` in keywords plus `storage` in name |
| cloud speicher | medium, same reasoning | | | | 30 | 23 | `cloud` plus `speicher` |
| speicher | medium | | | | 37 | 15 | name (de-DE) |
| synchronisieren | high | | | | 34 | 15 | keywords (de-DE) |
| wasabi | high (preset) | 38 | 17 | 15 | | | keywords, variant A only |
| file transfer | high (transfers) | 38 | 21 | 234 | | | `file` plus `transfer` in keywords |
| upload | high | 35 | 13 | 182 | | | keywords |
| bucket | high (core object) | 34 | 7 | 167 | 5 | 5 | subtitle |
| backblaze | high (preset) | 32 | 13 | 22 | 5 | 11 | keywords, variant A only |
| b2 | high (Backblaze B2 preset) | 30 | 23 | 232 | | | keywords |
| r2 | high (Cloudflare R2 preset) | 26 | 23 | 180 | | | keywords |
| s3 | high (core protocol) | 26 | 9 | 249 | 9 | 17 | name |
| mount | high (Mount as Drive, Pro) | 25 | 19 | 101 | | | subtitle |
| minio | high (Custom preset), US value of 2026-05-23 | 20 | 9 | 9 | 5 | 5 | keywords, variant A only |
| s3 client | high | 19 | 19 | 210 | | | `client` in keywords plus `s3` in name |
| cloudflare | medium (company name), US value of 2026-05-23 | 56 | 9 | 138 | 49 | 19 | not in keywords (company name) |
| spaces | low (ambiguous, DigitalOcean Spaces is one preset) | 41 | 7 | 238 | | | dropped |
| backup | conditional (folder to bucket sync can serve backups, but Bucketeer is not marketed as a backup app) | 36 | 17 | 238 | | | product decision |
| file manager | low (search intent is local file management) | 56 | 7 | 229 | 8 | 15 | not used |
| object storage | high relevance, no measurable demand (US value of 2026-05-23) | 5 | 7 | 46 | 5 | 5 | covered by `object` plus `storage` |
| azure blob, azure storage, blob storage | high relevance, no measurable demand | 5 | 5 to 7 | 59 to 215 | | | covered by `blob` plus name |
| s3 browser, s3 bucket, s3 explorer, aws s3, cloudflare r2 | high relevance, no measurable demand | 5 | 7 to 13 | 59 to 243 | | | covered by single words |
| mount drive, network drive, netzlaufwerk, laufwerk | medium, no measurable demand | 5 | 13 to 23 | | 5 | 15 to 23 | `drive` or `laufwerk` in keywords |
| civo, storj, digitalocean | high (presets), low or no measurable demand | 5 to 13 | 5 to 13 | | | | dropped |
| ftp, sftp | none: Bucketeer has no FTP or SFTP support | 44, 31 | 15, 17 | | 39, 30 | 15, 17 | excluded |
| cyberduck, transmit, cloudmounter, mountain duck, forklift | competitor app names | 5 to 29 | | | 5 to 26 | | excluded (guideline 2.3.7) |

The older Astro note in the ASO toolkit (`apps/bucketeer/bucketeer.md`,
2026-05-23) proposed `ftp` and `sftp` for the keyword field. Bucketeer
1.0 supports neither, so they stay out.

### 6.3 Provider names in the keyword field (resolved)

Apple's keyword reference says "Names of other apps or companies
aren't allowed", and guideline 2.3.7 warns against trademarked terms
used to game search. AWS, Backblaze, Wasabi, MinIO, Cloudflare, Civo
and Storj are company or brand names, even though Bucketeer supports
each of them. The current ASC drafts use them. Live competitors name
providers in their subtitles (section 5), which shows acceptance in
the subtitle, but says nothing about keyword fields, which are not
public.

This document therefore offers two keyword variants. Choosing between
them is a decision for Marcello. Expert judgment: variant B for the
first submission, because a metadata rejection would delay the launch,
and the provider names still appear in the description and
promotional text for users.

## 7. Recommended drafts

Not live. Field lengths were checked with a script on 2026-11-09:
characters for name and subtitle, UTF-8 bytes for keywords, and a
check that no keyword repeats a word from the name, subtitle or the
category names.

Apple documents that search uses the text relevance of name,
subtitle, keywords and primary category. Whether it combines words
across fields into phrases (for example `cloud` in keywords with
`storage` in the name for "cloud storage") is common ASO practice
but not documented by Apple. The placement ideas above rely on that
assumption.

### 7.1 en-US (and en-GB unchanged copy)

| Field | Current ASC draft | Recommended draft | Length |
|---|---|---|---|
| Name | `Bucketeer – Object Storage` | `Bucketeer: S3 & Azure Storage` | 29 of 30 |
| Subtitle | `S3 and Azure Blob file browser` | `Browse, sync & mount buckets` | 28 of 30 |
| Keywords (approved: providers + generics + backup) | see 4.1 | `aws,cloud,object,blob,r2,b2,backblaze,wasabi,minio,upload,transfer,client,drive,encryption,backup` | 97 of 100 bytes |
| Promotional text | 157 characters | keep the current ASC text | 157 of 170 |

Reasoning (expert judgment applied to the measured values):

- The name moves the two terms with measured US demand (`s3` 26,
  `azure` 45) into the field Apple weights most, and keeps `storage`
  for "cloud storage" and "object storage". `object storage` itself
  shows no measurable demand (5).
- The subtitle states the three actions with demand (`sync` 51,
  `bucket` 34, `mount` 25) in a readable sentence. `mount` is accurate
  for Bucketeer Pro; the encrypted-bucket restriction belongs in the
  description (ticket 7), not in a 30 character subtitle. The
  subtitle avoids absolute claims such as "any bucket".
- Variant B keeps only generic words plus the product names `r2` and
  `b2`, leaving 16 bytes free. Candidates for those bytes: `backup`
  (US 36) if Marcello confirms backup is an intended positioning, or
  `share` (unmeasured) for presigned links.
- Promotional text does not affect search ranking according to
  Apple's search guidance, so it stays focused on conversion. The
  current text is accurate against `README.md`.
- Description: left to ticket 7. Observation for ticket 7: the ASC
  en-US description draft does not contain the "only network traffic"
  sentence, but its Pro bullet "Mount a bucket as a drive in Finder
  (macOS 14.1 or later)" does not mention that buckets with
  client-side encryption cannot be mounted. Ticket 7 so far changed
  the repo draft only, not the ASC drafts.

### 7.2 de-DE

| Field | Current ASC draft | Recommended draft | Length |
|---|---|---|---|
| Name | `Bucketeer – Object Storage` | `Bucketeer: S3 & Azure Speicher` | 30 of 30 |
| Subtitle | `Dateibrowser für S3 und Azure` | `Sync & Mount für Buckets` | 24 of 30 |
| Keywords (approved direction) | see 4.2 | `aws,cloud,sync,blob,object,r2,b2,backblaze,wasabi,upload,laufwerk,datei,backup,verschlüsselung` | 95 of 100 bytes |

Reasoning: in the DE storefront `s3` alone shows little demand (9)
while `sync` (39), `azure` (37), `speicher` (37) and
`synchronisieren` (34) do. `cloud` plus `speicher` targets
"cloud speicher" (30). English terms such as `sync`, `mount`,
`bucket` and `storage` are kept because the existing German ASC
copy already uses them and they are common in German developer
language (expert judgment). The name and subtitle need a review by a
native German speaker before use.

### 7.3 Other locales

No storefront measurements exist for the other 18 locales, so no
localized name, subtitle or keyword field is proposed for them. Do not
translate the en-US drafts word by word into all 20 locales without
review. Recommended approach:

1. Zero risk fix for every locale: remove `s3`, `azure` and, where
   the subtitle contains it, `blob` from the keyword field (section
   4.2). Use the freed bytes for a locale-native generic term, chosen
   by a native speaker.
2. If the en-US name changes, decide per locale whether the localized
   name keeps English `Storage` or uses the local word (as `Speicher`
   in de-DE).
3. Measure each priority storefront in Astro before rewriting its
   subtitle and keywords, then have a native speaker write the copy.
4. Order of the work: open question for Marcello (section 9). en-GB
   can reuse en-US as it does today.

## 8. Measurement plan

Baselines can only be captured after the first public release.

| Step | What | Source |
|---|---|---|
| 1. Day of release | Add the real App Store ID `6787542659` to Astro on platform mac (US and DE first) and track the shortlist from section 6.2. Retire temporary entry 113. Add `bucketeer` to `APP_STORE_IDS` in the ASO toolkit's `scripts/asc_common.py` so `asc_analytics.py` can report it | Astro, ASO toolkit |
| 2. Days 1 to 28 | Baseline per storefront and per day: impressions, product page views, first-time downloads and conversion rate as defined in ASC App Analytics, split by source type (App Store Search, App Store Browse, Web Referrer, App Referrer). Daily keyword ranks from Astro. Pro trial starts and Pro purchases from App Store Connect sales data | ASC App Analytics (`APP_STORE_ENGAGEMENT` report via `asc_analytics.py`), Astro |
| 3. Change | Name, subtitle and keyword field change only with a new app version submission; promotional text can change at any time. Change one field group per version so effects can be told apart | ASC |
| 4. Review window | Compare the 28 days after a metadata change with the 28 days before, per storefront, on App Store Search impressions, search conversion rate and ranks of the targeted keywords | ASC, Astro |
| 5. Screenshots and icon | Use Product Page Optimization for these. Apple's PPO tests icons, screenshots and app previews, not name, subtitle or keywords | [Apple PPO page](https://developer.apple.com/app-store/product-page-optimization/), fetched 2026-11-09 |

Targets: not set. Setting numeric targets before any baseline exists
would be invention. Define them after the first 28 day baseline.

Attribution limits:

- The launch period mixes the effect of the listing itself with
  launch announcements and the website; the first 28 days are a
  baseline, not a test result.
- Several changes in one version (for example a new subtitle plus new
  screenshots) cannot be separated afterwards.
- Astro ranks are point samples from Astro's fetches and can differ
  from what a given user sees.
- Apple applies privacy thresholds to App Analytics; the exact
  thresholds were not verified in this research. Small storefronts
  may show no data.
- No App Store mechanism A/B tests text metadata, so text changes are
  before and after comparisons with all their seasonal noise.

## 9. Decisions and remaining questions

Resolved 2026-11-09 Europe/Rome (Marcello):

1. Keywords: include everything. Use provider names and generic terms,
   including `backup`. Chosen en-US keyword draft (100 of 100 bytes):
   `aws,cloud,object,blob,r2,b2,backblaze,wasabi,minio,upload,transfer,client,drive,encryption,backup`.
   Still research/draft only. No App Store Connect write.

Still open:

1. ASC listing verification: the ASC drafts (20 locales) are ahead of
   `APP_STORE_METADATA.md`. Should ASC become the source of truth, or
   should the repo document be synced from ASC?
2. Name change from `Bucketeer – Object Storage` to
   `Bucketeer: S3 & Azure Storage` before the first submission?
3. Paid ASO tool access: Astro provides relative popularity and
   difficulty scores only. Is access to Apple Search Ads popularity or
   another ASO tool with search volume estimates available?
4. Locale priority after en-US and de-DE: which storefronts matter
   most? Each needs an Astro measurement and a native speaker review.
