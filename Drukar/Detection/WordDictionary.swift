import AppKit

final class WordDictionary: @unchecked Sendable {
    static let shared = WordDictionary()

    private let uaSymSpell: SymSpell
    private let enSymSpell: SymSpell
    private let uaMapped: MappedDictionary?
    private let enMapped: MappedDictionary?

    private static let ukrainianAlphabet = Array("абвгґдежзиіїйклмнопрстуфхцчшщьюяє")
    private static let englishAlphabet = Array("abcdefghijklmnopqrstuvwxyz")

    private init() {
        uaSymSpell = SymSpell(dictionary: WordFrequency.ukrainianScores)
        enSymSpell = SymSpell(dictionary: WordFrequency.englishScores)
        uaMapped = MappedDictionary.load(resource: "words_uk")
        enMapped = MappedDictionary.load(resource: "words_en")
    }

    // MARK: - isKnown: MappedDictionary (VESUM/SCOWL) → SymSpell

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

    // MARK: - Autocorrect: SymSpell → Norvig+mmap → double transposition

    func correction(for word: String, language: String) -> String? {
        let lowered = word.lowercased()
        guard lowered.count >= 2 else { return nil }
        guard !isKnownWord(lowered, language: language) else { return nil }

        // Level 1: SymSpell (150K frequent words, O(1))
        let symspell = language == "uk" ? uaSymSpell : enSymSpell
        let suggestions = symspell.lookup(lowered)
        if let best = suggestions.first, best.distance > 0 {
            return best.word
        }

        // Level 2: Norvig ED=1 over mmap (3.7M VESUM / 134K SCOWL, O(n·log N))
        if let norvig = correctionByNorvig(lowered, language: language) {
            return norvig
        }

        // Level 3: Double transposition (two adjacent swaps, validated via mmap)
        if lowered.count >= 5 {
            if let transposed = correctionByDoubleTransposition(lowered, language: language) {
                return transposed
            }
        }

        return nil
    }

    // MARK: - Norvig ED=1: generate ~700 candidates, binary search in mmap

    private func correctionByNorvig(_ word: String, language: String) -> String? {
        let mapped = language == "uk" ? uaMapped : enMapped
        guard let mapped else { return nil }

        let chars = Array(word)
        let alphabet = language == "uk" ? Self.ukrainianAlphabet : Self.englishAlphabet
        let symspell = language == "uk" ? uaSymSpell : enSymSpell

        var bestCandidate: String?
        var bestScore: Double = -1

        // Deletes: remove one character
        for i in 0..<chars.count {
            var modified = chars
            modified.remove(at: i)
            let candidate = String(modified)
            if candidate.count >= 2, mapped.contains(candidate) {
                let score = symspell.score(of: candidate)
                if score > bestScore { bestScore = score; bestCandidate = candidate }
            }
        }

        // Inserts: add one character at each position
        for i in 0...chars.count {
            for ch in alphabet {
                var modified = chars
                modified.insert(ch, at: i)
                let candidate = String(modified)
                if mapped.contains(candidate) {
                    let score = symspell.score(of: candidate)
                    if score > bestScore { bestScore = score; bestCandidate = candidate }
                }
            }
        }

        // Replaces: swap one character for another
        for i in 0..<chars.count {
            let original = chars[i]
            for ch in alphabet where ch != original {
                var modified = chars
                modified[i] = ch
                let candidate = String(modified)
                if mapped.contains(candidate) {
                    let score = symspell.score(of: candidate)
                    if score > bestScore { bestScore = score; bestCandidate = candidate }
                }
            }
        }

        // Transposes: swap two adjacent characters
        for i in 0..<(chars.count - 1) {
            var modified = chars
            modified.swapAt(i, i + 1)
            let candidate = String(modified)
            if candidate != word, mapped.contains(candidate) {
                let score = symspell.score(of: candidate)
                if score > bestScore { bestScore = score; bestCandidate = candidate }
            }
        }

        if let candidate = bestCandidate {
            DrukarLog.debug("norvig: '\(word)' → '\(candidate)' (score=\(String(format: "%.2f", bestScore)))")
        }
        return bestCandidate
    }

    // MARK: - Double Adjacent Transposition

    private func correctionByDoubleTransposition(_ word: String, language: String) -> String? {
        var chars = Array(word)
        guard chars.count >= 3 else { return nil }

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
