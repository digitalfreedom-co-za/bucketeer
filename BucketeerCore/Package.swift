// swift-tools-version: 6.0
import PackageDescription

/// Shared models + services used by both the **Bucketeer** host app and
/// the **Bucketeer File Provider** extension. Keeps Sendable value
/// types, Keychain / SwiftData stores, the Soto S3 client factory, and
/// the Azure Blob backend in one place so the extension can read user
/// accounts and stream objects without duplicating any of it.
///
/// Phase 9.5 deliverable. Host-only code (composition root, ViewModels,
/// SwiftUI views, StoreKit gating, drag-and-drop coordinator) stays in
/// the host target.
let package = Package(
    name: "BucketeerCore",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "BucketeerCore",
            targets: ["BucketeerCore"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/soto-project/soto", from: "7.0.0")
    ],
    targets: [
        .target(
            name: "BucketeerCore",
            dependencies: [
                .product(name: "SotoS3", package: "soto")
            ],
            path: "Sources/BucketeerCore"
        ),
        .testTarget(
            name: "BucketeerCoreTests",
            dependencies: ["BucketeerCore"],
            path: "Tests/BucketeerCoreTests"
        )
    ]
)
