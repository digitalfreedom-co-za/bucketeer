# Availability matrix

Where Bucketeer is offered in the Mac App Store, and why. The Privacy
Policy (§2), the EULA (§1.1), their website copies and the store
drafts state exactly this matrix. Change it here first, then in every
one of those places.

## Matrix for v1.0

| Market | Decision | Source |
|---|---|---|
| Mainland China | Deselect for the app and both IAPs | Portfolio legal baseline; confirmed by Marcello 2026-11-22 Europe/Rome |
| Egypt | Deselect for the app and both IAPs | Portfolio legal baseline; confirmed by Marcello 2026-11-22 Europe/Rome |
| Saudi Arabia | Deselect for the app and both IAPs | Portfolio legal baseline; confirmed by Marcello 2026-11-22 Europe/Rome |
| Russia | Deselect for the app and both IAPs | Portfolio legal baseline; confirmed by Marcello 2026-11-22 Europe/Rome |
| France | Lifetime IAP (`pro.lifetime`) not offered in France (confirmed 2026-11-22). Offering the app in France is intended under that decision but remains gated on the ANSSI / export-compliance path in [`EXPORT_COMPLIANCE.md`](EXPORT_COMPLIANCE.md); until that path is satisfied and recorded, the app stays deselected in France. | Marcello 2026-11-22 Europe/Rome (decision log issue #14); export compliance (ANSSI) |
| Every other storefront Apple serves | Offered | Portfolio legal baseline |

The 2026-11-22 decision does not say whether the free trial IAP
(`pro.trial`) is offered in France. That is an open question for
Marcello; nothing in this repo should state it either way until it is
decided.

France is **not** cleared for the app in App Store Connect. The
Privacy Policy and EULA no longer list France as an excluded
storefront because the product decision no longer requires a full
France block, but that is not a statement that the app is on sale in
France. Juristi (lawyer review) must review the legal wording and the
export path before any App Store Connect availability write and
before this change is merged.

GDPR remains the global floor for every actual user of the App,
wherever they live (Privacy Policy §2).

## Sources

- Portfolio legal baseline: `digitalfreedom-co-za/legal`,
  `internal/PRODUCT_PROFILE.en.md` §6 Markets, at main
  `b938e596beb94c7198c90373bd7c417af4a227d2`. The legal README
  (section "What the generating app must confirm", same commit)
  requires the four deselections to be checked in App Store Connect
  before submission.
- France, commercial: Marcello's decision of 2026-11-22 11:04
  Europe/Rome (decision log issue #14): do not offer the Lifetime
  purchase in France; block Mainland China, Egypt, Saudi Arabia and
  Russia. This narrows the 2026-11-09 decision that France stays fully
  deselected for v1.0.
- France, export compliance:
  [`EXPORT_COMPLIANCE.md`](EXPORT_COMPLIANCE.md) (sections "Why
  `ITSAppUsesNonExemptEncryption = NO`" and "If France is added
  later") and the Encryption section of
  [`APP_STORE_METADATA.md`](APP_STORE_METADATA.md). The app itself is
  not added to the France storefront while the key is `NO` and no
  ANSSI declaration and documentation are on file.

## Decision log

- 2026-11-09 Europe/Rome: Marcello confirmed France remains deselected for Bucketeer v1.0. ASC Pricing and Availability evidence is still outstanding.
- 2026-11-22 11:04 Europe/Rome: Marcello decided (decision log issue #14): in App Store Connect availability, block Mainland China, Egypt, Saudi Arabia and Russia; do not offer the Lifetime purchase in France. This narrows the 2026-11-09 entry: a full France storefront block is no longer the product decision. Offering the app in France stays gated on the ANSSI steps in `EXPORT_COMPLIANCE.md` ("If France is added later"); `ITSAppUsesNonExemptEncryption` stays `NO` until then. Juristi review of the legal wording and the export path is required before any ASC availability write and before merge. ASC Pricing and Availability evidence is still outstanding.

## Live App Store Connect configuration

Not verified against this matrix. No screenshot or export of Pricing
and Availability for the app or for the in-app purchases has been
recorded here. A read-only check on 2026-11-12 (reported in ticket #6)
found the app unavailable only in France and still available in
Mainland China, Egypt, Saudi Arabia and Russia. That is the opposite of
the legal baseline and is not an approved configuration. It is not
evidence that this matrix is live. The IAP setup note
in [`RELEASE_v1.0.md`](RELEASE_v1.0.md) (2026-07-05, all 175
territories) predates this matrix and is not evidence of the app's
availability. Localized UI copy, including Russian, is not evidence
of distribution in that market.

Record the evidence here once it exists: date, who checked, and the
list of deselected territories for the app, `pro.lifetime` and
`pro.trial`.

## Pre-submission check

The checklist in [`RELEASE_v1.0.md`](RELEASE_v1.0.md) section 2
verifies the matrix in App Store Connect before every submission:

- Mainland China, Egypt, Saudi Arabia and Russia are deselected for the
  app, for `pro.lifetime` and for `pro.trial`.
- `pro.lifetime` is not offered in France.
- The app is offered in France only after the export path in
  [`EXPORT_COMPLIANCE.md`](EXPORT_COMPLIANCE.md) ("If France is added
  later") is satisfied and recorded there. Until then the app stays
  deselected in France.
