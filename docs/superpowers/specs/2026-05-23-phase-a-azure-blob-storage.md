# Phase A — Azure Blob Storage Support

**Date:** 2026-05-23
**Author:** Marcel R. G. Berger
**Status:** Planned (slots between Phase 5 and Phase 6)
**Driver:** Azure Blob Storage is a first-tier object-storage market. Supporting it alongside every S3-compatible provider is a deliberate USP for S3 Browser — *"all the S3 providers and Azure, one app."*

---

## 1. Why a separate phase

Azure Blob Storage is **not** S3-compatible natively. It has:

- A different protocol shape — `https://{account}.blob.core.windows.net/{container}/{blob}`
- A different authentication scheme — Shared Key HMAC-SHA256 signing (stricter canonicalisation than AWS Sig V4), or SAS tokens, or Microsoft Entra ID OAuth2
- Different XML shapes for list responses
- Different upload semantics — Block Blobs / Append Blobs / Page Blobs (block-staging + commit-block-list for large uploads)
- Different metadata header names (`x-ms-meta-*` vs `x-amz-meta-*`)

Wrapping it as just another Soto endpoint is impossible. It needs its own transport, its own signer, its own request/response handling. The right move is therefore to plan it as one cohesive phase, slotted **after Phase 5** (Delete/Rename/Folder Actions) so the small UI gaps in the browser are closed first, but **before Phase 6** (Preview) so all subsequent features build on a provider-router that already speaks both S3 and Azure.

---

## 2. Goal

Add Azure Blob Storage as a first-class provider in the existing provider picker with the same browser UX as the S3 providers:

- Browse containers (= buckets), browse blobs (= objects), folder-style navigation via `/` delimiter
- Upload (single-shot below 100 MB, block-staged above)
- Download (single GET below threshold, ranged parallel GET above)
- Delete, rename (copy + delete), create folder (zero-byte blob with `prefix/`)
- Preview, drag-and-drop, mount-as-drive, sync — automatically follow once the underlying transports work, since they live on the same protocols
- Localised UI labels nudge to Azure terminology only where it matters ("Storage account name", "Account key")

---

## 3. Scope

### 3.1 In scope (Phase A v1.0)

- **Provider preset**: `S3Provider.azureBlob`
- **Auth**: Account Name + Account Key (Shared Key signing)
- **Endpoint**: `https://{accountName}.blob.core.windows.net`
- **Operations**: List Containers, List Blobs (hierarchical via delimiter), Get Blob, Put Block Blob, Delete Blob, Copy Blob, head (Get Blob Properties), zero-byte directory marker (`prefix/`)
- **Block Blob multipart**: Put Block + Put Block List for blobs ≥ 100 MB
- **Folder simulation**: flat namespace with `/` delimiter — matches the S3 UX
- **Region inferred from endpoint**: no separate region field needed; endpoint already encodes it. Region picker is hidden for `.azureBlob` and falls back to "auto"
- **Localised field labels**: AddEditAccountSheet shows Azure-specific labels when the provider is `.azureBlob`

### 3.2 Out of scope (Phase A v1.0 — later if demand exists)

- SAS token auth (v1.1)
- Microsoft Entra ID OAuth2 (v2)
- Append Blobs and Page Blobs (only Block Blobs in v1.0)
- Azure Data Lake Storage Gen2 hierarchical namespace (real folders) — v1.0 uses flat namespace identical to S3
- Snapshots, versioning, soft-delete restore, immutability policies
- Cross-account / cross-region copy via Azure-side replication
- Lease management, blob tags, encryption-scope per-blob
- Storage-account-level operations (create / delete containers, change tier, lifecycle)

---

## 4. Architecture

### 4.1 Provider abstraction layer

Today `S3Browsing` and `Transferring` are both nominally provider-agnostic; the only concrete implementations talk to Soto. To support Azure cleanly, the existing services become **two backends** behind a **router**:

```
S3Browsing            ← router on account.provider →   S3ObjectStore       (Soto, AWS family + compatibles)
Transferring          ← router on account.provider →   AzureBlobObjectStore (URLSession + Shared Key)
```

