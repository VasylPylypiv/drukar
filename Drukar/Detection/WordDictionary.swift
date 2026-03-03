import AppKit

final class WordDictionary {
    private let checker = NSSpellChecker.shared

    func isKnownUkrainianWord(_ word: String) -> Bool {
        isKnownWord(word, language: "uk")
    }

    func isKnownEnglishWord(_ word: String) -> Bool {
        isKnownWord(word, language: "en")
    }

    func isKnownWord(_ word: String, language: String) -> Bool {
        let lowered = word.lowercased()
        guard lowered.count >= 2 else { return false }
        let range = checker.checkSpelling(
            of: lowered, startingAt: 0,
            language: language, wrap: false,
            inSpellDocumentWithTag: 0, wordCount: nil
        )
        return range.location == NSNotFound
    }

    /// Returns the best correction for a misspelled word, or nil if no good correction exists.
    func correction(for word: String, language: String) -> String? {
        let lowered = word.lowercased()
        guard lowered.count >= 2 else { return nil }

        guard !isKnownWord(lowered, language: language) else { return nil }

        let guesses = checker.guesses(
            forWordRange: NSRange(location: 0, length: lowered.utf16.count),
            in: lowered,
            language: language,
            inSpellDocumentWithTag: 0
        )

        guard let guesses, !guesses.isEmpty else { return nil }

        for guess in guesses.prefix(5) {
            let distance = editDistance(lowered, guess.lowercased())
            if distance <= 1 {
                return guess
            }
        }

        return nil
    }

    /// Damerau-Levenshtein distance: counts transpositions as single edit
    private func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a)
        let b = Array(b)
        let m = a.count, n = b.count

        if m == 0 { return n }
        if n == 0 { return m }

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
