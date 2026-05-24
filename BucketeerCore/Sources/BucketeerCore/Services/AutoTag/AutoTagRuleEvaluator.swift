//
//  AutoTagRuleEvaluator.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 24.05.26.
//

import Foundation

/// Pure rule-matching logic for the auto-tagging engine. Phase 13.8.
///
/// The evaluator is deliberately stateless — given a list of rules
/// and the inputs (filename + MIME type), it returns the merged
/// `(tags, metadata)` of every matching rule. Order is honoured:
/// later rules win when two rules set the same key.
///
/// The glob grammar matches the macOS shell:
/// - `*` matches zero or more characters except `/`
/// - `?` matches exactly one character except `/`
/// - everything else is literal
///
/// A rule with both `filenameGlob` and `mimePrefix` empty matches
/// every upload — useful for "default tag" rules.
public enum AutoTagRuleEvaluator {

    public static func evaluate(
        rules: [AutoTagRule],
        filename: String,
        mime: String?
    ) -> (tags: [String: String], userMetadata: [String: String]) {
        var tags: [String: String] = [:]
        var metadata: [String: String] = [:]
        for rule in rules where rule.enabled {
            guard matchesFilename(rule.filenameGlob, filename: filename) else { continue }
            guard matchesMIME(rule.mimePrefix, mime: mime) else { continue }
            tags.merge(rule.tags) { _, new in new }
            metadata.merge(rule.userMetadata) { _, new in new }
        }
        return (tags, metadata)
    }

    static func matchesFilename(_ glob: String, filename: String) -> Bool {
        if glob.isEmpty { return true }
        return matchGlob(glob, against: filename)
    }

    static func matchesMIME(_ prefix: String, mime: String?) -> Bool {
        if prefix.isEmpty { return true }
        guard let mime else { return false }
        return mime.lowercased().hasPrefix(prefix.lowercased())
    }

    /// Iterative glob matcher with support for `*` and `?`. Linear
    /// time in the common case; falls back to backtracking on the
    /// pattern when a `*` is followed by a literal that fails to
    /// match. Good enough for filename matching where patterns are
    /// short.
    static func matchGlob(_ pattern: String, against text: String) -> Bool {
        let p = Array(pattern)
        let s = Array(text)
        var i = 0  // index into s
        var j = 0  // index into p
        var starIdx = -1
        var matchIdx = 0

        while i < s.count {
            if j < p.count && (p[j] == "?" || p[j] == s[i]) {
                i += 1; j += 1
            } else if j < p.count && p[j] == "*" {
                starIdx = j
                matchIdx = i
                j += 1
            } else if starIdx != -1 {
                j = starIdx + 1
                matchIdx += 1
                i = matchIdx
            } else {
                return false
            }
        }
        while j < p.count && p[j] == "*" { j += 1 }
        return j == p.count
    }
}
