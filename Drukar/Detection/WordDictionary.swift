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

        guard let first = guesses?.first else { return nil }

        let distance = editDistance(lowered, first.lowercased())
        guard distance <= 1 else { return nil }

        return first
    }

    private func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a)
        let b = Array(b)
        let m = a.count, n = b.count

        if m == 0 { return n }
        if n == 0 { return m }

        var prev = Array(0...n)
        var curr = [Int](repeating: 0, count: n + 1)

        for i in 1...m {
            curr[0] = i
            for j in 1...n {
                if a[i - 1] == b[j - 1] {
                    curr[j] = prev[j - 1]
                } else {
                    curr[j] = min(prev[j - 1], prev[j], curr[j - 1]) + 1
                }
            }
            prev = curr
        }
        return prev[n]
    }
}
