import AppKit

final class WordDictionary {
    private let checker = NSSpellChecker.shared

    func isKnownUkrainianWord(_ word: String) -> Bool {
        let lowered = word.lowercased()
        guard lowered.count >= 2 else { return false }
        let range = checker.checkSpelling(
            of: lowered, startingAt: 0,
            language: "uk", wrap: false,
            inSpellDocumentWithTag: 0, wordCount: nil
        )
        return range.location == NSNotFound
    }

    func isKnownEnglishWord(_ word: String) -> Bool {
        let lowered = word.lowercased()
        guard lowered.count >= 2 else { return false }
        let range = checker.checkSpelling(
            of: lowered, startingAt: 0,
            language: "en", wrap: false,
            inSpellDocumentWithTag: 0, wordCount: nil
        )
        return range.location == NSNotFound
    }
}