The host app still uses `container.s3Browser` and `container.transferManager` — the router is transparent.

### 4.2 New file layout

```
Services/
  ProviderRouter.swift           — implements S3Browsing + acts as TransferManager router
  S3/
    S3ObjectStore.swift          — renamed from S3BrowserService.swift
    S3ClientFactory.swift        — unchanged
  Azure/
    AzureBlobObjectStore.swift   — implements S3Browsing for Azure
    AzureSharedKeySigner.swift   — HMAC-SHA256 Shared Key signing (CryptoKit)
    AzureRequestBuilder.swift    — URL construction + canonical headers
    AzureListXMLParser.swift     — list-blobs / list-containers XML response parser
    AzureMultipartUploader.swift — block-staging + commit-block-list
  Transfers/
    TransferManager.swift        — dispatches per-account to S3 or Azure transport
```

### 4.3 Model changes

- `S3Provider` gains a new case `.azureBlob`
- `S3Account` shape stays identical:
  - `accountID` is reused to hold the Azure storage-account name (already an `Optional<String>` field on the model)
  - `region` is set to `"auto"` and hidden in the UI for this provider
  - `endpointOverride` stays available for sovereign Azure clouds (`*.blob.core.usgovcloudapi.net`, `*.blob.core.chinacloudapi.cn`)
- `AccountCredentials` reuses `accessKey` for the storage-account name and `secretKey` for the base64 account key (no schema change)

### 4.4 Authentication: Shared Key signing

Implemented from scratch using `CryptoKit.HMAC<SHA256>`. Algorithm (Microsoft docs reference):

```
SharedKey {accountName}:Base64({HMAC-SHA256(stringToSign, base64Decode(accountKey))})

stringToSign =
    VERB + "\n" +
    Content-Encoding + "\n" +
    Content-Language + "\n" +
    Content-Length + "\n" +              // empty for GET
    Content-MD5 + "\n" +
    Content-Type + "\n" +
    Date + "\n" +                        // empty if x-ms-date is present
    If-Modified-Since + "\n" +
    If-Match + "\n" +
    If-None-Match + "\n" +
    If-Unmodified-Since + "\n" +
    Range + "\n" +
    CanonicalizedHeaders +
    CanonicalizedResource
```

The signer is a `struct` with no shared mutable state (pure function over request inputs) — trivially Sendable.

### 4.5 Transfers

- **Upload < 100 MB**: single Put Block Blob (`PUT /{container}/{blob}`)
- **Upload ≥ 100 MB**: multipart Block Blob — split file into chunks of `Self.blockSize` (default 8 MiB, configurable up to 4000 MiB), `Put Block` each (parallel, up to 4 concurrent), then `Put Block List` (commits)
- **Download < 100 MB**: single Get Blob
- **Download ≥ 100 MB**: ranged Get Blob, parallel — same threshold and parallelism story as S3 multipart download for symmetry
- Progress reporting flows back through the same `TransferManager` state machine as S3 transfers
- Cancellation uses cooperative `Task.cancel()` and the same `terminated: Set<UUID>` guard already in place

### 4.6 Listing

- `listBuckets(account:)` → `GET https://{account}.blob.core.windows.net/?comp=list`
- `listObjects(account:, bucket:, prefix:, continuationToken:)` →
  `GET https://{account}.blob.core.windows.net/{container}?restype=container&comp=list&prefix={prefix}&delimiter=/&marker={token}`
- Parse the XML response into `[S3Bucket]` / `[S3Object]` value snapshots that already exist
- Pagination uses Azure's `NextMarker` element instead of S3's `NextContinuationToken` — wrapped at the parser boundary so callers don't see the difference

### 4.7 UI changes

- `S3Provider.azureBlob` shows `"Azure Blob Storage"` with SF Symbol `"cloud.fill"` in the picker
- AddEditAccountSheet renders three Azure-aware fields when provider is `.azureBlob`:
  - **Storage account name** (mapped to `accountID`)
  - **Account key** (SecureField, mapped to `secretKey` in Keychain)
  - **Custom endpoint** (optional, defaults to `https://{accountID}.blob.core.windows.net`)
