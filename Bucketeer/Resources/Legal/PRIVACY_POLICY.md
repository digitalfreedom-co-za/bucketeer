# Privacy Policy

*How Bucketeer for macOS handles your data — short answer: it doesn't
send any of it to us.*

**Application** — Bucketeer for macOS
**Publisher** — DigitalFreedom · Berger & Rosenstock GbR
**Postal address** — Dieselstr. 22e · 61231 Bad Nauheim · Germany
**VAT-ID** — DE 455 096 022
**Representatives** — Marcel R. G. Berger, Jasmin Rosenstock
**Privacy contact** — data-protection@digitalfreedom.co.za
**Effective date** — 24 May 2026

---

## 1. Summary

**Bucketeer is a strictly local-first macOS app.** The Publisher
operates **no servers** in connection with the App, runs **no
telemetry**, ships **no analytics SDK**, embeds **no off-Mac crash
reporter**, and has **no account system**.

The App holds, all on your Mac:

- Your S3 / Azure connection metadata in a SwiftData store inside the
  App's sandboxed App Group container.
- Your S3 / Azure credentials in the macOS Keychain access group
  `$(TeamID).za.co.digitalfreedom.bucketeer.shared`.
- A host-only audit log of operations you triggered, in a separate
  SwiftData store under Application Support.
- Optionally, a preview cache and downloaded files in your macOS user
  directories.

The only network traffic Bucketeer creates is the **direct, signed
request** your Mac sends to the storage endpoint **you** configured.
The Publisher cannot read your credentials, your bucket listings, or
your object contents.

---

## 2. Data controller

Where any personal data is processed locally on your Mac (essentially
just the secret access keys held in the Keychain on your behalf), the
data controller under Art. 4(7) GDPR is:

Berger & Rosenstock GbR (trading as DigitalFreedom)
Dieselstr. 22e · 61231 Bad Nauheim · Germany

The Publisher does not act as a controller for any data that crosses
the network — that traffic is between your Mac and the storage
provider you configured.

---

## 3. Data the App handles

### 3.1 Stored locally on your Mac

**Account metadata** — name, provider type, region, endpoint URL,
account ID, default bucket, path-style flag, last-used timestamp.
Storage: SwiftData store in the App Group container
`group.za.co.digitalfreedom.bucketeer`. Purpose: identify and connect
to each configured storage account.

**Credentials** — S3 access key, secret key, optional session token /
Azure storage-account name + account key. Storage: macOS Keychain,
access group `$(TeamID).za.co.digitalfreedom.bucketeer.shared`, with
`kSecAttrAccessibleWhenUnlocked`. Purpose: sign authenticated requests
to the configured endpoint.

**Sync job definitions** — source / destination endpoint, mode, glob
filters, schedule, last-run summary. Storage: same SwiftData store as
the account metadata. Purpose: schedule and execute the user-defined
sync jobs.

**Activity log** — one row per upload, download, delete, sync run,
signed URL, account change, or watch-folder trigger you initiated.
Storage: separate SwiftData store `BucketeerActivity.store` under
Application Support, auto-purged after 180 days. Purpose: in-app audit
view + optional CSV export.

**Bandwidth limit** — selected preset + custom MB/s value. Storage:
`UserDefaults.standard`, key `bandwidth.limit.bytesPerSecond`.
Purpose: cap upload / download throughput.

**Trial state** — trial start date and "trial consumed" marker.
Storage: `UserDefaults.standard`, keys `bucketeer.trial.start` and
`bucketeer.trial.consumed`. Purpose: track the 14-day Bucketeer Pro
trial.

**Active StoreKit entitlement** — read on demand from
`Transaction.currentEntitlements`, not duplicated by the Publisher.
Purpose: determine whether Bucketeer Pro features are unlocked.

**Preview cache** — downloaded object payloads for inline Quick Look.
Storage: sandboxed temporary directory, SHA-256-keyed, 2 GiB LRU cap.
Purpose: show inline previews without re-fetching.

**Downloaded files** — at the location you chose in the save panel.
Your data, retained as long as you want.

**File Provider mount staging files** — system-managed File Provider
replica directory. Required by the macOS File Provider replicated-
extension model.

### 3.2 Sent over the network — but never to the Publisher

