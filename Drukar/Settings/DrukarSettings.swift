import Foundation

final class DrukarSettings: @unchecked Sendable {
    static let shared = DrukarSettings()

    private let defaults = UserDefaults.standard
    private let suiteName = "com.vasylpylypiv.inputmethod.Drukar"

    private enum Keys {
        static let autocorrectEnabled = "autocorrectEnabled"
        static let minWordLength = "minWordLength"
        static let excludedApps = "excludedApps"
        static let customUAWords = "customUAWords"
        static let customENWords = "customENWords"
    }

    private init() {}

    var autocorrectEnabled: Bool {
        get { defaults.object(forKey: Keys.autocorrectEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.autocorrectEnabled) }
    }

    var minWordLength: Int {
        get { defaults.object(forKey: Keys.minWordLength) as? Int ?? 2 }
        set { defaults.set(newValue, forKey: Keys.minWordLength) }
    }

    var excludedApps: [String] {
        get { defaults.stringArray(forKey: Keys.excludedApps) ?? [] }
        set { defaults.set(newValue, forKey: Keys.excludedApps) }
    }

    var customUAWords: [String] {
        get { defaults.stringArray(forKey: Keys.customUAWords) ?? [] }
        set { defaults.set(newValue, forKey: Keys.customUAWords) }
    }

    var customENWords: [String] {
        get { defaults.stringArray(forKey: Keys.customENWords) ?? [] }
        set { defaults.set(newValue, forKey: Keys.customENWords) }
    }

    func isExcludedApp(_ bundleID: String) -> Bool {
        excludedApps.contains(bundleID)
    }

    func isCustomWord(_ word: String, language: String) -> Bool {
        let lowered = word.lowercased()
        if language == "uk" { return customUAWords.contains(lowered) }
        if language == "en" { return customENWords.contains(lowered) }
        return false
    }

    func addCustomWord(_ word: String, language: String) {
        let lowered = word.lowercased()
        if language == "uk" {
            var words = customUAWords
            if !words.contains(lowered) { words.append(lowered); customUAWords = words }
        } else {
            var words = customENWords
            if !words.contains(lowered) { words.append(lowered); customENWords = words }
        }
    }

    func removeCustomWord(_ word: String, language: String) {
        let lowered = word.lowercased()
        if language == "uk" {
            customUAWords = customUAWords.filter { $0 != lowered }
        } else {
            customENWords = customENWords.filter { $0 != lowered }
        }
    }
}
