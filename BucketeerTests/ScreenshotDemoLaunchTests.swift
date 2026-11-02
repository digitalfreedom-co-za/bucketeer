//
//  ScreenshotDemoLaunchTests.swift
//  BucketeerTests
//
//  Created by Marcel R. G. Berger on 02.11.26.
//

import XCTest

/// The screenshot demo replaces the user's data with in-memory demo
/// data, so it must only switch on in the QA copy *and* with the launch
/// flag. Release builds do not contain the type at all (`#if DEBUG`).
final class ScreenshotDemoLaunchTests: XCTestCase {
    private let flag = ["-BucketeerScreenshotDemo", "YES"]
    private let qaID = ScreenshotDemoLaunch.qaBundleIdentifier

    func testActivationNeedsFlagAndQABundleIdentifier() {
        let launch = ScreenshotDemoLaunch.parse(
            arguments: ["Bucketeer"] + flag + ["-BucketeerDemoScreen", "04_versions", "-BucketeerDemoSeed", "/seed.json"],
            bundleIdentifier: qaID
        )
        XCTAssertEqual(launch, ScreenshotDemoLaunch(screen: .versions, seedPath: "/seed.json"))

        XCTAssertNil(ScreenshotDemoLaunch.parse(arguments: flag, bundleIdentifier: "za.co.digitalfreedom.Bucketeer"))
        XCTAssertNil(ScreenshotDemoLaunch.parse(arguments: flag, bundleIdentifier: nil))
        XCTAssertNil(ScreenshotDemoLaunch.parse(arguments: [], bundleIdentifier: qaID))
        XCTAssertNil(ScreenshotDemoLaunch.parse(arguments: ["-BucketeerScreenshotDemo", "NO"], bundleIdentifier: qaID))
        XCTAssertNil(ScreenshotDemoLaunch.parse(arguments: ["-BucketeerScreenshotDemo"], bundleIdentifier: qaID))
    }
}
