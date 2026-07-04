# Export-Compliance — Bucketeer

US export controls (EAR, 15 CFR Parts 730–774) require every app
that contains, accesses, implements, or incorporates cryptography
to be classified before worldwide App Store distribution.
Bucketeer's `Info.plist` declares:

```
ITSAppUsesNonExemptEncryption = YES
```

This document records the classification reasoning and the exact
App Store Connect answers, so the position is consistent across
the plist, the submission questionnaire, and any App Review or
BIS follow-up.

> **Status:** engineering self-assessment. The classification
> follows the standard mass-market self-classification path used
> by comparable apps (client-side-encryption file tools, password
> managers). Have counsel confirm before first submission if in
> doubt — the declaration is the developer's legal responsibility,
> not Apple's.

---

## What encryption does Bucketeer use?

| Surface | Mechanism | Source |
|---|---|---|
| Transport to S3 / Azure | TLS 1.2+ via URLSession + Soto | Apple URLSession, Soto SotoS3 |
| Credentials at rest | macOS Keychain | Apple Security framework |
| BYOK at-rest object encryption (Phase 13.15) | AES-256-GCM | Apple CryptoKit (`AES.GCM.seal` / `.open`, `SymmetricKey(size: .bits256)`) |
| Request signing (Azure SharedKey / SAS) | HMAC-SHA256 | Apple CryptoKit |
| Hash for resumable-upload fingerprints | SHA-256 | Apple CryptoKit (`SHA256`) |
| Hash for the cross-account temp manifest | SHA-256 | Apple CryptoKit |

Every algorithm is a **standard symmetric cipher, MAC, or hash**
shipped by Apple. There is no proprietary cryptography, no
third-party crypto library, no key-escrow scheme, and no
certificate-issuing capability.

## Classification

**ECCN 5D992.c — mass-market encryption software**, self-classified
per the Cryptography Note (Note 3 to Category 5, Part 2) and
License Exception ENC, 15 CFR §740.17(b)(1).

Why not "exempt" (`ITSAppUsesNonExemptEncryption = NO`): the
`NO` answer is reserved for apps that use **no** encryption or
only encryption within Apple's exemption categories (encryption
limited to authentication, digital signatures, DRM, OS-provided
HTTPS calls only, banking/medical uses, etc.). Bucketeer's Phase
13.15 feature performs **general-purpose confidentiality
encryption of arbitrary user file contents** (AES-256-GCM on
object bodies). That is squarely non-exempt functionality, so the
honest plist answer is `YES` — followed by the mass-market
self-classification, which removes the need for a CCATS/license
but not the need to answer `YES`.

Mass-market prongs (Cryptography Note), all met:

1. **Generally available to the public** — sold without
   restriction on the Mac App Store at a published price.
2. **User-installable without supplier support** — self-installs
   from the App Store; no MDM, no field engineering.
3. **Cryptographic functionality cannot easily be changed by the
   user** and is **fully described** — fixed AES-256-GCM envelope
   documented in this file, `CHANGELOG.md` (13.15), and the
   `BucketeerEnvelope` / `ObjectEncryptor` source comments (cipher,
   256-bit key, 96-bit nonce, AAD header, user-held key custody).

The source-available publication of the encryption implementation
(see `LICENSE`) supports prong 3 but is **not** relied on as a
§742.15(b) published-source carve-out — that route would require a
formal email notification to BIS and the ENC Encryption Request
Coordinator, which has not been made.

## Continuing obligations

- **Annual self-classification report.** Self-classification under
  §740.17(b)(1) carries the annual report duty (§740.17(e)(3),
  Supp. No. 8 to Part 742): a CSV naming the product, ECCN
  5D992.c, and authorization type "ENC", emailed to
  `crypt-supp8@bis.doc.gov` and `enc@nsa.gov` by **February 1**
  covering the prior calendar year. First report is due the
  February after the first public release.
- **App Store Connect questionnaire** (per version, or answered
  once via plist keys):
  - "Does your app use encryption?" → **Yes**
  - "Does your app qualify for any of the exemptions?" → **No**
  - "Does your app implement any encryption algorithms that are
    proprietary or not accepted as standard?" → **No**
  - "Is your app going to be available in France?" → follow the
    questionnaire; standard mass-market apps upload the France
    import declaration only if prompted.
- Once App Store Connect issues an export-compliance key, add
  `ITSEncryptionExportComplianceCode` to the Info.plist so
  TestFlight builds skip the per-build questionnaire.

## Operational reminders

- Re-evaluate whenever Bucketeer adds a new cryptographic surface
  (non-Apple cipher, custom protocol, hardware-key crypto, central
  key escrow). Any of those can break the mass-market posture.
- The classification applies per major version. v1.0 → v1.x
  carries this assessment unchanged; v2.0 with enterprise
  provisioning / managed key roll-forward needs re-classification.
- If App Review questions the declaration, answer with the
  classification above (5D992.c mass-market, §740.17(b)(1),
  annual self-classification report filed). Apple's reviewers
  verify consistency, not the EAR analysis itself.

## References

- 15 CFR §740.17 (License Exception ENC) — https://www.ecfr.gov/current/title-15/subtitle-B/chapter-VII/subchapter-C/part-740/section-740.17
- 15 CFR Part 742, Supp. No. 8 (self-classification report format) — https://www.ecfr.gov/current/title-15/subtitle-B/chapter-VII/subchapter-C/part-742
- Apple — *Determine your export compliance requirements* —
  https://developer.apple.com/help/app-store-connect/manage-app-and-version-information/determine-your-export-compliance-requirements
- Apple — *Complying with encryption export regulations* —
  https://developer.apple.com/documentation/security/complying_with_encryption_export_regulations