When you use the App, it sends standard S3 / Azure Blob requests
(`ListBuckets`, `ListObjectsV2` / `List Containers` / `List Blobs`,
`GetObject` / `Get Blob`, `PutObject` / `Put Block Blob`,
`DeleteObject` / `Delete Blob`, `CopyObject` / `Copy Blob`,
`HeadObject` / `Get Blob Properties`) to the endpoint URL configured
for each account.

Each request is signed locally using **AWS Signature v4** (S3 family)
or **Azure Shared Key HMAC-SHA256** (Azure family). The Publisher is
not on the path of those requests and has no visibility into them.

### 3.3 Data the App does NOT collect

The App does not, at any time, collect, process, transmit, or store
on the Publisher's behalf:

- Personal identifiers (name, email, phone, postal address)
- Device identifiers (advertising identifier, IDFV, IDFA, hardware
  UUID, MAC address, serial number)
- Usage analytics, telemetry, feature-engagement events
- Crash reports, diagnostic logs, performance traces
- Location data of any kind
- Microphone, camera, photo library, contacts, calendar, reminders,
  HealthKit, HomeKit, or Apple Pay data
- Browsing history beyond the bucket listings the App displays in its
  own window for your own session
- Data for advertising, marketing, attribution, or profiling

---

## 4. Legal basis under GDPR

Where the App processes personal data locally on your Mac (essentially
just your storage credentials in the Keychain), the legal basis is:

- **Art. 6(1)(b) GDPR** — performance of the contract (this Privacy
  Policy + the EULA) at your request, and
- **Art. 6(1)(f) GDPR** — the Publisher's legitimate interest in
  providing the functionality you installed the App to use.

No data leaves your Mac as a consequence of this processing, except
the API requests to the storage endpoints **you** configured.

---

## 5. Third parties

### 5.1 Storage endpoints you configure

Each storage provider you connect to (AWS, Azure, Cloudflare,
Backblaze, Wasabi, DigitalOcean, Civo, Storj, MinIO, or any custom
endpoint) is a **separate data controller**. The App acts purely as
your client and routes your requests to the endpoint URL you chose.
The Publisher has no contractual relationship with those providers and
makes no representations about how they handle your data. Consult each
provider's own privacy policy.

### 5.2 Apple (Mac App Store + StoreKit)

Apple distributes the App and processes the Bucketeer Pro in-app
purchase. Apple receives standard purchase, download, and crash data
in connection with that distribution under Apple's own privacy policy
(`https://www.apple.com/legal/privacy/`). The Publisher receives only
aggregated payout reports from App Store Connect.

### 5.3 No other third parties

The App contains no advertising, analytics, crash-reporting, or
attribution SDKs. There are no third-party services the App contacts
of its own accord.

---

## 6. International transfers

The Publisher does not receive your data, so there is no international
transfer on the Publisher's side.

Network traffic the App generates to your storage endpoint may cross
international borders depending on the region you selected for that
provider. That transfer is between you and the provider; the Publisher
is not party to it.

---

## 7. Retention

**Account metadata** — until you delete the account in the App or
uninstall the App.

**Keychain credentials** — until you delete the account, change
credentials, or uninstall the App.

**Sync job definitions** — until you delete the job or uninstall the
App.

**Activity log entries** — automatically purged 180 days after they
are recorded. You can clear the log on demand from the Activity Log
window.

**Trial start / consumed marker** — permanent on your Mac; survives
App uninstall in `~/Library/Preferences` and is sticky to prevent
trial reset.

**Preview cache** — LRU-evicted at 2 GiB; cleared on user-initiated
"Clear Cache" and on uninstall.

**Downloaded files** — under your full control; the Publisher never
receives or tracks them.

**File Provider mount replicas** — managed by the macOS File Provider
system; removed when you unmount the bucket or uninstall the App.

The Publisher holds **no** copies of any of the above.

---

## 8. Your GDPR rights

Because the Publisher holds no personal data about you, the rights
under GDPR Art. 15 – 22 have nothing to act on at the Publisher's end:

- **Right of access (Art. 15)** — the Publisher holds no data on you
  to disclose.
- **Right to rectification (Art. 16)** — none to rectify.
- **Right to erasure (Art. 17)** — none to erase.
- **Right to data portability (Art. 20)** — none to export.
- **Right to restriction (Art. 18) / objection (Art. 21)** — no
  processing of your personal data takes place at the Publisher's end.

