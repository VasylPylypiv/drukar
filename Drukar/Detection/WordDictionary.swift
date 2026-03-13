import AppKit

final class WordDictionary {
    private let uaSymSpell: SymSpell
    private let enSymSpell: SymSpell
    private let uaMapped: MappedDictionary?
    private let enMapped: MappedDictionary?

    init() {
        uaSymSpell = SymSpell(dictionary: WordFrequency.ukrainianScores)
        enSymSpell = SymSpell(dictionary: WordFrequency.englishScores)
        uaMapped = MappedDictionary.load(resource: "words_uk")
        enMapped = MappedDictionary.load(resource: "words_en")
    }

    // MARK: - isKnown: MappedDictionary (VESUM/SCOWL) → SymSpell

    /// High-confidence: word is in our own dictionaries (VESUM/SCOWL/SymSpell).
    func isHighConfidence(_ word: String, language: String) -> Bool {
        let lowered = word.lowercased()
        let mapped = language == "uk" ? uaMapped : enMapped
        if mapped?.contains(lowered) == true { return true }
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

        let mapped = language == "uk" ? uaMapped : enMapped
        if mapped?.contains(lowered) == true { return true }

        let symspell = language == "uk" ? uaSymSpell : enSymSpell
        if symspell.isKnown(lowered) { return true }

        return false
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

        if lowered.count >= 5 {
            if let transposed = correctionByDoubleTransposition(lowered, language: language) {
                return transposed
            }
        }

        return nil
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
}
