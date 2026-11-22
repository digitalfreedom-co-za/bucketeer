# Legal languages

Which languages the legal texts of Bucketeer are generated in, why, and what is
not verified yet. Applies to the in-app documents in `Bucketeer/Resources/Legal/`
and to the website copies made from them by `scripts/sync-legal.mjs` in
`getbucketeer.app.website`.

## Rule

Source: `legal/shared/_meta/LOCALIZATION_POLICY.en.md` version 2.1.0 (legal
commit b938e59).

- Required legal languages are the storefront languages of the markets the app
  ships in, and always at least English (`en`) and German (`de`) (section 2).
- For a consumer, the version in an official language of their country of
  habitual residence governs where such a version exists. English governs for
  business customers and where no local version exists (section 1).
- Country sections are never dropped in a translation (section 4). Verbatim
  blocks stay byte-identical, such as the Australian Consumer Law notice in
  EULA section 16.5 (section 3).
- Every document carries its doc-id and version in a header comment
  (section 7).

## Markets

Recorded exclusions, nothing beyond them:

| Market | Status | Source |
|---|---|---|
| Mainland China | Not offered | `legal/internal/PRODUCT_PROFILE.en.md` 1.5.1, section 6 |
| Egypt | Not offered | same |
| Saudi Arabia | Not offered | same |
| Russia | Not offered | same |
| France | Not offered in v1.0 | `docs/EXPORT_COMPLIANCE.md` |
| Every other storefront Apple serves | Offered according to the documents above | same |

The live storefront list in App Store Connect has **not been verified**. The
20 UI locales of the app and the website (including Russian) are no proof that
the app is sold in a market where that language is spoken.

## Matrix

| Document | en | de | Other languages |
|---|---|---|---|
| Privacy Policy (`PRIVACY_POLICY.md`, `PRIVACY_POLICY.de.md`) | yes | yes | pending the verified storefront list |
| EULA (`EULA.md`, `EULA.de.md`) | yes | yes | pending the verified storefront list |
| Impressum (`IMPRESSUM.md`, `IMPRESSUM.de.md`) | yes | yes | pending the verified storefront list |
| License (`LICENSE.md`) | yes | no | English only: the license of the published source code, not a consumer contract |
| Open Source Notices (`OPEN_SOURCE_NOTICES.md`) | yes | no | English only: third-party license texts that are reproduced as published |

The unsuffixed file is English. A translation sits next to it with the language
code before the extension (`EULA.de.md`). The About window shows the file for
the language of `Locale.current` when it is bundled, otherwise the English file.
The website shows the German text on the German pages and the English text in
every other locale, with a notice stating the governing-language rule.

## Traceability

Each English document starts with a header such as:

```
<!-- doc-id: BUCKETEER_EULA | lang: en | area: app | version: 1.0.0 | valid-from: 2026-11-02 | baseline: legal apps/documents/EULA.en.md, Bucketeer product adaptation; ... | owner: Marcel R. G. Berger -->
```

The Bucketeer texts are product adaptations of the legal repo baselines
(`shared/PRIVACY_POLICY.en.md`, `apps/documents/EULA.en.md`,
`website/IMPRESSUM.en.md`). Which baseline version they were derived from was
not recorded; the header names the version the legal repo carries at
b938e59 for reference only. Version 1.0.0 is the first versioned state of the
Bucketeer text. Each German file names the English doc-id and version it
translates and is marked `review: not counsel-reviewed`. AI legal review
(Anwalt role) completed 2026-11-09; not a licensed counsel review. The in-app renderer
skips single-line HTML comments, so the headers are not shown to the reader.

When an English document changes, bump its version, update the German sibling
to the same content and the `translation-of` version, then run the website
sync.

## Open questions

- The verified storefront and language list from App Store Connect. Until it is
  known, only `en` and `de` are generated.
- Counsel review of the German texts before they are published. AI legal
  review (Anwalt role) completed 2026-11-09; not a licensed counsel review.
- Whether further languages are required once the list is known. The
  localization policy names `cs da de el es fi fr hu it ja ko nb nl pl pt sv tr`
  as the store tier. French in particular may be needed for consumers in
  Belgium, Switzerland or Quebec even though France itself is excluded, if those
  storefronts are offered.
