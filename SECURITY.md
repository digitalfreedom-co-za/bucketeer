# Security Policy

## Supported versions

Bucketeer ships through the Mac App Store under one public version
line. Security patches land on the latest release; older builds are
not separately maintained.

| Version | Supported |
|---|---|
| v1.x (current) | ✅ |
| < v1.0 | ❌ (pre-release internals only) |

## Reporting a vulnerability

**Please do not file a public GitHub issue for security reports.**
The repository is source-available so anyone reading an issue
becomes aware of the vulnerability before a patch is in users'
hands.

Send a private report to:

> **security@digitalfreedom.co.za**

Include:

- A short description of the issue (what an attacker could do)
- The Bucketeer version (App → Bucketeer → About)
- macOS version (`sw_vers`)
- Reproduction steps — concrete commands, screenshots, or a test
  bucket setup
- Whether you'd like to be credited in the release notes

You should expect a first reply within **2 working days**. We
follow a co-ordinated disclosure timeline:

| Phase | Target |
|---|---|
| Acknowledgement | within 2 working days |
| Triage + severity assessment | within 5 working days |
| Patch in development branch | within 30 days for high / critical |
| App Store submission | within 7 days of merged patch |
| Public advisory | once Apple has approved the patched build |

## Scope

In scope:

- The Bucketeer App binary distributed on the Mac App Store
- The source code in this repository
- The Bucketeer-side handling of credentials, transferred data,
  client-side encryption keys, and the local stores listed in
  `docs/ARCHITECTURE.md` §1.1

Out of scope:

- Vulnerabilities in third-party storage providers (AWS, Azure,
  Cloudflare, etc.) — report those to the provider directly
- macOS, Xcode, or Apple system frameworks
- The Soto open-source dependencies (report at the upstream project)
- Self-hosted MinIO / S3-compatible servers configured by the user
- Social-engineering attacks that require the user to type
  credentials into a third-party site

## Hall of fame

Researchers who report a confirmed vulnerability following this
policy and ask to be credited are listed in the release notes for
the build that fixed the issue.
