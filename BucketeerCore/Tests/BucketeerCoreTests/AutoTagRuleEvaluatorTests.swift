//
//  AutoTagRuleEvaluatorTests.swift
//  BucketeerCoreTests
//
//  Created by Marcel R. G. Berger on 24.05.26.
//

import Foundation
import Testing
@testable import BucketeerCore

@Suite("AutoTagRuleEvaluator")
struct AutoTagRuleEvaluatorTests {

    @Test("Empty rule list yields empty results")
    func emptyRules() {
        let result = AutoTagRuleEvaluator.evaluate(rules: [], filename: "x", mime: "x")
        #expect(result.tags.isEmpty)
        #expect(result.userMetadata.isEmpty)
    }

    @Test("Disabled rules are skipped even when patterns match")
    func disabledIgnored() {
        let rule = AutoTagRule(
            name: "off",
            enabled: false,
            filenameGlob: "*.txt",
            tags: ["key": "value"]
        )
        let result = AutoTagRuleEvaluator.evaluate(rules: [rule], filename: "a.txt", mime: nil)
        #expect(result.tags.isEmpty)
    }

    @Test("Empty glob + empty mime matches everything")
    func emptyMatchesAll() {
        let rule = AutoTagRule(name: "any", tags: ["always": "yes"])
        let result = AutoTagRuleEvaluator.evaluate(rules: [rule], filename: "x", mime: nil)
        #expect(result.tags["always"] == "yes")
    }

    @Test("Glob honours wildcards (* and ?)")
    func globWildcards() {
        #expect(AutoTagRuleEvaluator.matchGlob("*.txt", against: "report.txt"))
        #expect(AutoTagRuleEvaluator.matchGlob("report.???", against: "report.txt"))
        #expect(AutoTagRuleEvaluator.matchGlob("*report*", against: "monthly-report-2026.pdf"))
        #expect(!AutoTagRuleEvaluator.matchGlob("*.txt", against: "report.pdf"))
        #expect(!AutoTagRuleEvaluator.matchGlob("a?b", against: "ab"))
    }

    @Test("MIME prefix is case-insensitive and prefix-only")
    func mimePrefix() {
        #expect(AutoTagRuleEvaluator.matchesMIME("image/", mime: "image/jpeg"))
        #expect(AutoTagRuleEvaluator.matchesMIME("Image/", mime: "IMAGE/PNG"))
        #expect(!AutoTagRuleEvaluator.matchesMIME("image/", mime: "video/mp4"))
        #expect(!AutoTagRuleEvaluator.matchesMIME("image/", mime: nil))
    }

    @Test("Multiple rules merge tags + metadata; later rule wins on conflict")
    func mergeOrder() {
        let r1 = AutoTagRule(name: "a", filenameGlob: "*", tags: ["k": "1", "a": "x"])
        let r2 = AutoTagRule(name: "b", filenameGlob: "*", tags: ["k": "2", "b": "y"])
        let result = AutoTagRuleEvaluator.evaluate(rules: [r1, r2], filename: "f", mime: nil)
        #expect(result.tags["k"] == "2")
        #expect(result.tags["a"] == "x")
        #expect(result.tags["b"] == "y")
    }
}
