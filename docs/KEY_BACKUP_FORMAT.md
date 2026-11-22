# Bucketeer key backup format (version 1)

`.bktkeys` files contain only an authenticated encrypted JSON payload. They are
independent of the existing BCKT object envelope; that format is unchanged.
All offsets below are zero-based and all lengths are bytes.

| Offset | Length | Meaning |
| --- | --- | --- |
| 0 | 7 | ASCII `BKTKEYX` |
| 7 | 1 | Format version: `1` |
| 8 | 1 | KDF identifier: `1` = PBKDF2-HMAC-SHA256 |
| 9 | 4 | Unsigned iteration count, big-endian |
| 13 | 16 | Random salt |
| 29 | 12 | Random AES-GCM nonce |
| 41 | variable | AES-256-GCM ciphertext |
| end − 16 | 16 | GCM authentication tag |

The complete 41-byte header, including salt and nonce, is additional
authenticated data (AAD). PBKDF2 uses the passphrase's NFC-normalized UTF-8 bytes, the stored salt, and a 32-byte output key. Exports use 600,000
iterations. Imports reject counts below 100,000 or above 10,000,000 before
performing the KDF. Apple CommonCrypto implements PBKDF2; CryptoKit implements
AES-GCM; Security's SecRandomCopyBytes supplies salt and nonce randomness.

The plaintext is a JSON array of entries with `id` (source key UUID),
`accountID` (UUID), optional `accountDisplayName`, `bucket`, `label`, `rawKey`
(base64-encoded 32-byte key), and `createdAt` (JSONEncoder's seconds since
2001-01-01 UTC). Unknown fields are ignored for forward compatibility.
Unsupported versions and KDF identifiers are rejected, never guessed.
Malformed headers and invalid iteration counts have typed errors. Wrong
passphrases and modifications of structurally valid files fail authentication.
No entries are offered for import until the entire file authenticates and the
payload passes validation. Duplicate account/bucket entries and duplicate entry UUIDs are rejected.
Input files are limited to 16 MiB to bound memory use.

Export requires device-owner authentication and a confirmed passphrase of at
least 12 characters. Only ciphertext is written, atomically. Temporary JSON,
passphrase byte buffers, and derived key bytes are reset where practical;
Swift value semantics and framework-owned copies prevent a guarantee that
all secret copies can be erased from process memory. No plaintext key files
or logs are produced.

## Import and backup state

The review compares account UUID plus bucket, not display names. Equal key
bytes are skipped after checking the current store again. Missing Keychain bytes
with surviving metadata are restored against the reviewed local ID after the user confirms the import. A different existing key defaults to keep existing.
Replacement requires a per-key choice and destructive confirmation. The store
rechecks the expected existing key ID when applying that choice; a stale
choice fails instead of replacing a subsequently changed key. New keys use
fresh local IDs to prevent source UUID collisions with unrelated local keys.
Unknown account UUIDs are preserved and appear under “Deleted account”, using
the existing reassignment flow. Accounts are never matched by name.

Authentication failures import nothing. Storage errors can leave a subset of
reviewed keys imported; retrying is safe because identical keys are skipped.
A replacement writes new Keychain bytes first, saves metadata, then removes
old bytes. If metadata saving fails, the old key remains usable.

Successful file saving marks only the exported local keys as backed up.
An explicit first-upload acknowledgement is also persisted per local key.
Imported keys have a backup by definition. New or replaced key identities do
not inherit the old key's acknowledgement. Before encrypting an upload, the
shared upload gate checks this state; cancellation leaves the upload blocked.
Declines suppress further prompts for that key for 60 seconds. The prompt also
offers direct export; queued uploads stop until the backup has been saved, then
can be retried. Device-owner authentication is enforced by the export ViewModel
before reading raw keys.
Keep both the file and its passphrase safely: losing either prevents recovery
from that backup.
