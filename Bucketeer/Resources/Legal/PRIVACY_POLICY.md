<!-- doc-id: BUCKETEER_PRIVACY_POLICY | lang: en | area: app | version: 1.0.2 | valid-from: 2026-11-12 | baseline: legal shared/PRIVACY_POLICY.en.md, Bucketeer product adaptation; baseline version at derivation not recorded (legal b938e59 carries PRIVACY_POLICY 2.3.1) | owner: Marcel R. G. Berger -->
# Privacy Policy

*How Bucketeer for macOS handles your data.*

**Application** — Bucketeer for macOS, including its Finder extension
("Bucketeer File Provider")
**Effective date** — 12 November 2026

**Controller** — DigitalFreedom Global LLC (trading as DigitalFreedom),
30 N Gould St, Ste N, Sheridan, WY 82801, United States
**Data protection contact** — data-protection@digitalfreedom.co.za ·
request form https://data-protection.digitalfreedom.co.za
**General contact** — hello@digitalfreedom.co.za
**Website** — https://digitalfreedom.co.za

---

## 1. Summary

- There is **no Bucketeer server and no Bucketeer account**. The
  provider does not receive your credentials, your bucket listings or
  the content of your files.
- Everything Bucketeer stores stays **on your Mac**: credentials and
  encryption keys in the macOS Keychain, everything else in the App's
  local storage.
- Bucketeer contains **no analytics, no tracking, no advertising, no
  crash-reporting and no attribution SDKs**.
- The App connects only to the **storage endpoints you configure**
  (S3-compatible providers and Azure Blob Storage) and to **Apple** for
  the App Store purchase.
- The provider only receives personal data from you if **you write to
  us**, for example a support request.

---

## 2. Global scope and GDPR as the baseline

Bucketeer is distributed through the Mac App Store. It is not offered
in the storefronts for Mainland China, Egypt, Saudi Arabia, Russia and
France. This Policy applies to every user of the App wherever they
live, including anyone who uses it outside the storefront where it was
obtained. The provider applies the EU General Data Protection Regulation (GDPR) as a
**global floor**: every user gets at least the protection described
here. Where the law of your country of residence is more protective,
that law applies.

---

## 3. What the App stores on your Mac

None of the following is sent to the provider.

| Data | Where it is stored | Purpose |
|---|---|---|
| Account metadata (name, provider type, region, endpoint URL, account ID, default bucket, path-style setting, last use) and sync job definitions (source, destination, mode, filters, schedule, local folder access, last run) | Local database in the App Group container `group.za.co.digitalfreedom.bucketeer`, shared with the Bucketeer Finder extension | Connect to your storage accounts and run your sync jobs |
| Access credentials (S3 access key, secret key, optional session token; Azure account name and key) | macOS Keychain, shared access group of the App and its Finder extension, available only while the Mac is unlocked, not synchronised via iCloud | Sign requests to the endpoint you configured |
| Activity log (time, operation, status, account name, bucket, object key, size, duration, error message, sync job) | Local database in the App's own container | Show you what the App did; optional CSV export. Entries are deleted automatically after 180 days; you can clear the log at any time |
| Trash (metadata of objects you deleted in Bucketeer and, up to a size limit you set, a local copy of their content) | Local database and cache folder in the App's own container | Let you restore objects you deleted. Entries are removed after the retention period you set (default 30 days) |
| Auto-tag rules, resumable-upload checkpoints | Local databases in the App's own container | Apply your tagging rules; resume interrupted uploads |
| Encryption keys (only if you enable client-side encryption for a bucket) | Key material in the macOS Keychain, key labels in a local database | Encrypt and decrypt objects on your Mac (see section 6) |
| Encryption key backup (optional, only if you export) | A passphrase-protected .bktkeys file at a location you choose in the macOS save dialog | Let you restore keys on this Mac or another Mac (see section 6) |
| Settings (bandwidth limit, trash and Spotlight settings, menubar mode) | The App's local preferences | Remember your choices |
| Preview cache | Temporary folder of the App, limited to 2 GiB | Show previews without downloading again |
| Files you open with another app (Open / Open With) | Temporary folder of the App | Let the other app edit the file and upload your saves; deleted once the storage provider has your last save |
| Edits that could not be uploaded (Open / Open With) | Application Support folder of the App | Keep your unsaved work after a failed upload or a crash; kept until you upload, export or discard it in the App |
| Downloaded files | The location you choose | Your files, under your control |
| Finder mount staging files (only for mounted buckets) | System-managed File Provider storage | Required by macOS to show a bucket in Finder |
| Last listing of the folders you opened in Finder (object names and ETags, only for mounted buckets) | The Finder extension's own container | Show changes made on the server in Finder |

