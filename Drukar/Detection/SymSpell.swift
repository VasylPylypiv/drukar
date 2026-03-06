import Foundation

/// Symmetric Delete Spelling Correction (SymSpell) — fast fuzzy lookup.
/// Pre-computes all delete variants at init, then lookups are O(1) hash checks.
final class SymSpell: @unchecked Sendable {
    struct SuggestionResult {
        let word: String
        let distance: Int
        let score: Double
    }

    private let maxEditDistance: Int
    private let prefixLength: Int
    private let words: [String: Double]
    private let deletes: [String: [String]]

    /// Build SymSpell index from a word→score dictionary.
    /// - Parameters:
    ///   - dictionary: word→log_score mapping (e.g. from ua_freq.json)
    ///   - maxEditDistance: maximum edit distance for lookups (1 recommended)
    ///   - prefixLength: prefix length for key generation (7 recommended)
    init(dictionary: [String: Double], maxEditDistance: Int = 1, prefixLength: Int = 7) {
        self.maxEditDistance = maxEditDistance
        self.prefixLength = prefixLength
        self.words = dictionary

        var deletesMap: [String: [String]] = [:]
        deletesMap.reserveCapacity(dictionary.count * 8)

        for word in dictionary.keys {
            let edits = SymSpell.generateEditsWithinDistance(word, maxDistance: maxEditDistance, prefixLength: prefixLength)
            for edit in edits {
                deletesMap[edit, default: []].append(word)
            }
        }

        self.deletes = deletesMap
        DrukarLog.info("SymSpell: indexed \(dictionary.count) words, \(deletesMap.count) delete keys")
    }

    /// Exact match check (distance = 0). O(1).
    func isKnown(_ word: String) -> Bool {
        words[word.lowercased()] != nil
    }

    /// Score for exact match. Returns 0 if word is unknown.
    func score(of word: String) -> Double {
        words[word.lowercased()] ?? 0.0
    }

    /// Find spelling suggestions within maxEditDistance.
    /// Returns candidates sorted by: distance ASC, score DESC.
    func lookup(_ input: String, maxDistance: Int? = nil) -> [SuggestionResult] {
        let lowered = input.lowercased()
        let distance = min(maxDistance ?? maxEditDistance, maxEditDistance)

        if let s = words[lowered] {
            return [SuggestionResult(word: lowered, distance: 0, score: s)]
        }

        var candidates: [String: SuggestionResult] = [:]

        let inputEdits = SymSpell.generateEditsWithinDistance(lowered, maxDistance: distance, prefixLength: prefixLength)
        for edit in inputEdits {
            if let originals = deletes[edit] {
                for original in originals {
                    guard candidates[original] == nil else { continue }
                    let d = SymSpell.damerauLevenshtein(lowered, original)
                    if d <= distance {
                        let s = words[original] ?? 0.0
                        candidates[original] = SuggestionResult(word: original, distance: d, score: s)
                    }
                }
            }
        }

        // Also check: the input itself might be a delete of a dictionary word (insertion errors)
        // This is handled by checking if any dictionary word's deletes match the input
        if let originals = deletes[lowered] {
            for original in originals {
                guard candidates[original] == nil else { continue }
                let d = SymSpell.damerauLevenshtein(lowered, original)
                if d <= distance {
                    let s = words[original] ?? 0.0
                    candidates[original] = SuggestionResult(word: original, distance: d, score: s)
                }
            }
        }

        return candidates.values.sorted { a, b in
            if a.distance != b.distance { return a.distance < b.distance }
            return a.score > b.score
        }
    }

    // MARK: - Delete Generation

    /// Generate all strings within `maxDistance` deletes, truncated to `prefixLength`.
    private static func generateEditsWithinDistance(_ word: String, maxDistance: Int, prefixLength: Int) -> Set<String> {
        let chars = Array(word)
        let truncated = chars.count > prefixLength ? Array(chars.prefix(prefixLength)) : chars
        var result = Set<String>()
        generateDeletes(String(truncated), distance: maxDistance, results: &result)
        return result
    }

    private static func generateDeletes(_ word: String, distance: Int, results: inout Set<String>) {
        let chars = Array(word)
        guard distance > 0, chars.count > 1 else { return }

        for i in 0..<chars.count {
            var modified = chars
            modified.remove(at: i)
            let candidate = String(modified)
            if results.insert(candidate).inserted {
                generateDeletes(candidate, distance: distance - 1, results: &results)
            }
        }
    }

    // MARK: - Damerau-Levenshtein Distance

    static func damerauLevenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a)
        let b = Array(b)
        let m = a.count, n = b.count

        if m == 0 { return n }
        if n == 0 { return m }
        if abs(m - n) > 2 { return max(m, n) }

        var prev2 = [Int](repeating: 0, count: n + 1)
        var prev = Array(0...n)
        var curr = [Int](repeating: 0, count: n + 1)

        for i in 1...m {
            curr[0] = i
            for j in 1...n {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                curr[j] = min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
                if i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1] {
                    curr[j] = min(curr[j], prev2[j - 2] + cost)
                }
            }
            prev2 = prev
            prev = curr
        }
        return prev[n]
    }
}
