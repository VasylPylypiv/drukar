import Foundation

enum WordFrequency {
    private static let ukrainianScores: [String: Double] = loadScores(from: "ua_freq")
    private static let englishScores: [String: Double] = loadScores(from: "en_freq")

    static func score(of word: String, language: String) -> Double {
        let lowered = word.lowercased()
        if language == "uk" { return ukrainianScores[lowered] ?? 0.0 }
        if language == "en" { return englishScores[lowered] ?? 0.0 }
        return 0.0
    }

    static func isKnown(_ word: String, language: String) -> Bool {
        score(of: word, language: language) > 0.0
    }

    private static func loadScores(from resource: String) -> [String: Double] {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "json") else {
            DrukarLog.warning("WordFrequency: missing \(resource).json in bundle")
            return [:]
        }
        do {
            let data = try Data(contentsOf: url)
            let dict = try JSONDecoder().decode([String: Double].self, from: data)
            DrukarLog.info("WordFrequency: loaded \(dict.count) words from \(resource).json")
            return dict
        } catch {
            DrukarLog.warning("WordFrequency: failed to load \(resource).json — \(error)")
            return [:]
        }
    }
}
