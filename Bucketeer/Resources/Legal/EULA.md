# END USER LICENSE AGREEMENT — Bucketeer for macOS

**Effective Date:** 24 May 2026
**Application:** Bucketeer for macOS (the "App")
**Publisher:**
DigitalFreedom — a brand of Berger & Rosenstock GbR
Dieselstr. 22e, 61231 Bad Nauheim, Germany
Contact: hello@digitalfreedom.co.za
Website: https://digitalfreedom.co.za

---

## 1. ACCEPTANCE

By installing or using Bucketeer, you agree to this End User License
Agreement (the "Agreement"). If you do not agree, do not install or use
the App.

This Agreement applies to the version of Bucketeer that you download
from the **Apple Mac App Store**. The App is not distributed through
any other channel (no Homebrew cask, no direct DMG download, no Google
Play, no enterprise distribution).

Apple's standard licensed-application end-user license agreement applies
to your use of the App in parallel with this Agreement. Where the two
conflict, the Apple terms govern only the matters Apple's terms
specifically address (App-Store sale, refunds, Family Sharing); this
Agreement governs everything else.

---

## 2. THE APP

Bucketeer is a native macOS application that lets you browse, transfer,
mount, and synchronise objects across S3-compatible providers and Azure
Blob Storage. It runs entirely on your Mac. The Publisher operates no
servers in connection with the App.

---

## 3. LICENSE GRANT

Subject to this Agreement, the Publisher grants you a personal,
non-exclusive, non-transferable, revocable license to install and use
Bucketeer on Mac devices you personally own or control, in accordance
with the Apple Media Services Terms.

Open-source components bundled with the App are governed by their own
licenses; see `OPEN_SOURCE_NOTICES.md` in the in-App **About** view.

---

## 4. PRICING AND IN-APP PURCHASE

Bucketeer is free to download from the Mac App Store and includes a
**14-day Pro trial** that activates on first launch and unlocks every
feature for the trial period. After the trial expires, the App stays
usable in a **Free tier** that retains the core browser (multi-account
browsing, upload, download, delete, rename, multipart transfers, Quick
Look preview, drag-and-drop).

The four **Bucketeer Pro pillars** — Mount as Drive (File Provider
extension), Sync Engine (copy / move / mirror jobs), cross-account
copy, and Menubar background mode — unlock with a single in-app
purchase:

| | |
|---|---|
| **Product** | Bucketeer Pro (Lifetime) |
| **Product ID** | `za.co.digitalfreedom.bucketeer.pro.lifetime` |
| **Price** | EUR 14.99 (or local equivalent set by Apple) |
| **Type** | One-time, non-consumable in-app purchase |
| **Family Sharing** | Enabled — a single purchase covers your Family Sharing group |
| **Subscription** | No subscription, no auto-renewal, no recurring charge |

The purchase is processed by Apple under the Apple Media Services
Terms. Refunds are handled exclusively by Apple via
`reportaproblem.apple.com`; the Publisher cannot process refunds
directly.

The Publisher reserves the right to change the price for new buyers in
future releases. A price change never affects an already-purchased
lifetime entitlement.

---

## 5. PERMITTED USE

You may:

- Install and run the App on any number of Macs you personally own,
  subject to Apple's Family Sharing rules.
- Connect the App to any S3-compatible endpoint or Azure Blob Storage
  account you are authorised to use.
- Upload, download, modify, and delete the objects you have
  authorisation to operate on at each connected endpoint.

---

## 6. RESTRICTIONS

You must not:

- Reverse-engineer, decompile, or disassemble the App except to the
  extent permitted by Section 69e of the German Copyright Act
  (Urheberrechtsgesetz) or other mandatory law.
- Circumvent the in-app purchase, the trial timer, or any other
  technical protection in the App.
- Use the App to connect to storage endpoints that you are not
  authorised to access. Bucketeer is a thin client: any access control
  is enforced by your provider, not by the Publisher.
- Use the App's name, icon, or branding to imply endorsement of, or
  affiliation with, derivative works.
- Use the App in violation of export-control or sanctions laws.

The App's source code is published under the separate
**Source-Available License** in `LICENSE.md`; redistribution rights for
the source are governed there.

---

## 7. YOUR RESPONSIBILITIES

Bucketeer acts on your behalf against the storage endpoints you
configure. You are responsible for:

- The validity, scope, and storage of the credentials you enter. The
  App stores credentials in your macOS Keychain and never transmits
  them anywhere except as part of authenticated requests to the
  endpoint you configured for that account.
- The objects you upload, download, modify, or delete via the App.
  Delete and Rename are destructive and effectively immediate against
  most providers. Mirror Sync with delete-propagation enabled will
  delete destination objects that are missing from the source.