- Region picker hidden (Azure derives region from account)
- Path-style toggle hidden (irrelevant for Azure)
- The localised section header reads `"Container"` (rendered in-app) when the provider is Azure, `"Bucket"` otherwise — single string-key with a provider-context selector

### 4.8 Error mapping

Azure error codes (returned in the response body or `x-ms-error-code` header) map to the existing `S3BrowserError` cases:

| Azure | Mapped to |
|---|---|
| `ContainerNotFound` | `.bucketNotFound(container)` |
| `BlobNotFound` | `.objectNotFound(key:)` |
| `AuthenticationFailed`, `InvalidAuthenticationInfo`, `AccountIsDisabled`, `InsufficientAccountPermissions` | `.authenticationFailed` |
| `ServerBusy`, `OperationTimedOut` | `.networkUnavailable` |
| any other | `.providerError(statusCode:, message:)` |

---

## 5. Sub-phases

| # | Slice | Estimated effort | Deliverable |
|---|---|---|---|
| **A.1** | Foundation: provider case, signer, request builder, list/head/delete/copy | 1 session | Read-side parity: browse a real Azure account |
| **A.2** | Transports: download + single-shot upload | 1 session | Upload + download of files < 100 MB works |
| **A.3** | Block-blob multipart upload + parallel ranged download | 1 session | Symmetry with S3 multipart for large files |
| **A.4** | UI polish: provider-aware labels, region/path-style hiding, endpoint default | 0.5 session | Add-account flow feels native for Azure users |
| **A.5** | Test matrix against a real Azure storage account; Codex review | 0.5 session | Manual sign-off + fixes |
| **A.6** | Docs: README, OPEN_SOURCE_NOTICES if any third-party crypto/XML dep is added (none expected — CryptoKit + XMLParser are Apple-native), App Store description bullet | 0.5 session | Ready for Phase 6 |

**Total**: ~4.5 sessions.

---

## 6. Risks and unknowns

- **Shared Key signing edge cases**: canonicalisation rules around blank headers and URL encoding are notoriously fiddly. Mitigation: unit tests over Microsoft's published canonicalisation examples.
- **Sovereign-cloud endpoints**: Azure China and Azure GovCloud use different hostnames. The endpoint-override field in our existing model already handles this — no schema change, but UI guidance is needed.
- **Large-file Block IDs**: Block IDs in a Put Block List must all be the same length when base64-encoded. Mitigation: pad with a fixed prefix `block-%08d` before base64.
- **XML parsing**: Apple's `XMLParser` is event-driven and stateful, less friendly than Soto's generated decoders. Mitigation: keep parser scoped to a tiny set of element names; cover via unit tests.

---

## 7. Roadmap placement

```
Phase 4 (done)  →  Phase 5 (Object actions)
                     ↓
                   Phase A (Azure foundation, transports, polish)
                     ↓
                   Phase 6 (Preview)
                     ↓
                   Phase 7 (Drag-and-Drop)
                     ↓
                   Phase 8 (Menubar)
                     ↓
                   Phase 9 (File Provider Extension)
                     ↓
                   Phase 10 (Sync Engine)
                     ↓
                   Phase 11 (Localisation finalisation in all 10 wiki languages)
                     ↓
                   Phase 12 (Hardening: a11y, performance, App Store metadata)
```

The Sync Engine of Phase 10 then automatically supports S3-to-Azure and Azure-to-S3 sync, which is a second USP nobody else ships out of the box.

---

## 8. Open decisions

1. **Auth modes in v1.0**: Account Key only is my recommendation; SAS Token deferred to v1.1, OAuth2 to v2. Confirm.
2. **Hierarchical namespace (ADLS Gen2)**: skip in v1.0 — keeps the codebase identical between S3 and Azure paths. Surfaces if there is real user demand.
3. **Folder semantics**: flat namespace with `/` delimiter, identical to S3. Real ADLS hierarchical folders deferred. Confirm.

Once these are confirmed, Phase A.1 implementation can begin immediately after Phase 5 lands.

---

*End of phase plan.*
