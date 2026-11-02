<!--
Thanks for contributing. Fill in the sections below — the
template is short on purpose. The maintainer reads every PR
description before the code, so the more specific you can be
about *why*, the faster review goes.

If your PR is a work-in-progress, open it as a Draft.
-->

## Summary

What changes, in 1–3 sentences. Lead with the *behaviour change*
the user sees, not the implementation.

## Why

Link to the GitHub issue, Things task, or design-doc section
that motivated this change. If there's no prior issue, write
the motivation here.

## Test plan

How you verified the change works:

- [ ] `swift test --package-path BucketeerCore` passes
- [ ] `sh scripts/preflight.sh` passes
- [ ] Manual smoke test:
  - [ ] …step…

If your change touches:

- **Transfers / sync / encryption** — note which providers you
  tested against (AWS / Azure / R2 / etc.) and any size
  thresholds you exercised.
- **UI** — attach before/after screenshots for any visible
  change.
- **Localised strings** — confirm the catalog has all 10
  languages filled in (you can use the Python helper in
  `Bucketeer/Resources/` if there is one).
- **Privacy-sensitive code** — call out whether
  `PrivacyInfo.xcprivacy` needs an update.

## Reviewer checklist

For the maintainer / second reviewer:

- [ ] Code matches existing conventions (`Bucketeer/CLAUDE.md`)
- [ ] No new dependencies (or new ones justified in the PR body)
- [ ] No telemetry, analytics, or off-Mac data paths
- [ ] No `SHIP_BLOCKER` markers left in the diff
- [ ] CHANGELOG entry added if user-visible
- [ ] Documentation updated (`docs/ARCHITECTURE.md`, `docs/RELEASE_v1.0.md`,
      `docs/DEEP_LINKS.md`, etc.) if architecture or workflow changed
