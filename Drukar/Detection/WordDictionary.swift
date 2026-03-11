import AppKit

final class WordDictionary {
    private let checker = NSSpellChecker.shared

    private let uaSymSpell: SymSpell
    private let enSymSpell: SymSpell

    init() {
        uaSymSpell = SymSpell(dictionary: WordFrequency.ukrainianScores)
        enSymSpell = SymSpell(dictionary: WordFrequency.englishScores)
    }

    // MARK: - isKnown: SymSpell(d=0) || NSSpellChecker

    /// High-confidence: word is in our own 50K dictionary (not just NSSpellChecker).
    func isHighConfidence(_ word: String, language: String) -> Bool {
        let lowered = word.lowercased()
        let symspell = language == "uk" ? uaSymSpell : enSymSpell
        return symspell.isKnown(lowered)
    }

    func isKnownUkrainianWord(_ word: String) -> Bool {
        isKnownWord(word, language: "uk")
    }

    func isKnownEnglishWord(_ word: String) -> Bool {
        isKnownWord(word, language: "en")
    }

    func isKnownWord(_ word: String, language: String) -> Bool {
        let lowered = word.lowercased()
        guard lowered.count >= 2 else { return false }

        let symspell = language == "uk" ? uaSymSpell : enSymSpell
        if symspell.isKnown(lowered) { return true }

        let range = checker.checkSpelling(
            of: lowered, startingAt: 0,
            language: language, wrap: false,
            inSpellDocumentWithTag: 0, wordCount: nil
        )
        return range.location == NSNotFound
    }

    // MARK: - Autocorrect: SymSpell fuzzy lookup + double transposition fallback

    func correction(for word: String, language: String) -> String? {
        let lowered = word.lowercased()
        guard lowered.count >= 2 else { return nil }
        guard !isKnownWord(lowered, language: language) else { return nil }

        let symspell = language == "uk" ? uaSymSpell : enSymSpell
        let suggestions = symspell.lookup(lowered)

        if let best = suggestions.first, best.distance > 0 {
            return best.word
        }

        // SymSpell d=1 found nothing — try double transposition for longer words
        if lowered.count >= 5 {
            if let transposed = correctionByDoubleTransposition(lowered, language: language) {
                return transposed
            }
        }

        // Last resort: NSSpellChecker guesses (covers words outside our 50K dictionary)
        return correctionBySpellChecker(lowered, language: language)
    }

    // MARK: - Double Adjacent Transposition

    private func correctionByDoubleTransposition(_ word: String, language: String) -> String? {
        var chars = Array(word)
        guard chars.count >= 3 else { return nil }

        for i in 0..<(chars.count - 1) {
            chars.swapAt(i, i + 1)
            let candidate = String(chars)
            if isKnownWord(candidate, language: language) {
                return candidate
            }
            chars.swapAt(i, i + 1)
        }

        guard chars.count >= 5 else { return nil }
        for i in 0..<(chars.count - 1) {
            chars.swapAt(i, i + 1)
            for j in 0..<(chars.count - 1) where j != i {
                chars.swapAt(j, j + 1)
                let candidate = String(chars)
                if isKnownWord(candidate, language: language) {
                    return candidate
                }
                chars.swapAt(j, j + 1)
            }
            chars.swapAt(i, i + 1)
        }

        return nil
    }

    // MARK: - NSSpellChecker Fallback

    private func correctionBySpellChecker(_ word: String, language: String) -> String? {
        let guesses = checker.guesses(
            forWordRange: NSRange(location: 0, length: word.utf16.count),
            in: word,
            language: language,
            inSpellDocumentWithTag: 0
        )

        guard let guesses, !guesses.isEmpty else { return nil }

        let maxDistance = word.count >= 7 ? 2 : 1

        for guess in guesses.prefix(5) {
            let distance = SymSpell.damerauLevenshtein(word, guess.lowercased())
            if distance <= maxDistance {
                return guess
            }
        }

        return nil
    }
}