- The costs your provider bills you for storage, requests, and egress
  bandwidth consumed via the App. Bucketeer makes no attempt to
  estimate or cap these costs.
- Backups of any data you store via the App.

---

## 8. THIRD-PARTY STORAGE ENDPOINTS

Bucketeer connects only to the S3-compatible endpoints or Azure Blob
Storage accounts you yourself configure. Each provider is a separate
operator with its own terms and privacy policy. The Publisher:

- has no agreement with, and no control over, the operators of those
  endpoints;
- is not responsible for their availability, performance, charging,
  data-handling, or security;
- cannot read your credentials, your bucket/container listings, or
  your file contents.

Disputes about provider behaviour, billing, or data-handling are
between you and the relevant provider.

---

## 9. DATA AND PRIVACY

The App processes data exclusively on your Mac and against the
endpoints you configure. The Publisher does not collect, transmit, or
receive any of your data. See the separate **Privacy Policy** for the
full statement.

---

## 10. UPDATES

The App may receive updates via the Mac App Store. Updates are subject
to this Agreement. Where an update materially changes paid features,
the Publisher will note the change in the App Store release notes.

---

## 11. WARRANTY DISCLAIMER

TO THE MAXIMUM EXTENT PERMITTED BY LAW, THE APP IS PROVIDED "AS IS" AND
"AS AVAILABLE" WITHOUT WARRANTY OF ANY KIND. THE PUBLISHER SPECIFICALLY
DISCLAIMS THE IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
PARTICULAR PURPOSE, AND NON-INFRINGEMENT. THE PUBLISHER DOES NOT
WARRANT THAT THE APP WILL BE UNINTERRUPTED, ERROR-FREE, OR SECURE.

This Section does not exclude warranties or rights that cannot be
excluded under mandatory consumer law. Statutory rights of consumers
under European Union law and the laws of the user's country of
residence remain unaffected.

---

## 12. LIABILITY

The Publisher's liability for damages, except for damages caused
intentionally or by gross negligence, for damages from injury to life,
body, or health, and for liability under the German Product Liability
Act (Produkthaftungsgesetz), is limited to:

- damages typical and foreseeable for an app of this kind; and
- in aggregate, the amount you paid for the Bucketeer Pro in-app
  purchase, or EUR 14.99 if you have not made that purchase.

The Publisher is not liable for:

- loss of data, profits, or business opportunities arising out of your
  use of the App;
- damage caused by third-party storage providers, including outages,
  account suspensions, or data loss at the provider's end;
- damage caused by your own loss of, or mismanagement of, your
  credentials.

---

## 13. NOT FOR HIGH-RISK USE

Bucketeer is a general-purpose object-storage browser. It must not be
used as a component of medical, life-support, safety-critical
industrial, nuclear-control, aviation-control, or military-critical
systems. Such use is at your sole risk.

---

## 14. TERMINATION

This Agreement applies for as long as you have the App installed. You
may terminate it at any time by deleting the App. The Publisher may
terminate this Agreement with immediate effect if you materially breach
its terms. On termination you must stop using the App and delete it.

The Bucketeer Pro lifetime entitlement, once purchased, survives
termination of this Agreement only insofar as Apple's Media Services
Terms preserve your purchase record; the Publisher cannot restore an
entitlement Apple has revoked.

---

## 15. GOVERNING LAW AND JURISDICTION

This Agreement is governed by the laws of the Federal Republic of
Germany, excluding the conflict-of-laws rules. The UN Convention on
Contracts for the International Sale of Goods (CISG) does not apply.

For consumers domiciled in the European Union, mandatory consumer-
protection law of their country of residence remains unaffected.

The European Commission's Online Dispute Resolution (ODR) platform is
reachable at `https://ec.europa.eu/consumers/odr`. The Publisher is
neither obliged nor willing to participate in consumer dispute-
resolution proceedings before a Verbraucherschlichtungsstelle under
the German VSBG.

---

## 16. CHANGES TO THIS AGREEMENT

Material changes to this Agreement will be reflected in a new
"Effective Date" at the top of this document and announced in the App
Store release notes for the release that introduces them. Continued use
of the App after the Effective Date of the new version constitutes
acceptance of the changed terms.

---

## 17. CONTACT

Berger & Rosenstock GbR (DigitalFreedom)
Dieselstr. 22e
61231 Bad Nauheim, Germany

Email: hello@digitalfreedom.co.za
Privacy contact: data-protection@digitalfreedom.co.za

---

(c) 2026 DigitalFreedom — Berger & Rosenstock GbR. All rights reserved.
