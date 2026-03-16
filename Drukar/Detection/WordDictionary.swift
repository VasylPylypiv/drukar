import Foundation

final class WordDictionary: @unchecked Sendable {
    static let shared = WordDictionary()

    private let uaMapped: MappedDictionary?
    private let enMapped: MappedDictionary?

    private static let ukrainianAlphabet = Array("абвгґдежзиіїйклмнопрстуфхцчшщьюяє'")
    private static let englishAlphabet = Array("abcdefghijklmnopqrstuvwxyz")

    private init() {
        uaMapped = MappedDictionary.load(resource: "words_uk")
        enMapped = MappedDictionary.load(resource: "words_en")
    }

    // MARK: - isKnown: MappedDictionary (VESUM 3.7M / SCOWL 134K)

    func isHighConfidence(_ word: String, language: String) -> Bool {
        let mapped = language == "uk" ? uaMapped : enMapped
        return mapped?.contains(word.lowercased()) == true
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
        return mapped?.contains(lowered) == true
    }

    // MARK: - Autocorrect: Norvig ED=1 over mmap → double transposition

    func correction(for word: String, language: String) -> String? {
        let lowered = word.lowercased()
        guard lowered.count >= 2 else { return nil }
        guard !isKnownWord(lowered, language: language) else { return nil }

        if let norvig = correctionByNorvig(lowered, language: language) {
            return applyCase(from: word, to: norvig)
        }

        if lowered.count >= 5 {
            if let transposed = correctionByDoubleTransposition(lowered, language: language) {
                return applyCase(from: word, to: transposed)
            }
        }

        return nil
    }

    // MARK: - Norvig ED=1: ~700 candidates, binary search in mmap

    private func correctionByNorvig(_ word: String, language: String) -> String? {
        let mapped = language == "uk" ? uaMapped : enMapped
        guard let mapped else { return nil }

        let chars = Array(word)
        let alphabet = language == "uk" ? Self.ukrainianAlphabet : Self.englishAlphabet

        var bestCandidate: String?
        var bestScore: Double = -1

        func check(_ candidate: String) {
            if candidate.count >= 2, mapped.contains(candidate) {
                let score = WordFrequency.score(of: candidate, language: language)
                if score > bestScore {
                    bestScore = score
                    bestCandidate = candidate
                }
            }
        }

        // Deletes
        for i in 0..<chars.count {
            var m = chars; m.remove(at: i); check(String(m))
        }

        // Inserts
        for i in 0...chars.count {
            for ch in alphabet {
                var m = chars; m.insert(ch, at: i); check(String(m))
            }
        }

        // Replaces
        for i in 0..<chars.count {
            let orig = chars[i]
            for ch in alphabet where ch != orig {
                var m = chars; m[i] = ch; check(String(m))
            }
        }

        // Transposes
        for i in 0..<(chars.count - 1) {
            var m = chars; m.swapAt(i, i + 1)
            let c = String(m)
            if c != word { check(c) }
        }

        if let candidate = bestCandidate {
            DrukarLog.debug("norvig: '\(word)' → '\(candidate)'")
        }
        return bestCandidate
    }

    // MARK: - Double Adjacent Transposition (two swaps)

    private func correctionByDoubleTransposition(_ word: String, language: String) -> String? {
        var chars = Array(word)
        guard chars.count >= 5 else { return nil }

        for i in 0..<(chars.count - 1) {
            chars.swapAt(i, i + 1)
            for j in 0..<(chars.count - 1) where j != i {
                chars.swapAt(j, j + 1)
                if isKnownWord(String(chars), language: language) {
                    return String(chars)
                }
                chars.swapAt(j, j + 1)
            }
            chars.swapAt(i, i + 1)
        }
        return nil
    }

    // MARK: - Case Preservation

    private func applyCase(from original: String, to corrected: String) -> String {
        guard !original.isEmpty, !corrected.isEmpty else { return corrected }
        if original == original.uppercased() && original != original.lowercased() {
            return corrected.uppercased()
        }
        if original.first?.isUppercase == true {
            return corrected.prefix(1).uppercased() + corrected.dropFirst()
        }
        return corrected
    }
}
