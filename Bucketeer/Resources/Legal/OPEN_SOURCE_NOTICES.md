# OPEN SOURCE NOTICES

## Third-Party Open-Source Software in Bucketeer

**Last Updated:** 24 May 2026
**Application:** Bucketeer for macOS
**Publisher:** DigitalFreedom — Berger & Rosenstock GbR
Contact: hello@digitalfreedom.co.za

---

## 1. SCOPE

Bucketeer integrates the following open-source libraries via Swift
Package Manager. The pinned versions are recorded in
`Bucketeer.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
for the App-Store build that this document accompanies.

Inclusion of these components does not extend redistribution rights to
Bucketeer as a whole: the App's source code is published under the
[Source-Available License](LICENSE.md) and the compiled binary under
the [End User License Agreement](EULA.md). Your use of each upstream
library is governed by the library's own license, reproduced below.

---

## 2. DIRECT DEPENDENCY

### Soto (SotoS3)

```
Project:    soto-project/soto
Repository: https://github.com/soto-project/soto
License:    Apache-2.0
Copyright:  Copyright 2017-2026 the Soto project authors
Used for:   AWS S3 protocol client for every S3-compatible provider
            (AWS, Civo, Cloudflare R2, Backblaze B2, Wasabi,
             DigitalOcean Spaces, Storj, MinIO and any custom S3
             endpoint).
```

---

## 3. TRANSITIVE DEPENDENCIES (Pulled in by Soto)

All entries are licensed under the **Apache License 2.0** unless noted
otherwise. Copyright lines reflect the upstream `LICENSE` header at the
pinned version. Repository URLs are the canonical sources from which
the linker pulls the binaries during the App-Store build.

### Apple Swift Ecosystem

```
SwiftNIO
Repository: https://github.com/apple/swift-nio
Copyright:  © 2017-2026 Apple Inc. and the SwiftNIO project authors

SwiftNIO Extras
Repository: https://github.com/apple/swift-nio-extras
Copyright:  © 2017-2026 Apple Inc. and the SwiftNIO project authors

SwiftNIO SSL
Repository: https://github.com/apple/swift-nio-ssl
Copyright:  © 2017-2026 Apple Inc. and the SwiftNIO project authors

SwiftNIO HTTP/2
Repository: https://github.com/apple/swift-nio-http2
Copyright:  © 2017-2026 Apple Inc. and the SwiftNIO project authors

SwiftNIO Transport Services
Repository: https://github.com/apple/swift-nio-transport-services
Copyright:  © 2017-2026 Apple Inc. and the SwiftNIO project authors

SwiftCrypto
Repository: https://github.com/apple/swift-crypto
Copyright:  © 2019-2026 Apple Inc. and the SwiftCrypto project authors

Swift Certificates
Repository: https://github.com/apple/swift-certificates
Copyright:  © 2022-2026 Apple Inc. and the swift-certificates project authors

Swift ASN.1
Repository: https://github.com/apple/swift-asn1
Copyright:  © 2022-2026 Apple Inc. and the swift-asn1 project authors

Swift Collections
Repository: https://github.com/apple/swift-collections
Copyright:  © 2021-2026 Apple Inc. and the Swift project authors

Swift Algorithms
Repository: https://github.com/apple/swift-algorithms
Copyright:  © 2020-2026 Apple Inc. and the Swift project authors

Swift Async Algorithms
Repository: https://github.com/apple/swift-async-algorithms
Copyright:  © 2022-2026 Apple Inc. and the Swift project authors

Swift Atomics
Repository: https://github.com/apple/swift-atomics
Copyright:  © 2020-2026 Apple Inc. and the Swift project authors

Swift Numerics
Repository: https://github.com/apple/swift-numerics
Copyright:  © 2019-2026 Apple Inc. and the Swift Numerics project authors

Swift System
Repository: https://github.com/apple/swift-system
Copyright:  © 2020-2026 Apple Inc. and the Swift System project authors

