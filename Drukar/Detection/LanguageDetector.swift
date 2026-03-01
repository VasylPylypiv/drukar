import Foundation

final class LanguageDetector {

    static func isUkrainianLayout(_ layoutID: String) -> Bool {
        layoutID.lowercased().contains("ukrainian")
    }

    static func isEnglishLayout(_ layoutID: String) -> Bool {
        layoutID.hasPrefix("com.apple.keylayout.US") ||
        layoutID.hasPrefix("com.apple.keylayout.ABC") ||
        layoutID.hasPrefix("com.apple.keylayout.British") ||
        layoutID.lowercased().contains("english")
    }

    static func isSupportedLayout(_ layoutID: String) -> Bool {
        isUkrainianLayout(layoutID) || isEnglishLayout(layoutID)
    }

    // MARK: - Bigram Scoring

    private static let commonEnglishBigrams: Set<String> = [
        "th", "he", "in", "er", "an", "re", "on", "at", "en", "nd",
        "ti", "es", "or", "te", "of", "ed", "is", "it", "al", "ar",
        "st", "to", "nt", "ng", "se", "ha", "as", "ou", "io", "le",
        "ve", "co", "me", "de", "hi", "ri", "ro", "ic", "ne", "ea",
        "ra", "ce", "li", "ch", "ll", "be", "ma", "si", "om", "ur",
        "ca", "el", "ta", "la", "ns", "ge", "ly", "ei", "no", "pe",
        "ol", "us", "ad", "ss", "ee", "oo", "tt", "il", "lo", "ct",
        "fo", "ho", "di", "tr", "ec", "un", "wh", "wa", "wi", "do",
        "we", "ab", "so", "ac", "ow", "id", "em", "da", "mo", "pr",
        "op", "sh", "up", "go", "if", "ke", "ni", "po", "am", "ot",
        "su", "ub", "bl", "im", "ia", "ie", "ua", "ay", "ey", "oy",
        "ry", "ty", "ny", "my", "by", "gy", "py", "dy", "fy",
        "ul", "ut", "um", "uc", "ud", "uf", "ug", "uh", "uk",
        "pl", "cl", "fl", "gl", "sl", "sp", "sc", "sk", "sm", "sn",
        "sw", "tw", "dw", "fr", "gr", "br", "cr", "dr", "wr", "mp",
        "mb", "nk", "nc", "lf", "ft", "pt", "xt", "lt", "rt", "rn",
        "rm", "rl", "rk", "rc", "rb", "rd", "rf", "rg", "rp", "rs",
        "gh", "ph", "wn", "ld", "lk", "lm", "lp", "ls", "lv", "nf",
        "nm", "nn", "pp", "rr", "ff", "dd", "ck", "wl", "aw", "ew",
        "ai", "au", "oi", "oa", "ue", "ui", "oe",
    ]

    private static let commonUkrainianBigrams: Set<String> = {
        let pairs = [
            "на", "но", "ні", "не", "по", "ст", "ко", "ен", "ра", "ти",
            "ро", "ан", "ер", "ре", "ка", "ов", "ор", "ал", "та", "ін",
            "ла", "ва", "пр", "ри", "ос", "ви", "то", "за", "ар",
            "ів", "ис", "ат", "ол", "ча", "ді", "ак", "ел", "ма", "ло",
            "ий", "ог", "од", "ій", "ик", "ту", "пе", "ле", "ве",
            "ми", "де", "ся", "це", "го", "ці", "як", "тр", "ав", "бу",
            "те", "ки", "до", "мо", "ку", "да", "ли", "іс", "во",
            "ід", "ем", "ам", "би", "об", "ас", "тв", "зн", "із", "бі",
            "се", "сь", "ть", "нь", "ом", "мі", "зі", "їх", "єм", "дл",
            "ук", "ач", "ай", "ей", "ьк", "кі", "зд", "св", "сп", "жи",
            "па", "ап", "пу", "уг", "га", "уд", "ду", "ди", "нк",
            "ок", "бо", "йо", "зе", "мл", "ля",
            "лі", "іт", "тк", "кр", "рі", "іл", "лк", "кл", "лу",
            "ун", "нд", "дн", "нн", "пі", "іч", "чн", "нц", "ір",
            "рк", "кн", "кт", "рн", "іг", "гр", "ру", "ум", "мн",
            "гі", "іш", "шк", "кс", "сн", "нт", "тн", "нз", "зр", "рм",
            "мк", "он", "нс", "сі", "вн", "іб",
            "бл", "сл", "лн", "нг", "гу", "ус", "сц",
            "цю", "юч", "чо", "рт", "тс", "пл", "лю",
            "юб", "бр", "рш", "шт", "ті", "ім", "мп", "пн", "нч",
            "хі", "хо", "ха", "жа", "жн", "жо", "що", "ща",
            "яв", "юд", "єд", "їн", "їз", "їд", "гл", "дм",
            "км", "зб", "зв", "зл", "зм", "зу", "ск", "см",
            "сх", "тл", "тм", "фі", "хр", "цк", "чк", "шн", "шл",
            "ян", "яр", "яс", "ят", "вс", "вд", "вт", "вч", "вк",
            "ще", "чу", "чі", "жу", "же", "ши", "ше", "щу", "юр",
            "їм", "їс", "яю", "ям", "яч", "юн", "юс", "хл", "хв",
            "дв", "оч", "че", "ев", "ид", "ну", "ут", "уч", "чи", "ит", "тя",
            "вр", "рж", "жд", "дж", "жі", "іж",
            "ьо", "ьн", "ьс", "ьб", "ьм", "ьц", "ьш",
            "вп", "пс", "оп", "рп", "вб",
            "ож", "мс", "мр", "мв", "вм",
            "дк", "лд", "лг", "дс", "тч", "чт", "вз", "йт",
            "йд", "йн", "йм", "йс",
            "єт", "тє", "єн", "ює", "єс",
            "їт", "їв", "їж",
            "ба", "аг", "ги", "бе", "ет", "аб", "ег",
            "аз", "зо", "ад", "ез",
        ]
        return Set(pairs)
    }()

    func commonBigramScore(word: String, forUkrainian: Bool) -> Double {
        let letters = word.lowercased().filter { $0.isLetter }
        guard letters.count >= 2 else { return 0.0 }

        let bigramSet = forUkrainian ? Self.commonUkrainianBigrams : Self.commonEnglishBigrams
        let chars = Array(letters)
        var total = 0
        var common = 0

        for i in 0..<(chars.count - 1) {
            let bigram = String([chars[i], chars[i + 1]])
            total += 1
            if bigramSet.contains(bigram) {
                common += 1
            }
        }

        guard total > 0 else { return 0.0 }
        return Double(common) / Double(total)
    }
}