Uninstalling the App does not necessarily remove all of this data from
your Mac. Delete accounts in the App first if you want the credentials
removed from the Keychain; you can also inspect and delete them in
Keychain Access.

---

## 4. Network connections

| Connection | When | What is sent | Recipient |
|---|---|---|---|
| Your storage endpoints (AWS S3, Cloudflare R2, Backblaze B2, Wasabi, DigitalOcean Spaces, Civo, Storj, MinIO, a custom S3 endpoint, Azure Blob Storage) | When you browse, transfer, sync, mount or change settings of a bucket | Standard S3 or Azure requests signed on your Mac, including object names, metadata and file content you upload; the endpoint also sees your IP address | The storage provider you chose, under your own contract with that provider |
| Apple App Store (StoreKit) | When you open the paywall, start the trial, buy or restore Bucketeer Pro, and when Apple reports a transaction | Apple's own purchase data; the App only reads whether Bucketeer Pro or the trial is active and when the trial started | Apple, as an independent controller |
| Links you open (website, support form, GitHub, Apple refund page) | Only when you click them | Request from your browser | The operator of that page |

The App sends no data to the provider. Requests to your storage
endpoints go directly from your Mac to the endpoint; the provider is
not on that path. The built-in provider addresses are reached over TLS
(https). If you enter an endpoint address yourself (custom S3, MinIO or
an endpoint override) and it starts with http://, for example a server
in your own network, the App connects without TLS, as you asked: object names, metadata, file content and the signed
requests then travel unencrypted and can be read on the network path.
The App shows a warning when you enter such an address.

---

## 5. Features with particular privacy relevance

**Finder mount (File Provider extension).** When you mount a bucket as
a drive, the Bucketeer extension reads the account metadata from the
App Group container and the credentials from the shared Keychain
group. It accesses only buckets you have mounted. Buckets with
client-side encryption cannot be mounted in this version.

**Presigned links.** Shareable links are created on your Mac by signing
a URL with your credentials. No server of the provider is involved.
Anyone who has the link can download the object until the link
expires, so share links with care.

**Spotlight.** Off by default. If you turn it on, file names, bucket
and account names of the folders you browse are added to the local
macOS Spotlight index on your Mac. File content is not indexed. Turning
it off or deleting an account removes the entries.

**Shortcuts and bucketeer:// links.** App Intents and deep links run
locally on your Mac and act only on accounts you have set up.

**Watch folders and local sync folders.** The App only accesses local
folders you have selected yourself; access is kept as a
security-scoped bookmark in the local database.

**Touch ID.** Revealing a stored secret requires
device-owner authentication (Touch ID or your Mac password). The App
receives only a yes/no result from macOS, never biometric data.

---

## 6. Client-side encryption (optional)

If you enable encryption for a bucket, the App creates a random
256-bit key on your Mac and stores it in the macOS Keychain. Objects
are encrypted with AES-256-GCM on your Mac before upload and decrypted
on your Mac after download. Your storage provider receives only the
encrypted data.

The provider has no copy of the key. The Keychain copy is not
synchronised to other devices and is not synchronised via iCloud. You
can optionally export keys to a passphrase-protected .bktkeys backup
after authenticating as the device owner (Touch ID or your Mac
password). The file contains the key material and labels such as
account and bucket names, encrypted with your passphrase. The App
writes only that encrypted file through the macOS save dialog and does
not send it over the network. If you save or later copy the file to a
synced or shared location, for example iCloud Drive, the encrypted
backup leaves this Mac under the terms of that service. Keep both the
file and the passphrase: if you delete the key or lose access to this
Mac's Keychain and have no usable backup, the encrypted objects cannot
be decrypted, and the provider cannot recover them. Object names and
metadata are not encrypted.

---

## 7. Your contact with us

