# End User License Agreement

*The terms under which you may install and use Bucketeer for macOS.*

**Application** — Bucketeer for macOS (the "App")
**Publisher** — DigitalFreedom · Berger & Rosenstock GbR · Dieselstr. 22e · 61231 Bad Nauheim · Germany
**Contact** — hello@digitalfreedom.co.za
**Effective date** — 24 May 2026

---

## 1. Acceptance

By installing or using Bucketeer you agree to this End User License
Agreement (the "Agreement"). If you do not agree, do not install or use
the App.

This Agreement applies to the version of Bucketeer that you download
from the **Apple Mac App Store**. The App is not distributed through
any other channel — no Homebrew cask, no direct DMG, no enterprise
distribution.

Apple's standard licensed-application end-user license agreement
applies in parallel. Where the two conflict, the Apple terms govern
only the matters they specifically address (the App Store sale itself,
refunds, Family Sharing); this Agreement governs everything else.

---

## 2. The App

Bucketeer is a native macOS application that lets you browse,
transfer, mount, and synchronise objects across S3-compatible
providers and Azure Blob Storage. It runs entirely on your Mac. The
Publisher operates **no servers** in connection with the App.

---

## 3. License grant

Subject to this Agreement, the Publisher grants you a personal,
non-exclusive, non-transferable, revocable license to install and use
Bucketeer on Mac devices you personally own or control, in accordance
with the Apple Media Services Terms.

Open-source components bundled with the App are governed by their own
licenses. See **Open Source Notices** in the in-app **About** view.

---

## 4. Pricing and in-app purchase

Bucketeer is free to download from the Mac App Store and ships with a
**14-day Pro trial** that activates on first launch and unlocks every
feature for the trial period. After the trial expires the App keeps
working in a **Free tier** that retains the core browser: multi-
account browsing, upload, download, delete, rename, multipart
transfers, Quick Look preview, drag-and-drop.

The four **Bucketeer Pro pillars** — Mount as Drive (File Provider
extension), Sync Engine (copy / move / mirror jobs), cross-account
copy, and Menubar background mode — unlock with a single in-app
purchase.

**Product** — Bucketeer Pro (Lifetime)
**Product ID** — `za.co.digitalfreedom.bucketeer.pro.lifetime`
**Price** — EUR 14.99 (or the local equivalent set by Apple)
**Type** — One-time, non-consumable in-app purchase
**Family Sharing** — Enabled; one purchase covers your group
**Subscription** — None; no auto-renewal; no recurring charge

The purchase is processed by Apple under the Apple Media Services
Terms. Refunds are handled exclusively by Apple via
`reportaproblem.apple.com`; the Publisher cannot process refunds
directly.

The Publisher may change the price for new buyers in future releases.
A price change never affects an already-purchased lifetime
entitlement.

---

## 5. Permitted use

You may:

- Install and run the App on any number of Macs you personally own,
  subject to Apple's Family Sharing rules.
- Connect the App to any S3-compatible endpoint or Azure Blob Storage
  account you are authorised to use.
- Upload, download, modify, and delete the objects you have
  authorisation to operate on at each connected endpoint.

---

## 6. Restrictions

You must not:

- Reverse-engineer, decompile, or disassemble the App except to the
  extent permitted by §69e UrhG (German Copyright Act) or other
  mandatory law.
- Circumvent the in-app purchase, the trial timer, or any other
  technical protection in the App.
- Use the App to connect to storage endpoints you are not authorised
  to access. Bucketeer is a thin client — access control is enforced
  by your provider, not by the Publisher.
- Use the App's name, icon, or branding in a way that implies
  endorsement of, or affiliation with, derivative works.
- Use the App in violation of export-control or sanctions law.

The App's source code is published under the separate
**Source-Available License** (see **License** in the in-app About
view). Redistribution rights for the source are governed there.

---

## 7. Your responsibilities

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
  estimate or cap these costs — the **Bandwidth limit** setting only
  governs throughput, not provider-side charges.
- Backups of any data you store via the App.

---

## 8. Third-party storage endpoints

Bucketeer connects only to the S3-compatible endpoints or Azure Blob
Storage accounts you yourself configure. Each provider is a separate
operator with its own terms and privacy policy. The Publisher:

- has no agreement with, and no control over, the operators of those
  endpoints;
- is not responsible for their availability, performance, charging,
  data-handling, or security;
- cannot read your credentials, your bucket / container listings, or
  your file contents.

Disputes about provider behaviour, billing, or data-handling are
between you and the relevant provider.

---

## 9. Data and privacy

The App processes data exclusively on your Mac and against the
endpoints you configure. The Publisher does not collect, transmit, or
receive any of your data. See the separate **Privacy Policy** for the
full statement.

---

## 10. Updates

The App may receive updates via the Mac App Store. Updates are
subject to this Agreement. Where an update materially changes paid
features, the Publisher will note the change in the App Store release
notes.

---

## 11. Warranty disclaimer

To the maximum extent permitted by law, the App is provided **"as is"
and "as available"** without warranty of any kind. The Publisher
specifically disclaims the implied warranties of merchantability,
fitness for a particular purpose, and non-infringement. The Publisher
does not warrant that the App will be uninterrupted, error-free, or
secure.

This Section does not exclude warranties or rights that cannot be
excluded under mandatory consumer law. Statutory rights of consumers
under European Union law and the laws of the user's country of
residence remain unaffected.

---

## 12. Liability

The Publisher's liability for damages — except for damages caused
intentionally or by gross negligence, damages from injury to life,
body, or health, and liability under the German Product Liability Act
(Produkthaftungsgesetz) — is limited to:

- damages typical and foreseeable for an app of this kind; and
- in aggregate, the amount you paid for the Bucketeer Pro in-app
  purchase, or EUR 14.99 if you have not made that purchase.

The Publisher is not liable for:

- loss of data, profits, or business opportunities arising out of your
  use of the App;
- damage caused by third-party storage providers, including outages,
  account suspensions, or data loss at the provider's end;
- damage caused by your own loss or mismanagement of credentials.

---

## 13. Not for high-risk use

Bucketeer is a general-purpose object-storage browser. It must **not**
be used as a component of medical, life-support, safety-critical
industrial, nuclear-control, aviation-control, or military-critical
systems. Such use is at your sole risk.

---

## 14. Termination

This Agreement applies for as long as you have the App installed. You
may terminate it at any time by deleting the App. The Publisher may
terminate this Agreement with immediate effect if you materially
breach its terms. On termination you must stop using the App and
delete it.

The Bucketeer Pro lifetime entitlement, once purchased, survives
termination of this Agreement only insofar as Apple's Media Services
Terms preserve your purchase record; the Publisher cannot restore an
entitlement Apple has revoked.

---

## 15. Governing law and jurisdiction

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

## 16. Changes to this Agreement

Material changes are reflected in a new **Effective date** at the top
of this document and announced in the App Store release notes for the
release that introduces them. Continued use of the App after the
Effective date of the new version constitutes acceptance of the
changed terms.

---

## 17. Contact

Berger & Rosenstock GbR (DigitalFreedom)
Dieselstr. 22e · 61231 Bad Nauheim · Germany
Email: hello@digitalfreedom.co.za
Privacy contact: data-protection@digitalfreedom.co.za

---

© 2026 DigitalFreedom · Berger & Rosenstock GbR · All rights reserved.
