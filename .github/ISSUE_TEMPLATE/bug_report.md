---
name: Bug report
about: Something in Bucketeer doesn't behave the way you expected.
title: "[Bug] "
labels: ["bug", "triage"]
---

<!--
Please don't paste credentials, presigned URLs, or anything else
the public should not see. Redact bucket names if they're
identifying. If the bug is a security vulnerability, follow
SECURITY.md instead of filing it here.
-->

## What happened

A clear, 1–2 sentence description of the unexpected behaviour.

## What you expected

What Bucketeer should have done instead.

## Steps to reproduce

1. …
2. …
3. …

## Environment

- **Bucketeer version**: Bucketeer → About → version line
- **macOS version**: `sw_vers` from Terminal
- **Provider**: AWS S3 / Azure Blob / Cloudflare R2 / Backblaze B2 / Wasabi / DigitalOcean Spaces / Storj / Civo / MinIO / Custom
- **Region**: e.g. eu-central-1
- **Bucket settings** (if relevant): versioning on/off, encryption,
  unusual lifecycle rules, etc.
- **Bucketeer Pro?**: Yes / No / Trial

## Activity log row

If the issue surfaced in the Activity Log (⌘⌥0), copy the row's
text from the CSV export. Strip anything sensitive.

```
2026-05-25 14:00:01, upload, failed, "<account>", "<bucket>", "<key>", 1048576, 12, , "..."
```

## Screenshots / logs

Drag images directly into this issue. For Console output, wrap
in a ``` fenced code block.
