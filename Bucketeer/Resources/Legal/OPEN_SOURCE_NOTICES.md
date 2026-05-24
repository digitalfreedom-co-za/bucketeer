# Open Source Notices

*Third-party open-source software bundled inside Bucketeer for macOS,
together with the copyright lines and license texts required for
Apple's submission process and the upstream licenses themselves.*

**Application** — Bucketeer for macOS
**Publisher** — DigitalFreedom · Berger & Rosenstock GbR
**Contact** — hello@digitalfreedom.co.za
**Last updated** — 24 May 2026

---

## 1. Scope

Bucketeer integrates the following open-source libraries via Swift
Package Manager. The pinned versions are recorded in
`Bucketeer.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
for the App Store build that this document accompanies.

Inclusion of these components does **not** extend redistribution
rights to Bucketeer as a whole. The App's source code is published
under the **Source-Available License**; the compiled binary is
governed by the **End User License Agreement**. Your use of each
upstream library is governed by the library's own license, reproduced
below.

---

## 2. Direct dependency

### Soto (SotoS3)

- **Project** — `soto-project/soto`
- **Repository** — `https://github.com/soto-project/soto`
- **License** — Apache-2.0
- **Copyright** — © 2017–2026 the Soto project authors
- **Used for** — AWS S3 protocol client for every S3-compatible
  provider (AWS, Civo, Cloudflare R2, Backblaze B2, Wasabi,
  DigitalOcean Spaces, Storj, MinIO, and any custom S3 endpoint).

---

## 3. Transitive dependencies

All entries are licensed under the **Apache License 2.0** unless
noted otherwise. Copyright lines reflect the upstream `LICENSE`
header at the pinned version. Repository URLs are the canonical
sources from which the linker pulls the binaries during the App
Store build.

### 3.1 Apple Swift ecosystem

- **SwiftNIO** — `https://github.com/apple/swift-nio` — © 2017–2026
  Apple Inc. and the SwiftNIO project authors
- **SwiftNIO Extras** — `https://github.com/apple/swift-nio-extras`
  — © 2017–2026 Apple Inc. and the SwiftNIO project authors
- **SwiftNIO SSL** — `https://github.com/apple/swift-nio-ssl` —
  © 2017–2026 Apple Inc. and the SwiftNIO project authors
- **SwiftNIO HTTP/2** — `https://github.com/apple/swift-nio-http2`
  — © 2017–2026 Apple Inc. and the SwiftNIO project authors
- **SwiftNIO Transport Services** —
  `https://github.com/apple/swift-nio-transport-services` —
  © 2017–2026 Apple Inc. and the SwiftNIO project authors
- **SwiftCrypto** — `https://github.com/apple/swift-crypto` —
  © 2019–2026 Apple Inc. and the SwiftCrypto project authors
- **Swift Certificates** —
  `https://github.com/apple/swift-certificates` — © 2022–2026 Apple
  Inc. and the swift-certificates project authors
- **Swift ASN.1** — `https://github.com/apple/swift-asn1` —
  © 2022–2026 Apple Inc. and the swift-asn1 project authors
- **Swift Collections** —
  `https://github.com/apple/swift-collections` — © 2021–2026 Apple
  Inc. and the Swift project authors
- **Swift Algorithms** — `https://github.com/apple/swift-algorithms`
  — © 2020–2026 Apple Inc. and the Swift project authors
- **Swift Async Algorithms** —
  `https://github.com/apple/swift-async-algorithms` — © 2022–2026
  Apple Inc. and the Swift project authors
- **Swift Atomics** — `https://github.com/apple/swift-atomics` —
  © 2020–2026 Apple Inc. and the Swift project authors
- **Swift Numerics** — `https://github.com/apple/swift-numerics` —
  © 2019–2026 Apple Inc. and the Swift Numerics project authors
- **Swift System** — `https://github.com/apple/swift-system` —
  © 2020–2026 Apple Inc. and the Swift System project authors
