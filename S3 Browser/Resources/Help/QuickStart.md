# S3 Browser — Quick Start

Welcome to S3 Browser. This guide walks you through the core workflow.

## Add an account

1. Click **+** in the sidebar header (or the **+ Add Account** button)
2. Pick a provider from the list — AWS S3, Civo, Cloudflare R2, Backblaze B2, Wasabi, DigitalOcean Spaces, Storj, or Custom
3. Enter a name, choose the region, and paste your access key and secret
4. Click **Test Connection** to verify the credentials before you save
5. Click **Save**

Credentials are stored exclusively in your macOS Keychain. Nothing leaves your Mac apart from the S3 traffic you yourself initiate.

## Browse buckets and objects

- Click an account in the sidebar to see its buckets
- Double-click a bucket to open it
- Double-click a folder to drill in
- Use the breadcrumb bar to jump back, or the arrow-up button to go to the parent

## Upload and download files

- **Upload**: click the up-arrow toolbar button or press **⌘U**, then choose one or more files. Multipart upload kicks in automatically for files over 5 MB.
- **Download**: right-click on a file and choose **Download…**, then pick a save location.

All transfers appear in the **Transfers** section in the sidebar with live progress and a cancel button.

## Manage objects

- **New folder**: click the folder-plus toolbar button or press **⇧⌘N**, then enter a name. S3 has no real folders — this creates a zero-byte placeholder with a trailing slash.
- **Rename**: right-click on an object → **Rename…**. The rename is a server-side copy followed by a delete; large objects above 5 GB are not supported for v1.
- **Delete**: select one or more rows, click the trash button, then confirm.

## Edit an account

When you edit an account, all non-secret fields are pre-filled but the secret access key is hidden by default. Click **Reveal stored credentials** to authenticate with **Touch ID** or your account password and see the saved secret.

If you save without revealing or changing the secret, the existing credential stays in your Keychain untouched.

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| ⌘U | Upload files |
| ⇧⌘N | New folder |
| ⌫ | Delete selected (with confirmation) |
| ⌘W | Close window |
| ⌘Q | Quit |
| ⌘, | Open Settings |

## Privacy

S3 Browser does not collect, transmit, store, or analyse any personal data on behalf of its publisher. It runs entirely on your Mac and talks directly to the S3 endpoints you configure. See **About → Privacy Policy** for the full disclosure.

## Need help?

- Report bugs or request features on GitHub at <https://github.com/digitalfreedom-co-za/s3-browser/issues>
- Visit <https://digitalfreedom.co.za>
