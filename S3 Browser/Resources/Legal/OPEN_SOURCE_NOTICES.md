# OPEN SOURCE NOTICES

## Third-Party Open Source Software Used by S3 Browser

**Last Updated:** May 2026

**Publisher:**
DigitalFreedom — a brand of Berger & Rosenstock GbR
Dieselstr. 22e, 61231 Bad Nauheim, Germany
Contact: hello@digitalfreedom.co.za

---

## 1. INTRODUCTION

S3 Browser includes the following open-source software. Each component
is subject to its own license terms, reproduced or referenced below.

Inclusion of these components in S3 Browser does not extend any
redistribution rights to the App as a whole; the App is distributed
under the Publisher's [Source-Available License](../../LICENSE) for the
source code and the [End User License Agreement](EULA.md) for the binary.

---

## 2. COMPONENTS

### 2.1 Soto

```
Component: Soto (SotoS3)
Project:   soto-project/soto
License:   Apache-2.0
Copyright: Copyright 2017-2026 the Soto project authors
Repository: https://github.com/soto-project/soto
```

Pure-Swift SDK for AWS and S3-compatible services. Used by S3 Browser
for all S3 protocol operations.

### 2.2 Soto Core

```
Component: SotoCore
Project:   soto-project/soto-core
License:   Apache-2.0
Copyright: Copyright 2017-2026 the Soto project authors
Repository: https://github.com/soto-project/soto-core
```

Transitive dependency of Soto.

### 2.3 SwiftNIO

```
Component: SwiftNIO
Project:   apple/swift-nio
License:   Apache-2.0
Copyright: Copyright (c) 2017-2026 Apple Inc. and the SwiftNIO project authors
Repository: https://github.com/apple/swift-nio
```

Transitive dependency of Soto Core.

### 2.4 AsyncHTTPClient

```
Component: AsyncHTTPClient
Project:   swift-server/async-http-client
License:   Apache-2.0
Copyright: Copyright (c) 2018-2026 the AsyncHTTPClient project authors
Repository: https://github.com/swift-server/async-http-client
```

Transitive dependency of Soto Core.

### 2.5 SwiftCrypto

```
Component: SwiftCrypto
Project:   apple/swift-crypto
License:   Apache-2.0
Copyright: Copyright (c) 2019-2026 Apple Inc. and the SwiftCrypto project authors
Repository: https://github.com/apple/swift-crypto
```

Transitive dependency of Soto Core.

### 2.6 SwiftLog

```
Component: SwiftLog
Project:   apple/swift-log
License:   Apache-2.0
Copyright: Copyright (c) 2018-2026 Apple Inc. and the SwiftLog project authors
Repository: https://github.com/apple/swift-log
```

Transitive dependency of Soto Core.

### 2.7 SwiftMetrics

```
Component: SwiftMetrics
Project:   apple/swift-metrics
License:   Apache-2.0
Copyright: Copyright (c) 2018-2026 Apple Inc. and the SwiftMetrics project authors
Repository: https://github.com/apple/swift-metrics
```

Transitive dependency of Soto Core.

---

## 3. APACHE LICENSE 2.0

All components listed above are licensed under the Apache License,
Version 2.0 ("License"). The full text of the License is available at:

<https://www.apache.org/licenses/LICENSE-2.0>

Excerpt — Notice file requirement (Section 4(d)):

> If the Work includes a "NOTICE" text file as part of its distribution,
> then any Derivative Works that You distribute must include a readable
> copy of the attribution notices contained within such NOTICE file,
> excluding those notices that do not pertain to any part of the
> Derivative Works.

The full NOTICE files of the components above are reproduced verbatim in
the in-App "About → Open Source Notices" view.

---

## 4. SOURCE CODE AVAILABILITY

Source code for the Apache-2.0 components above is available at the
repository URLs listed for each component. The pinned versions used by
S3 Browser are recorded in `Package.resolved` in the project repository.

For requests directly to the Publisher, contact:
hello@digitalfreedom.co.za

---

## 5. UPDATES

This document is updated whenever a dependency is added, removed, or
upgraded across a major version. Pinned versions for the current release
live in the `Package.resolved` of the App Store build.

---

(c) 2026 DigitalFreedom — Berger & Rosenstock GbR. The copyright notice
in this section applies to this document only, not to the open-source
components listed herein, which are subject to their respective licenses.