If you write to us (email, support form, data protection form), we
process your name, email address, the content of your message and any
attachments to answer you. Legal basis: Art. 6(1)(b) GDPR where your
request concerns your purchase or use of the App, otherwise
Art. 6(1)(f) GDPR (our interest in answering enquiries). The processing
of support requests, the helpdesk providers involved and their
retention periods are described in the helpdesk privacy notice shown
in the support portal at https://support.apps.digitalfreedom.co.za.

---

## 8. Legal basis for local processing

The App processes your data on your Mac to provide the functions you
use (Art. 6(1)(b) GDPR). Storing information on your Mac and reading it
back is strictly necessary for these functions (§ 25(2) No. 2 TDDDG,
Art. 5(3) Directive 2002/58/EC). The provider has no access to this
data.

---

## 9. Third parties

**Storage providers.** Each storage provider you connect is a separate
controller for the data you store there. Their privacy policies apply.
The provider has no contract with them in connection with your use of
the App.

**Apple.** Apple distributes the App and processes the purchase of
Bucketeer Pro as an independent controller under its own privacy
policy (https://www.apple.com/legal/privacy/). In the EU/EEA, the
United Kingdom, Switzerland and Türkiye Apple sells in its own name,
elsewhere as the provider's agent. The provider receives sales and
payout reports from App Store Connect, not your payment details.

The provider does not sell or share personal data.

---

## 10. International transfers

The App transfers no data to the provider. Requests to your storage
endpoints may cross borders depending on the provider and region you
choose; that transfer is between you and your provider. If you write to
us, your message is processed by DigitalFreedom Global LLC in the
United States and by the helpdesk providers named in the helpdesk
privacy notice.

---

## 11. Retention

Data on your Mac stays until you delete it in the App, in Finder or in
Keychain Access, with these automatic limits: activity log 180 days,
trash entries after the retention period you set (default 30 days),
preview cache limited to 2 GiB. The provider holds no copy of any of
it. Support correspondence is kept as stated in the helpdesk privacy
notice.

---

## 12. Your rights

Wherever you live, you have at least the rights under the GDPR:
access (Art. 15), rectification (Art. 16), erasure (Art. 17),
restriction (Art. 18), data portability (Art. 20) and objection
(Art. 21).

Because the App sends nothing to the provider, these rights concern
only data you have sent us yourself, for example a support request.
For data stored with your storage provider or with Apple, contact them
directly.

To exercise your rights, write to data-protection@digitalfreedom.co.za
or use https://data-protection.digitalfreedom.co.za. We answer within
one month (Art. 12(3) GDPR), or within the shorter period your local
law prescribes.

**Complaints.** You can complain to a supervisory authority, in
particular in the country of your habitual residence, your place of
work or the place of the alleged infringement (Art. 77 GDPR). The
provider has no establishment in the EU, so there is no lead
supervisory authority. In the United Kingdom the authority is the
Information Commissioner's Office, in Switzerland the Federal Data
Protection and Information Commissioner.

**California.** The provider does not sell or share personal
information and does not use it for targeted advertising. California
residents have the rights to know, delete and correct and are not
discriminated against for using them.

---

## 13. Children

Bucketeer is a tool for managing cloud storage and is not directed at
children. The App collects no personal data for the provider and
therefore does not knowingly process personal data of children.

---

## 14. Security

- The App and its Finder extension run in the macOS App Sandbox.
- Credentials and the Keychain copy of encryption keys are kept in the
  macOS Keychain, only available while the Mac is unlocked and not
  synchronised via iCloud. They are not written to log files or shown
  in error messages. An optional key backup is stored only if you
  export it, as described in section 6.
- Connections to storage endpoints use TLS, except an endpoint address
  you enter yourself with http:// (see section 4). Requests are
  signed on your Mac (AWS Signature Version 4 or Azure Shared Key);
  the secret key itself is never sent.

No software is free of defects. Please report security issues to
security@digitalfreedom.co.za.

---

## 15. Changes

When this Policy changes, the effective date at the top changes and the
App Store release notes of the release concerned mention it.

---

## 16. Contact

DigitalFreedom Global LLC (trading as DigitalFreedom)
30 N Gould St, Ste N
Sheridan, WY 82801
United States

Data protection: data-protection@digitalfreedom.co.za
Data protection request form: https://data-protection.digitalfreedom.co.za
General inquiries: hello@digitalfreedom.co.za
Website: https://digitalfreedom.co.za

---

© 2026 DigitalFreedom Global LLC. All rights reserved.
