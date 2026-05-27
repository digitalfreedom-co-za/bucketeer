# Export-Compliance — Bucketeer

US export controls require every app that contains, accesses,
implements, or incorporates cryptography to be classified
before it can be distributed worldwide via the App Store.
Bucketeer's `Info.plist` declares:

```
ITSAppUsesNonExemptEncryption = NO
```

This document records the legal reasoning for that declaration
so the answer is ready-to-paste if Apple's App Review or BIS
ever ask.

---

## What encryption does Bucketeer use?

| Surface | Mechanism | Source |
|---|---|---|
| Transport to S3 / Azure | TLS 1.2+ via URLSession + Soto | Apple URLSession, Soto SotoS3 |
| Credentials at rest | macOS Keychain | Apple Security framework |
| BYOK at-rest object encryption (Phase 13.15) | AES-256-GCM | Apple CryptoKit (`AES.GCM.seal` / `.open`, `SymmetricKey(size: .bits256)`) |
| Hash for resumable-upload fingerprints | SHA-256 | Apple CryptoKit (`SHA256`) |
| Hash for the cross-account temp manifest | SHA-256 | Apple CryptoKit |

Every algorithm is a **standard symmetric cipher or hash**
shipped by Apple. There is no proprietary cryptography in the
codebase, no third-party crypto library, no key-escrow scheme,
and no certificate-issuing capability.

## Why ITSAppUsesNonExemptEncryption = NO

The declaration is governed by **15 CFR §740.17 (License
Exception ENC)**. Under §740.17(b)(1) — "Mass-market products":

> Certain mass-market commodities, software, and components are
> released from "EI" controls when the product:
> (i) generally is available to the public by being sold,
> without restriction, from stock at retail selling points by any
> of these means: over-the-counter, mail-order, electronic, or
> telephone-order transactions;
> (ii) is designed for installation by the user without further
> substantial support from the supplier; and
> (iii) employs encryption that is fully described in the
> applicable documentation.

Bucketeer meets all three prongs:

1. **Mass-market / retail.** Distributed exclusively via the
   Apple Mac App Store at a published price, available to any
   consumer with an Apple ID. No usage gating, no enterprise
   licensing, no controlled distribution channel.
2. **User-installable without supplier support.** The app
   self-installs from the App Store; there is no installer
   intermediary, no enterprise MDM requirement, no field-
   engineering touch.
3. **Encryption fully described.** This document, the README
   ("Phase 13.15 — Client-Side Encryption per bucket"), the
   `CHANGELOG.md` entry for 13.15, and the inline comments on
   `BucketeerEnvelope.swift` + `ObjectEncryptor.swift`
   collectively document the cipher (AES-GCM), the key length
   (256 bits), the nonce length (96 bits), the AAD (the
   8-byte authenticated header), the key custody model (user
   supplies, stored in macOS Keychain, never transmitted), and
   the failure modes.

In addition, the **publicly available source code** prong of
§740.17(b)(3) independently applies: Bucketeer is published under
a Source-Available License from day one (see `LICENSE`); every
byte of the encryption implementation is auditable.

## Why this avoids the BIS Annual Self-Classification Report

The Annual Self-Classification Report is required for items
**classified under ECCN 5D992.c** that fall outside §740.17(b)(1).
Because Bucketeer fully qualifies for the mass-market exemption
above, no report is owed. (The previous owner of this rule —
the now-replaced "Encryption Registration" — was eliminated in
the 2020 BIS rule update; the only continuing obligation for
mass-market crypto items is the §740.17(b)(1) self-assessment
documented in this file.)

## Operational reminders

- Re-evaluate this classification whenever Bucketeer adds a new
  cryptographic surface (e.g. a non-Apple cipher, a custom
  protocol, a hardware-key gate that *itself* performs crypto,
  or a centrally-managed key-escrow service). Any of those would
  invalidate the §740.17(b)(1) mass-market posture.
- The classification applies per major version. v1.0 → v1.x
  carries this assessment unchanged. v2.0 — if it adds enterprise
  features like SSO-gated provisioning, managed key roll-forward,
  or cross-tenant migration — needs to be re-classified before
  submission.
- If Apple App Review questions the `NO` declaration, paste this
  document into the response and reference §740.17(b)(1) directly.
  Apple's reviewers do not adjudicate EAR; they verify that the
  developer has answered the export-compliance question
  *consistently with their published classification*.

## References

- 15 CFR §740.17 (License Exception ENC) — https://www.ecfr.gov/current/title-15/subtitle-B/chapter-VII/subchapter-C/part-740/section-740.17
- Apple — *Determine your export compliance requirements* —
  https://developer.apple.com/help/app-store-connect/manage-app-and-version-information/determine-your-export-compliance-requirements
- Apple — *Complying with encryption export regulations* —
  https://developer.apple.com/documentation/security/complying_with_encryption_export_regulations
