# Availability matrix

Where Bucketeer is offered in the Mac App Store, and why. The Privacy
Policy (§2), the EULA (§1.1), their website copies and the store
drafts state exactly this matrix. Change it here first, then in every
one of those places.

## Matrix for v1.0

| Market | Decision | Source |
|---|---|---|
| Mainland China | Deselect | Portfolio legal baseline |
| Egypt | Deselect | Portfolio legal baseline |
| Saudi Arabia | Deselect | Portfolio legal baseline |
| Russia | Deselect | Portfolio legal baseline |
| France | Deselect for v1.0 (confirmed) | Bucketeer export compliance (ANSSI); confirmed by Marcello 2026-11-09 Europe/Rome |
| Every other storefront Apple serves | Offered | Portfolio legal baseline |

GDPR remains the global floor for every actual user of the App,
wherever they live (Privacy Policy §2).

## Sources

- Portfolio legal baseline: `digitalfreedom-co-za/legal`,
  `internal/PRODUCT_PROFILE.en.md` §6 Markets, at main
  `b938e596beb94c7198c90373bd7c417af4a227d2`. The legal README
  (section "What the generating app must confirm", same commit)
  requires the four deselections to be checked in App Store Connect
  before submission.
- France: [`EXPORT_COMPLIANCE.md`](EXPORT_COMPLIANCE.md) (section "Why
  `ITSAppUsesNonExemptEncryption = NO`" and "If France is added
  later") and the Encryption section of
  [`APP_STORE_METADATA.md`](APP_STORE_METADATA.md). France stays
  deselected while the key is `NO` and no ANSSI declaration has been
  filed.

## Decision log

- 2026-11-09 Europe/Rome: Marcello confirmed France remains deselected for Bucketeer v1.0. ASC Pricing and Availability evidence is still outstanding.

## Live App Store Connect configuration

Unknown. No screenshot or export of Pricing and Availability for the
app or for the in-app purchase has been recorded. The IAP setup note
in [`RELEASE_v1.0.md`](RELEASE_v1.0.md) (2026-07-05, all 175
territories) predates this matrix and is not evidence of the app's
availability. Localized UI copy, including Russian, is not evidence
of distribution in that market.

Record the evidence here once it exists: date, who checked, and the
list of deselected territories for the app and the IAP.

## Pre-submission check

The checklist in [`RELEASE_v1.0.md`](RELEASE_v1.0.md) section 2
verifies the matrix in App Store Connect before every submission.