Swift HTTP Types
Repository: https://github.com/apple/swift-http-types
Copyright:  © 2023-2026 Apple Inc. and the Swift project authors

Swift HTTP Structured Headers
Repository: https://github.com/apple/swift-http-structured-headers
Copyright:  © 2021-2026 Apple Inc. and the swift-http-structured-headers project authors

Swift Log
Repository: https://github.com/apple/swift-log
Copyright:  © 2018-2026 Apple Inc. and the SwiftLog project authors

Swift Metrics
Repository: https://github.com/apple/swift-metrics
Copyright:  © 2018-2026 Apple Inc. and the SwiftMetrics project authors

Swift Distributed Tracing
Repository: https://github.com/apple/swift-distributed-tracing
Copyright:  © 2020-2026 Apple Inc. and the Swift Distributed Tracing project authors

Swift Service Context
Repository: https://github.com/apple/swift-service-context
Copyright:  © 2022-2026 Apple Inc. and the Swift Service Context project authors

Swift Service Lifecycle
Repository: https://github.com/swift-server/swift-service-lifecycle
Copyright:  © 2019-2026 the Swift Server project authors

Swift Configuration
Repository: https://github.com/apple/swift-configuration
Copyright:  © 2024-2026 Apple Inc. and the Swift Configuration project authors
```

### Swift Server Ecosystem

```
AsyncHTTPClient
Repository: https://github.com/swift-server/async-http-client
Copyright:  © 2018-2026 the AsyncHTTPClient project authors
```

### Soto Project

```
SotoCore
Repository: https://github.com/soto-project/soto-core
Copyright:  © 2017-2026 the Soto project authors

JMESPath (jmespath.swift)
Repository: https://github.com/adam-fowler/jmespath.swift
License:    MIT
Copyright:  © 2022-2026 Adam Fowler
```

---

## 4. LICENSE TEXTS

### 4.1 Apache License 2.0

All components above (except `jmespath.swift`) are licensed under the
**Apache License, Version 2.0**. Full text:

`https://www.apache.org/licenses/LICENSE-2.0`

Key compliance requirements observed by this document (Apache 2.0
Section 4):

- Each component's copyright notice is reproduced above (Section 4(c)).
- The `NOTICE` files of components that publish one are reproduced
  verbatim in the in-App **About → Open Source** view (Section 4(d)).
- No modifications to the upstream sources are bundled; the App links
  pristine binaries built from the pinned versions in `Package.resolved`
  (Section 4(b) — not triggered).
- Source code is available at the repository URLs above (Section 4(a)).

### 4.2 MIT License (jmespath.swift)

```
MIT License

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be included
in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```

---

## 5. SYSTEM FRAMEWORKS

In addition to the third-party packages above, Bucketeer relies on
first-party Apple system frameworks (Foundation, SwiftUI, SwiftData,
AppKit, FileProvider, StoreKit, LocalAuthentication, CryptoKit,
UniformTypeIdentifiers, Quartz / Quick Look). These are part of macOS
and governed by the Apple Operating System Software License Agreement;
no separate open-source notice applies to them.

---

## 6. SOURCE CODE AVAILABILITY

Source code for every Apache-2.0 and MIT component listed above is
available at the repository URL specified for that component. The
exact versions in the App-Store build of Bucketeer are pinned in
`Package.resolved` in the project repository:

`https://github.com/digitalfreedom-co-za/bucketeer`

For direct requests, contact: hello@digitalfreedom.co.za

---

## 7. UPDATES

This document is regenerated whenever a dependency is added, removed,
or upgraded across a major version. Patch-level upgrades follow the
existing entries' license and copyright lines and do not require a
notice update.

---

(c) 2026 DigitalFreedom — Berger & Rosenstock GbR. The copyright in this
document covers this notice file only; the open-source components
listed herein remain subject to their respective upstream licenses.
