# Export-Compliance — Bucketeer

US export controls (EAR, 15 CFR Parts 730–774) require every app
that contains, accesses, implements, or incorporates cryptography
to be classified before worldwide App Store distribution.
Bucketeer's `Info.plist` declares:

```
ITSAppUsesNonExemptEncryption = NO
```

This document records the classification reasoning, why the key is
`NO` for v1.0, and the exact App Store Connect answers, so the
position is consistent across the plist, the submission
questionnaire, and any App Review or BIS follow-up.

> **Status:** engineering self-assessment, decided by the owner for
> v1.0. Have counsel confirm before first submission — the
> declaration is the developer's legal responsibility, not Apple's.

---

## Provider and exporter

**DigitalFreedom Global LLC** (Wyoming, USA) publishes Bucketeer on
the Mac App Store and is the exporter of record for the EAR
classification below.

## What encryption does Bucketeer use?

| Surface | Mechanism | Source |
|---|---|---|
| Transport to Azure | TLS 1.2+ | Apple URLSession |
| Transport to S3 | TLS 1.2+ | Soto SotoS3 → AsyncHTTPClient (swift-nio). Its dependency swift-nio-ssl vendors **BoringSSL**, which is linked into both the host app and the File Provider extension (`CNIOBoringSSL` symbols, verified with `nm` on the 2026-11-02 Debug build). Which TLS stack serves a given connection at runtime is not documented here. |
| Credentials at rest | macOS Keychain | Apple Security framework |
| BYOK at-rest object encryption (Phase 13.15) | AES-256-GCM | Apple CryptoKit (`AES.GCM.seal` / `.open`, `SymmetricKey(size: .bits256)`) |
| Key backup files | PBKDF2-HMAC-SHA256 + AES-256-GCM | Apple CommonCrypto, CryptoKit and Security (random salt/nonce) |
| Request signing (Azure SharedKey / SAS) | HMAC-SHA256 | Apple CryptoKit |
| Hash for resumable-upload fingerprints | SHA-256 | Apple CryptoKit (`SHA256`) |
| Hash for the cross-account temp manifest | SHA-256 | Apple CryptoKit |

Every algorithm is a **standard symmetric cipher, MAC, or hash**, and PBKDF2 is a standard KDF.
The app's own encryption, signing and hashing use Apple CryptoKit and CommonCrypto;
the one bundled third-party cryptographic implementation is BoringSSL
inside swift-nio-ssl (transitive dependency of Soto, see table). It
implements standard TLS only. There is no proprietary cryptography,
no key-escrow scheme, and no certificate-issuing capability.

## US classification (EAR)

**ECCN 5D992.c — mass-market encryption software**, self-classified
per the Cryptography Note (Note 3 to Category 5, Part 2) and
License Exception ENC, 15 CFR §740.17(b)(1).

The client-side encryption of Phase 13.15 is general-purpose
confidentiality encryption of user file contents, so Bucketeer is not
outside the EAR's encryption controls. It is released as mass market:

1. **Generally available to the public** — sold without
   restriction on the Mac App Store at a published price.
2. **User-installable without supplier support** — self-installs
   from the App Store; no MDM, no field engineering.
3. **Cryptographic functionality cannot easily be changed by the
   user** and is **fully described** — fixed AES-256-GCM envelope
   documented in this file, `CHANGELOG.md` (13.15),
   `docs/KEY_BACKUP_FORMAT.md`, and the
   `BucketeerEnvelope` / `ObjectEncryptor` source comments (cipher,
   256-bit key, 96-bit nonce, AAD header, user-held key custody).

Consequences of the §740.17(b)(1) mass-market self-classification:

- **No CCATS** — no classification request to BIS is needed.
- **No annual self-classification report.** Since the BIS rule of
  29 March 2021 (86 FR 16482) the report under Supp. No. 8 to
  Part 742 is only required for the mass-market components, toolsets
  and chips listed in §740.17(b)(1); an end-user app like Bucketeer
  is not among them.

The source-available publication of the encryption implementation
(see `LICENSE`) supports prong 3 but is **not** relied on as a
§742.15(b) published-source carve-out — that route would require a
formal email notification to BIS and the ENC Encryption Request
Coordinator, which has not been made.

## Why `ITSAppUsesNonExemptEncryption = NO`

Apple's export-compliance questionnaire asks for documentation only
where it is legally required. With the US position settled by the
mass-market self-classification above, the remaining document Apple
collects is the French import declaration (ANSSI). Bucketeer v1.0
is **not offered in France**: the App Store availability in App Store
Connect excludes France. Per Apple's documentation the app is then
exempt from providing documentation, and the key is `NO`. App Store
Connect stops asking the questionnaire for each build.

The key is a statement about documentation duties for the chosen
storefronts, not a claim that Bucketeer contains no encryption. The
inventory above stays accurate and complete.

## App Store Connect checklist (v1.0)

- Pricing and Availability: **France deselected**. Keep it that way
  for every version while the key is `NO`.
- No `ITSEncryptionExportComplianceCode` in the plist.
- If App Review asks: 5D992.c mass market, self-classified under
  §740.17(b)(1), no CCATS, no annual report owed, not distributed in
  France.

## If France is added later

1. File the ANSSI declaration for the encryption functions listed
   above and wait for the acknowledgement.
2. Upload the ANSSI documentation in App Store Connect (App
   Information → App Encryption Documentation) and wait for approval.
3. Set `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = YES` and add
   `ITSEncryptionExportComplianceCode` with the key App Store Connect
   issues.
4. Only then add France to the availability.

## Operational reminders

- Re-evaluate whenever Bucketeer adds a new cryptographic surface
  (non-Apple cipher, custom protocol, hardware-key crypto, central
  key escrow). Any of those can break the mass-market posture.
- The classification applies per major version. v1.0 → v1.x
  carries this assessment unchanged; v2.0 with enterprise
  provisioning / managed key roll-forward needs re-classification.
- Before the first submission, have a lawyer confirm both the
  5D992.c self-classification and the France exclusion as the basis
  for `NO`.

## References

- 15 CFR §740.17 (License Exception ENC) — https://www.ecfr.gov/current/title-15/subtitle-B/chapter-VII/subchapter-C/part-740/section-740.17
- 15 CFR Part 742, Supp. No. 8 (self-classification report format) — https://www.ecfr.gov/current/title-15/subtitle-B/chapter-VII/subchapter-C/part-742
- 86 FR 16482 (29 March 2021), BIS rule removing the mass-market
  self-classification report for most items —
  https://www.federalregister.gov/citation/86-FR-16482
- Apple — *Determine your export compliance requirements* —
  https://developer.apple.com/help/app-store-connect/manage-app-and-version-information/determine-your-export-compliance-requirements
- Apple — *Complying with encryption export regulations* —
  https://developer.apple.com/documentation/security/complying_with_encryption_export_regulations
