# Open Source Notices

*Third-party open-source software included in Bucketeer for macOS.*

**Application** — Bucketeer for macOS, including its Finder extension
**Publisher** — DigitalFreedom, a brand of DigitalFreedom Global LLC
**Contact** — hello@digitalfreedom.co.za
**Last updated** — 2 November 2026

---

## 1. Scope

Bucketeer includes the open-source libraries listed below through
Swift Package Manager. The exact versions are pinned in
`Bucketeer.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
in the source repository. The versions given here match that file at
the date above.

These components keep their own licenses. Their inclusion does not
change the terms for Bucketeer itself: the App is governed by the
**End User License Agreement**, its source code by the
**Source-Available License**. Nothing in either restricts the rights
the open-source licenses grant.

---

## 2. Direct dependency

### Soto (SotoS3) 7.14.0

- **Repository** — https://github.com/soto-project/soto
- **License** — Apache License 2.0
- **Copyright** — the Soto project authors
- **Used for** — the S3 protocol client for every S3-compatible
  provider

---

## 3. Indirect dependencies

All licensed under the **Apache License 2.0** unless stated otherwise.

| Component | Version | Repository | Copyright |
|---|---|---|---|
| SotoCore | 7.13.0 | https://github.com/soto-project/soto-core | the Soto project authors |
| jmespath.swift | 1.0.3 | https://github.com/jmespath/jmespath.swift | 2021 Adam Fowler |
| AsyncHTTPClient | 1.33.1 | https://github.com/swift-server/async-http-client | the AsyncHTTPClient project authors |
| Swift Service Lifecycle | 2.11.0 | https://github.com/swift-server/swift-service-lifecycle | the Swift Service Lifecycle project authors |
| SwiftNIO | 2.100.0 | https://github.com/apple/swift-nio | Apple Inc. and the SwiftNIO project authors |
| SwiftNIO Extras | 1.34.1 | https://github.com/apple/swift-nio-extras | Apple Inc. and the SwiftNIO project authors |
| SwiftNIO HTTP/2 | 1.44.0 | https://github.com/apple/swift-nio-http2 | Apple Inc. and the SwiftNIO project authors |
| SwiftNIO SSL | 2.37.0 | https://github.com/apple/swift-nio-ssl | Apple Inc. and the SwiftNIO project authors |
| SwiftNIO Transport Services | 1.28.0 | https://github.com/apple/swift-nio-transport-services | Apple Inc. and the SwiftNIO project authors |
| Swift Crypto | 4.5.0 | https://github.com/apple/swift-crypto | Apple Inc. and the Swift Crypto project authors |
| Swift Certificates | 1.19.1 | https://github.com/apple/swift-certificates | Apple Inc. and the swift-certificates project authors |
| Swift ASN.1 | 1.7.0 | https://github.com/apple/swift-asn1 | Apple Inc. and the swift-asn1 project authors |
| Swift Collections | 1.5.1 | https://github.com/apple/swift-collections | Apple Inc. and the Swift project authors |
| Swift Algorithms | 1.2.1 | https://github.com/apple/swift-algorithms | Apple Inc. and the Swift project authors |
| Swift Async Algorithms | 1.1.4 | https://github.com/apple/swift-async-algorithms | Apple Inc. and the Swift project authors |
| Swift Atomics | 1.3.0 | https://github.com/apple/swift-atomics | Apple Inc. and the Swift project authors |
| Swift Numerics | 1.1.1 | https://github.com/apple/swift-numerics | Apple Inc. and the Swift Numerics project authors |
| Swift System | 1.6.4 | https://github.com/apple/swift-system | Apple Inc. and the Swift System project authors |
| Swift HTTP Types | 1.5.1 | https://github.com/apple/swift-http-types | Apple Inc. and the Swift project authors |
| Swift HTTP Structured Headers | 1.7.0 | https://github.com/apple/swift-http-structured-headers | Apple Inc. and the project authors |
| Swift Log | 1.12.1 | https://github.com/apple/swift-log | Apple Inc. and the SwiftLog project authors |
| Swift Metrics | 2.11.0 | https://github.com/apple/swift-metrics | Apple Inc. and the SwiftMetrics project authors |
| Swift Distributed Tracing | 1.4.1 | https://github.com/apple/swift-distributed-tracing | Apple Inc. and the Swift Distributed Tracing project authors |
| Swift Service Context | 1.3.0 | https://github.com/apple/swift-service-context | Apple Inc. and the Swift Service Context project authors |
| Swift Configuration | 1.2.0 | https://github.com/apple/swift-configuration | Apple Inc. and the Swift Configuration project authors |

### 3.1 BoringSSL

SwiftNIO SSL and Swift Crypto contain a copy of **BoringSSL**
(https://boringssl.googlesource.com/boringssl/). As stated in the
SwiftNIO SSL `NOTICE.txt`, BoringSSL is licensed under a combination of
the ISC license and the OpenSSL license; individual files carry the
notice "Copyright The OpenSSL Project Authors" or "Copyright The
BoringSSL Authors". The license text is available at
https://boringssl.googlesource.com/boringssl/+/refs/heads/master/LICENSE.

---

## 4. License texts

### 4.1 Apache License 2.0

Full text: https://www.apache.org/licenses/LICENSE-2.0

- The copyright notices of each component are listed above.
- The `NOTICE` files of the components are part of their source
  repositories at the pinned versions.
- Bucketeer uses the components unmodified.

### 4.2 ISC license and OpenSSL license (BoringSSL)

See the BoringSSL `LICENSE` file linked in section 3.1, which contains
both license texts in full.

---

## 5. Apple system frameworks

Bucketeer also uses frameworks that are part of macOS (among them
Foundation, SwiftUI, SwiftData, AppKit, FileProvider, StoreKit,
LocalAuthentication, CryptoKit, CryptoTokenKit, CoreSpotlight,
AppIntents, UniformTypeIdentifiers and Quick Look). They are governed by
the macOS software license agreement; no separate open-source notice
applies.

---

## 6. Source code

The source code of every component is available at the repository
listed for it. The source code of Bucketeer is published at
https://github.com/digitalfreedom-co-za/bucketeer under the
Source-Available License. Questions: hello@digitalfreedom.co.za

---

© 2026 DigitalFreedom Global LLC. This copyright covers this notice
only; the listed components remain subject to their own licenses.