- **Swift HTTP Types** —
  `https://github.com/apple/swift-http-types` — © 2023–2026 Apple
  Inc. and the Swift project authors
- **Swift HTTP Structured Headers** —
  `https://github.com/apple/swift-http-structured-headers` —
  © 2021–2026 Apple Inc. and the project authors
- **Swift Log** — `https://github.com/apple/swift-log` — © 2018–2026
  Apple Inc. and the SwiftLog project authors
- **Swift Metrics** — `https://github.com/apple/swift-metrics` —
  © 2018–2026 Apple Inc. and the SwiftMetrics project authors
- **Swift Distributed Tracing** —
  `https://github.com/apple/swift-distributed-tracing` — © 2020–2026
  Apple Inc. and the Swift Distributed Tracing project authors
- **Swift Service Context** —
  `https://github.com/apple/swift-service-context` — © 2022–2026
  Apple Inc. and the Swift Service Context project authors
- **Swift Service Lifecycle** —
  `https://github.com/swift-server/swift-service-lifecycle` —
  © 2019–2026 the Swift Server project authors
- **Swift Configuration** —
  `https://github.com/apple/swift-configuration` — © 2024–2026
  Apple Inc. and the Swift Configuration project authors

### 3.2 Swift Server ecosystem

- **AsyncHTTPClient** —
  `https://github.com/swift-server/async-http-client` — © 2018–2026
  the AsyncHTTPClient project authors

### 3.3 Soto project

- **SotoCore** — `https://github.com/soto-project/soto-core` —
  © 2017–2026 the Soto project authors
- **JMESPath (jmespath.swift)** — `https://github.com/adam-fowler/jmespath.swift`
  — **MIT** — © 2022–2026 Adam Fowler

---

## 4. License texts

### 4.1 Apache License 2.0

All components above (except `jmespath.swift`) are licensed under the
**Apache License, Version 2.0**. Full text:

`https://www.apache.org/licenses/LICENSE-2.0`

Key compliance points observed by this document (Apache 2.0 § 4):

- Each component's copyright notice is reproduced above (§ 4(c)).
- The `NOTICE` files of components that publish one are reproduced
  verbatim in the in-app **About → Open Source** view (§ 4(d)).
- No modifications to the upstream sources are bundled; the App
  links pristine binaries built from the pinned versions in
  `Package.resolved` (§ 4(b) — not triggered).
- Source code is available at the repository URLs above (§ 4(a)).

### 4.2 MIT License (jmespath.swift)

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and / or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NON-
INFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
LIABLE FOR ANY CLAIM, DAMAGES, OR OTHER LIABILITY, WHETHER IN AN
ACTION OF CONTRACT, TORT, OR OTHERWISE, ARISING FROM, OUT OF, OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

---

## 5. System frameworks

In addition to the third-party packages above, Bucketeer relies on
first-party Apple system frameworks (Foundation, SwiftUI, SwiftData,
AppKit, FileProvider, StoreKit, LocalAuthentication, CryptoKit,
UniformTypeIdentifiers, Quartz / Quick Look, CoreServices /
FSEventStream). These are part of macOS and governed by the Apple
Operating System Software License Agreement; no separate open-source
notice applies to them.

---

## 6. Source-code availability

Source code for every Apache-2.0 and MIT component listed above is
available at the repository URL specified for that component. The
exact versions in the App Store build of Bucketeer are pinned in
`Package.resolved` in the project repository:

`https://github.com/digitalfreedom-co-za/bucketeer`

For direct requests, contact: hello@digitalfreedom.co.za

---

## 7. Updates

This document is regenerated whenever a dependency is added, removed,
or upgraded across a major version. Patch-level upgrades follow the
existing entries' license and copyright lines and do not require a
notice update.

---

© 2026 DigitalFreedom · Berger & Rosenstock GbR. The copyright in
this document covers this notice file only; the open-source
components listed herein remain subject to their respective upstream
licenses.
