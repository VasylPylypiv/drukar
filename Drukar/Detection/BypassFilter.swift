import Foundation

/// Determines if a token should bypass language detection entirely.
/// Code identifiers, abbreviations, URLs etc. are passed through as-is in English.
enum BypassFilter {

    /// Returns true if the word should skip language detection and be committed as EN.
    static func shouldBypass(enWord: String, uaWord: String) -> Bool {
        let en = enWord.filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" || $0 == "." || $0 == "@" || $0 == "#" || $0 == "/" }
        guard !en.isEmpty else { return false }

        if containsDigits(en) { return true }
        if isAllCapsLatin(en) { return true }
        if isCamelOrPascalCase(en) { return true }
        if isSnakeCase(en) { return true }
        if looksLikePathOrURL(en) { return true }
        if isHashtagOrMention(enWord) { return true }

        return false
    }

    // MARK: - Rules

    private static func containsDigits(_ word: String) -> Bool {
        word.contains(where: { $0.isNumber })
    }

    private static func isAllCapsLatin(_ word: String) -> Bool {
        let letters = word.filter { $0.isLetter }
        guard letters.count >= 2 else { return false }
        return letters.allSatisfy { $0.isUppercase && $0.isASCII }
    }

    private static func isCamelOrPascalCase(_ word: String) -> Bool {
        let letters = word.filter { $0.isLetter }
        guard letters.count >= 4 else { return false }
        guard letters.allSatisfy({ $0.isASCII }) else { return false }
        let hasLower = letters.contains(where: { $0.isLowercase })
        let hasInternalUpper = letters.dropFirst().contains(where: { $0.isUppercase })
        return hasLower && hasInternalUpper
    }

    private static func isSnakeCase(_ word: String) -> Bool {
        guard word.contains("_") else { return false }
        let parts = word.split(separator: "_")
        guard parts.count >= 2 else { return false }
        return parts.allSatisfy { part in
            part.allSatisfy { $0.isLetter && $0.isASCII || $0.isNumber }
        }
    }

    private static func looksLikePathOrURL(_ word: String) -> Bool {
        if word.contains("://") { return true }
        if word.contains("@") && word.contains(".") { return true }
        if word.hasPrefix("/") || word.hasPrefix("~/") || word.hasPrefix("./") { return true }
        if word.contains("/") && word.contains(".") { return true }
        return false
    }

    private static func isHashtagOrMention(_ word: String) -> Bool {
        if word.hasPrefix("#") || word.hasPrefix("@") { return true }
        return false
    }
}
