# Bucketeer Help

Bucketeer is a Mac app for object storage: Amazon S3, S3-compatible providers and Azure Blob Storage. This guide covers every feature, from the first account to Finder drives and sync jobs.

## Add an account

- Click **+** in the sidebar header.
- Pick a provider: AWS S3, Azure Blob Storage, Civo, Cloudflare R2, Backblaze B2, Wasabi, DigitalOcean Spaces, Storj, or Custom (MinIO and any other S3-compatible endpoint).
- Enter a name, the region or endpoint, and your credentials (access key and secret; for Azure the storage account key).
- Click **Test Connection**, then **Save**.

Your credentials are stored in the macOS Keychain on this Mac. Bucketeer has no server and no user account; it talks directly to the endpoints you configure.

## Edit an account

The secret is hidden when you edit an account. Click **Reveal stored credentials** and confirm with Touch ID or your Mac password to see it. If you save without touching the secret, the stored one stays unchanged.

## Browse buckets and objects

- Click an account in the sidebar to list its buckets.
- Double-click a bucket or folder to open it. Use the breadcrumb bar or the up arrow to go back.
- Select a file to see its details and a Quick Look preview in the right-hand pane.
- Use the search field to filter the current folder.

## Upload and download

- **Upload**: click the upload button or press **⌘U**. You can also drag files from Finder into the object list or onto a bucket.
- **Download**: right-click a file and choose **Download…**.
- Large files are transferred in parallel parts. An interrupted upload resumes where it stopped.
- All transfers appear under **Transfers** in the sidebar with progress and a cancel button.
- **Settings → Transfers** lets you cap the total bandwidth.

## Open files in other apps

- Double-click a file, or right-click it and choose **Open**, to open it in its default app. **Open With** lists the other apps that can open it; **Other…** lets you pick any app.
- Bucketeer downloads the file into a temporary folder and watches it. A moment after each save, the file is uploaded back through the normal transfer queue, so client-side encryption applies.
- If the object was changed or deleted on the server after you opened it, Bucketeer does not overwrite it. Your version is uploaded next to it as "name (conflict date).ext" and Bucketeer shows a message.
- The temporary copy is deleted once the server has your last save. If a save could not be uploaded (for example while offline), Bucketeer keeps the file on this Mac and asks you to **Upload Again**, **Save a Copy…** or **Discard Edit** — also at the next launch, for example after a crash.

## Manage objects

- **New Folder**: toolbar button or **⇧⌘N**.
- **Rename…**: right-click an object. A rename is a server-side copy followed by a delete. Renaming or deleting a folder applies to everything in it, and a rename never replaces an existing name.
- **Delete**: select one or more objects, click the trash button and confirm.
- **Copy Deep Link**: copies a `bucketeer://` link to the object, which opens it in Bucketeer from anywhere on your Mac.

## Share links

Right-click a file and choose **Get share link…**. Pick how long the link stays valid, then copy or share it. The link is signed on your Mac with your credentials; anyone who has it can download the file until it expires.

## Versions

Right-click a file and choose **Show Versions…** to see its version history. You can restore an older version as the new latest copy or delete a single version. The bucket needs versioning enabled at the provider.

## Metadata and tags

Right-click a file and choose **Metadata & Tags…** to edit HTTP headers (content type, cache control and others), user metadata and tags, and to see the storage class. Some providers do not support every field; Bucketeer tells you when that is the case.

**Settings → Rules** holds auto-tagging rules: they add tags and metadata to new uploads that match a file name pattern or a MIME type.

## Bucket dashboard

Click **Dashboard** in the toolbar of an open bucket. It shows object count, total size, the largest objects, a rough monthly cost estimate, and the bucket's lifecycle rules, CORS configuration and bucket policy (read-only).

## Trash

When you delete objects, Bucketeer can keep a local copy on this Mac (**Settings → Transfers → Trash**). Open the trash with **Window → Trash** (**⇧⌘⌫**) and click **Restore** to upload a cached copy back to its original place. The object at the provider is deleted right away; only the local copy can be restored. Entries are removed automatically after the retention period you set.

## Activity log

**Window → Activity Log** (**⌥⌘0**) lists uploads, downloads, deletes, sync runs, share links and account changes. You can filter, search and export the list as CSV. Entries are kept on this Mac for 180 days.

## Client-side encryption

In **Settings → Encryption** you can create a key for a bucket. From then on, every upload to that bucket is encrypted on your Mac (AES-256-GCM) before it leaves, and downloads are decrypted on the fly. The key is stored in the macOS Keychain on this Mac only.

Important: if you lose the key, nobody can decrypt those objects, including us. Encrypted buckets cannot be mounted in Finder in this version of Bucketeer.

## Spotlight

**Settings → Transfers → Spotlight** is off by default. When you turn it on, the names of objects you browse become searchable in Spotlight. File contents are never indexed, and the index stays on this Mac.

## Shortcuts and Siri

Bucketeer adds actions to the Shortcuts app: list buckets, upload a file, create a share link and run a sync job. Use them in your own shortcuts or ask Siri.

## Pro features

These features need Bucketeer Pro:

- **Mount as Drive**: right-click a bucket and choose **Mount as Drive** to use it in Finder like a disk. Requires macOS 14.1 or later. Mounted drives appear under **Mounted Drives** in the sidebar; right-click to **Unmount**. Buckets with client-side encryption cannot be mounted. Changes made on the server appear in Finder when you refresh the bucket in Bucketeer. If a file you edit in Finder was changed on the server in the meantime, your version is saved next to it as a conflict copy.
- **Sync jobs**: in the **Sync** section, create a job that copies, moves or mirrors between two buckets, across accounts and providers, or between a local folder and a bucket. Run it by hand, at launch, every N minutes, or when the local folder changes.
- **Watch folders**: **New Watch Folder…** uploads every new file in a local folder to a bucket.
- **Copy to other account…**: copies objects to another account or provider. When both sides allow it, the copy runs server-side and the data does not pass through your Mac.
- **Menu bar mode**: **Settings → General** keeps Bucketeer running in the menu bar so drives and sync jobs stay active when the main window is closed.

Everything else is available in the Free tier.

## Bucketeer Pro, trial and purchase

Bucketeer Pro is a one-time in-app purchase through the App Store, with no subscription. Open **Settings → Pro** or any Pro feature to see the price in your currency and buy.

You can try Bucketeer Pro for 14 days at no cost. Before you start, the paywall shows the length of the trial, what happens afterwards and the price of Pro Lifetime; then click **Start trial**. When the trial ends, Bucketeer continues on the Free tier and nothing is charged. The trial can be started once per Apple ID, and restoring purchases also brings back a running trial on another Mac.

- **Restore purchase** brings Pro back on another Mac or after reinstalling.
- **Redeem Code** (macOS 15 or later) opens Apple's sheet for offer codes.

## Keyboard shortcuts

- **⌘U**: Upload files
- **⇧⌘N**: New folder
- **⌥⌘0**: Activity Log
- **⇧⌘⌫**: Trash
- **⌘?**: Bucketeer Help
- **⌘,**: Settings

## Privacy

Bucketeer does not collect analytics and contains no tracking. Your accounts, keys and logs stay on this Mac. Network traffic goes only to the storage providers you configure and to Apple for purchases. Details: **Help → Privacy Policy…**

## Need help?

- Report a problem: **Help → Report an Issue…** or <https://support.apps.digitalfreedom.co.za/>
- Website: <https://digitalfreedom.co.za>
