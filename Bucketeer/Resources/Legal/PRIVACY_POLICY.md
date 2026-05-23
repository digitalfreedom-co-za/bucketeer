# PRIVACY POLICY

## Bucketeer — Data Protection and Privacy Notice

**Effective Date:** May 2026
**Application:** Bucketeer for macOS
**Publisher:** DigitalFreedom — a brand of Berger & Rosenstock GbR

---

## 1. SUMMARY

**Bucketeer does not collect, store, transmit, or process any personal
data on behalf of its publisher.** The App runs entirely on your Mac, talks
directly to the S3-compatible endpoints you configure, and keeps your
credentials in your local macOS Keychain.

The Publisher operates no servers in connection with this App. There is no
account system, no telemetry, no analytics, no crash reporting, and no
advertising. The Publisher cannot read your credentials, your file
listings, or your file contents.

---

## 2. DATA CONTROLLER

The legal entity responsible for processing personal data ("data
controller" under Art. 4(7) GDPR), to the extent there is any, is:

Berger & Rosenstock GbR (trading as DigitalFreedom)
Dieselstr. 22e
61231 Bad Nauheim
Germany

Authorized Representatives: Marcel R. G. Berger, Jasmin Rosenstock
VAT-ID: DE455096022

For data protection inquiries: data-protection@digitalfreedom.co.za
General contact: hello@digitalfreedom.co.za
Website: https://digitalfreedom.co.za

---

## 3. DATA THE APP HANDLES

### 3.1 Data You Provide to the App (stored locally only)

| Data | Where it is stored | Why |
|---|---|---|
| Account name (label) | SwiftData store in your App Group container | So you can identify accounts in the sidebar |
| Provider, region, endpoint URL, account ID, default bucket, path-style flag | SwiftData store in your App Group container | So the App can connect to your S3 endpoint |
| Access key, secret key, optional session token | **macOS Keychain** (access group, sandboxed) | So the App can sign S3 requests on your behalf |
| Sync job definitions (source/destination, schedule, options) | SwiftData store in your App Group container | So scheduled sync jobs can run |

None of this data is transmitted to the Publisher or to any third party
that is not the S3 endpoint you yourself configured.

### 3.2 Data the App Reads from Your S3 Endpoints

When you use the App, it sends standard S3 API requests (`ListBuckets`,
`ListObjectsV2`, `GetObject`, `PutObject`, `DeleteObject`, `CopyObject`,
`HeadObject`) to the endpoint URL configured for each account. The
responses — bucket names, object keys, metadata, file contents — are held
in memory and, for downloads and previews, written to disk in the App's
sandbox container (specifically the temporary directory for previews and
the location you select for downloads).

The Publisher has no visibility into, and no control over, the data that
flows between your Mac and your S3 endpoint. Each S3 provider you connect
to is a separate data controller with its own privacy policy.

### 3.3 Data the App Does NOT Collect

The App does **not** collect, transmit, store, or process:

- Personal identifiers (name, email, phone, address)
- Device identifiers (advertising ID, IDFV, IDFA, hardware UUID)
- Usage analytics, telemetry, or product-interaction data
- Crash reports or diagnostic data sent to the Publisher
- Location data
- Camera, microphone, photo library, or contacts data
- Browsing history beyond what is shown in the App's own bucket listings
- Any data for advertising or marketing purposes

---

## 4. LEGAL BASIS (GDPR Art. 6)

Where the App processes personal data locally on your Mac (e.g. holds your
S3 access keys in the Keychain so it can sign requests), the legal basis
is **Art. 6(1)(b) GDPR** — performance of a contract (this EULA) at your
request — and **Art. 6(1)(f) GDPR** — the legitimate interest of providing
you with the requested functionality. No data leaves your Mac as a result
of this processing, except API requests to the S3 endpoint **you**
configured.

---

## 5. THIRD-PARTY SERVICES

### 5.1 S3 Endpoints You Configure

When you add an account, you point the App at a service provider you
choose: AWS, Cloudflare, Backblaze, Wasabi, DigitalOcean, Civo, Storj,
MinIO, or your own server. Each of those providers is a separate data
controller. The App's role is limited to acting on your instructions as
a client. We provide no contractual or technical link between any of
these providers and the Publisher.

For the privacy policy of the provider you choose, see that provider's
own documentation. Your S3 endpoint receives the standard fields of an
S3 request (signing material derived from your access key, the request
URL, HTTP headers, and any payload you upload).

### 5.2 Apple App Store

Apple distributes the App and, in connection with that distribution,
processes its own data (purchase, download, crash data). Apple's
processing is governed by Apple's privacy policies. See
<https://www.apple.com/legal/privacy/>.

### 5.3 No Other Third Parties

The App contains no advertising SDKs, no analytics SDKs, no crash
reporting SDKs, and no other third-party services that transmit data off
your device.

---

## 6. INTERNATIONAL TRANSFERS

The Publisher does not transfer your data internationally because the
Publisher does not receive your data in the first place.

S3 traffic generated by the App may cross international boundaries
depending on which endpoint you configure. That transfer is between you
and your S3 provider; the Publisher is not a party to it.

---

## 7. RETENTION

- Account metadata and credentials persist on your Mac until you delete
  the account inside the App or uninstall the App.
- Downloaded files persist at the location you chose to save them.
- The preview cache is bounded at 2 GB and rotated automatically; it is
  also cleared whenever you uninstall the App.
- Uninstalling the App removes all data the App stored in its sandbox
  container, in the App Group container, and in the Keychain access
  group it owns.

---

## 8. YOUR RIGHTS UNDER GDPR

Because the Publisher does not hold any of your personal data, the
classical GDPR data-subject rights (access, rectification, erasure,
portability, restriction, objection — Articles 15 to 22 GDPR) have
nothing to act on at the Publisher's end. You retain full control of
the data the App handles on your own Mac through normal Mac and App
controls (deleting accounts in the App, removing files in Finder,
uninstalling the App, clearing the Keychain entries).

For data held by your S3 provider, please exercise those rights with
that provider directly.

For data held by Apple in connection with App Store distribution, please
exercise those rights with Apple directly.

If you nevertheless have any privacy-related question, please contact
data-protection@digitalfreedom.co.za. The Publisher will respond within
one month (Art. 12(3) GDPR).

You also have the right to lodge a complaint with a supervisory
authority. The Publisher's lead authority is:

Der Hessische Beauftragte für Datenschutz und Informationsfreiheit
Postfach 3163, 65021 Wiesbaden, Germany
<https://datenschutz.hessen.de/>

---

## 9. CHILDREN

The App is a developer tool. It is not directed at children under 16 and
is rated 17+ on the App Store. The App does not collect any personal data
and so does not knowingly process personal data of children.

---

## 10. SECURITY

The App is sandboxed by macOS and runs with the hardened runtime enabled.
Credentials are stored in the macOS Keychain with `kSecAttrAccessible
= kSecAttrAccessibleWhenUnlocked` and are never written to disk in
plaintext, never logged, and never displayed in error messages. Network
connections to S3 endpoints use TLS 1.2 or higher; Apple's Application
Transport Security default policy is enforced without exceptions.

The Publisher operates no servers in connection with this App; therefore
there is no server-side security boundary to maintain.

---

## 11. CHANGES TO THIS POLICY

Material changes to this Policy will be reflected in a new "Effective
Date" at the top and will be communicated in App release notes for the
release that introduces the change.

---

## 12. JURISDICTION-SPECIFIC ADDENDA

Where the App is downloaded from an App Store in a jurisdiction whose
data-protection law adds rights or obligations beyond the GDPR baseline
applied above, those local rights apply additionally. Specifically:

- **California (CCPA/CPRA):** the App sells, shares, and discloses no
  personal information. Categories of personal information collected:
  none. Right to opt-out of "sale" / "share": not applicable.
- **Brazil (LGPD):** the Publisher acts in no role under Art. 5 LGPD in
  respect of this App's local operation.
- **South Africa (POPIA):** the App's operation does not engage the
  Publisher as a "responsible party" under POPIA.
- **India (DPDP Act):** the App's operation does not engage the Publisher
  as a "Data Fiduciary" under the DPDP Act.
- **Japan (APPI), South Korea (PIPA), Australian Privacy Act:** no
  personal information is collected by the Publisher.

If your local regime nevertheless creates obligations, please contact
data-protection@digitalfreedom.co.za and the Publisher will respond
within the time required by your local law.

---

## 13. CONTACT

Data protection: data-protection@digitalfreedom.co.za
General contact: hello@digitalfreedom.co.za

Postal address:
Berger & Rosenstock GbR
Dieselstr. 22e
61231 Bad Nauheim
Germany

---

(c) 2026 DigitalFreedom — Berger & Rosenstock GbR. All rights reserved.