You retain full control of the data the App handles on your Mac:
delete accounts in the App, remove files in Finder, uninstall the App
to clear everything, or use Keychain Access to inspect / remove the
stored credentials directly.

For data held by your **storage providers**: exercise those rights
with each provider directly.

For data held by **Apple** in connection with the App Store: exercise
those rights with Apple directly.

If you nevertheless have a privacy question, contact
data-protection@digitalfreedom.co.za. The Publisher will respond
within one month per Art. 12(3) GDPR.

You have the right to lodge a complaint with a supervisory authority.
The Publisher's lead authority is:

**Der Hessische Beauftragte für Datenschutz und Informationsfreiheit**
Postfach 3163 · 65021 Wiesbaden · Germany
`https://datenschutz.hessen.de/`

---

## 9. Children

Bucketeer is a developer / power-user tool. It is not directed at
children and is rated 17+ on the Mac App Store. The App does not
collect personal data and therefore does not knowingly process
personal data of children.

---

## 10. Security

- The App runs inside the macOS **App Sandbox** with only these
  entitlements: outgoing network client, user-selected file
  read-write, default Downloads folder read-write, App Group
  container, shared Keychain access group.
- Credentials are stored in the macOS Keychain with
  `kSecAttrAccessible = kSecAttrAccessibleWhenUnlocked` and
  `kSecAttrSynchronizable = false`. They are never written to disk in
  plaintext, never written to system logs (`Logger` markers use
  `privacy: .private` on credential-derived strings), and never
  displayed in user-facing error messages.
- Touch ID / device-owner authentication gates the **Reveal stored
  credentials** affordance in the Add / Edit Account sheet via
  `LAContext.deviceOwnerAuthentication`.
- All network connections to storage endpoints use TLS (Application
  Transport Security default policy, no ATS exceptions). The Soto S3
  client enforces TLS 1.2 minimum.
- Azure Shared Key signing uses HMAC-SHA256 from Apple's CryptoKit.

The Publisher operates no servers in connection with this App;
there is no server-side security boundary to maintain.

---

## 11. StoreKit purchases

When you buy Bucketeer Pro, the App reads
`Transaction.currentEntitlements` from the macOS App Store framework
to verify the purchase locally on your Mac. The Publisher receives
only the aggregated payout reports App Store Connect provides;
individual transactions are processed and stored by Apple under
Apple's own privacy policy. Family Sharing is enabled for the
Bucketeer Pro IAP — a single purchase covers your Family Sharing
group at no extra cost.

Refunds are handled exclusively by Apple via
`reportaproblem.apple.com`. The Publisher cannot process refunds or
access purchase records beyond the App Store Connect payout summary.

---

## 12. Jurisdiction-specific notes

Bucketeer is sold through Apple's Mac App Store and reaches every
country where Apple distributes apps. Because the App collects no
personal data on the Publisher's behalf, the Publisher takes no role
under most international privacy regimes for the App's local
operation:

- **California (CCPA / CPRA)** — the App does not collect, sell,
  share, or disclose any personal information. The right to opt out
  of "sale" or "sharing" is not applicable because no such activity
  takes place.
- **Brazil (LGPD)** — the Publisher is neither *controlador* nor
  *operador* under Art. 5 LGPD with respect to this App's local
  operation.
- **South Africa (POPIA)** — the Publisher does not engage as
  "responsible party" within the meaning of POPIA.
- **India (Digital Personal Data Protection Act)** — the Publisher is
  not a "Data Fiduciary" with respect to App users.
- **Japan (APPI) / South Korea (PIPA) / Australian Privacy Act 1988**
  — no personal information is collected by the Publisher.
- **United Kingdom (UK GDPR + DPA 2018)** — the Publisher applies the
  GDPR-equivalent rules described above.

If your local regime creates obligations that are not addressed above,
contact data-protection@digitalfreedom.co.za and the Publisher will
respond within the time required by your local law.

---

## 13. Changes to this Policy

Material changes are reflected in a new **Effective date** at the top
of this document and announced in the Mac App Store release notes for
the release that introduces them.

---

## 14. Contact

**Privacy / data-protection inquiries** — data-protection@digitalfreedom.co.za
**General inquiries** — hello@digitalfreedom.co.za
**Postal** — Berger & Rosenstock GbR · Dieselstr. 22e · 61231 Bad Nauheim · Germany

---

© 2026 DigitalFreedom · Berger & Rosenstock GbR · All rights reserved.
