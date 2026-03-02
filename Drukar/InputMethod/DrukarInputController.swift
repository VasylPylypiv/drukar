import Cocoa
import InputMethodKit
import Carbon.HIToolbox

/// Main input controller — one instance per client (app window).
/// IMK calls `handle(_:client:)` for each key event BEFORE it reaches the app.
/// We MUST handle all printable input — returning false means the keystroke is dropped.
class DrukarInputController: IMKInputController {
    private let buffer = DualBuffer()
    private let detector = LanguageDetector()
    private let characterMapper = CharacterMapper()
    private let dictionary = WordDictionary()

    private var enLayoutID: String?
    private var uaLayoutID: String?
    private var mapsReady = false

    private var composingText = ""

    // MARK: - Input Mode

    enum InputMode {
        case auto
        case english
    }

    // Mode is determined by Caps Lock state: LED on = English, LED off = Auto
    private var mode: InputMode {
        // Check actual hardware Caps Lock state
        NSEvent.modifierFlags.contains(.capsLock) ? .english : .auto
    }

    // MARK: - Lifecycle

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)
        resolveLayouts()
    }

    private static let excludedBundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "net.kovidgoyal.kitty",
        "com.github.wez.wezterm",
        "co.zeit.hyper",
        "dev.warp.Warp-Stable",
    ]

    private var isExcludedApp = false

    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        buffer.clear()
        composingText = ""
        if !mapsReady { resolveLayouts() }

        if let client = sender as? IMKTextInput {
            let bundleID = client.bundleIdentifier() ?? ""
            isExcludedApp = Self.excludedBundleIDs.contains(bundleID)
            DrukarLog.info("activateServer: mapsReady=\(mapsReady) app=\(bundleID) excluded=\(isExcludedApp)")
        }
    }

    override func deactivateServer(_ sender: Any!) {
        commitComposingText(sender as? IMKTextInput)
        buffer.clear()
        composingText = ""
        super.deactivateServer(sender)
    }

    override func commitComposition(_ sender: Any!) {
        DrukarLog.debug("commitComposition called, composing='\(composingText)'")
        if let client = sender as? IMKTextInput {
            commitComposingText(client)
        } else {
            composingText = ""
            buffer.clear()
        }
    }

    // MARK: - Event Handling

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, event.type == .keyDown else { return false }
        guard let client = sender as? IMKTextInput else { return false }

        if isExcludedApp { return false }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if modifiers.contains(.command) || modifiers.contains(.control) {
            commitComposingText(client)
            return false
        }

        let keyCode = event.keyCode

        if keyCode == UInt16(kVK_Delete) {
            return handleBackspace(client: client)
        }

        if keyCode == UInt16(kVK_Escape) {
            if composingText.isEmpty { return false }
            cancelComposingText(client)
            return true
        }

        if isArrowOrNavigationKey(keyCode) {
            commitComposingText(client)
            return false
        }

        // Any function keys or unknown keys — commit and pass through
        if keyCode > 0x7E {
            commitComposingText(client)
            return false
        }

        if DualBuffer.wordBoundaryKeyCodes.contains(keyCode) {
            let isSpace = keyCode == 0x31
            if mode == .english {
                commitComposingText(client)
                return !isSpace ? false : {
                    client.insertText(" ", replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
                    return true
                }()
            }
            handleWordBoundary(keyCode: keyCode, insertBoundary: isSpace, client: client)
            return isSpace
        }

        return handleCharacterInput(event: event, keyCode: keyCode, client: client)
    }

    // MARK: - Character Input

    private func handleCharacterInput(event: NSEvent, keyCode: UInt16, client: IMKTextInput) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isShifted = modifiers.contains(.shift)

        // EN mode: insert English character directly, no buffering
        if mode == .english {
            if mapsReady, let enID = enLayoutID {
                if let enChar = characterMapper.characterForKeyCode(keyCode, shifted: isShifted, sourceID: enID) {
                    client.insertText(String(enChar), replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
                    return true
                }
            }
            if let chars = event.characters, !chars.isEmpty {
                client.insertText(chars, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
                return true
            }
            return false
        }

        // Auto mode: buffer and detect
        if mapsReady, let enID = enLayoutID, let uaID = uaLayoutID {
            let enChar = characterMapper.characterForKeyCode(keyCode, shifted: isShifted, sourceID: enID)
            let uaChar = characterMapper.characterForKeyCode(keyCode, shifted: isShifted, sourceID: uaID)

            if enChar != nil || uaChar != nil {
                buffer.append(DualKeystroke(keyCode: keyCode, enChar: enChar, uaChar: uaChar, isShifted: isShifted))

                let typedChar = pickDisplayCharacter(enChar: enChar, uaChar: uaChar)
                if let ch = typedChar {
                    composingText.append(ch)
                    updateMarkedText(composingText, client: client)
                    return true
                }
            }
        }

        // Fallback: maps not ready or unmapped key — insert event's characters directly
        if let chars = event.characters, !chars.isEmpty {
            commitComposingText(client)
            client.insertText(chars, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
            return true
        }

        return false
    }

    private var detectedLanguageIsUkrainian = true

    private func pickDisplayCharacter(enChar: Character?, uaChar: Character?) -> Character? {
        if detectedLanguageIsUkrainian {
            return uaChar ?? enChar
        }
        return enChar ?? uaChar
    }

    // MARK: - Word Boundary

    private func handleWordBoundary(keyCode: UInt16, insertBoundary: Bool, client: IMKTextInput) {
        let boundaryChar = wordBoundaryCharacter(for: keyCode)

        guard !buffer.isEmpty else {
            if insertBoundary {
                // Clear any stale marked text state before inserting
                if !composingText.isEmpty {
                    composingText = ""
                    client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0),
                                         replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
                }
                client.insertText(boundaryChar, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
            }
            return
        }

        let enWord = buffer.enWord
        let uaWord = buffer.uaWord
        buffer.clear()
        composingText = ""

        let correctedWord = evaluateBestInterpretation(enWord: enWord, uaWord: uaWord)
        detectedLanguageIsUkrainian = (correctedWord == uaWord)
        DrukarLog.debug("boundary: en='\(enWord)' ua='\(uaWord)' → '\(correctedWord)' (nextUA=\(detectedLanguageIsUkrainian))")

        let textToInsert = insertBoundary ? correctedWord + boundaryChar : correctedWord
        client.insertText(textToInsert, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
    }

    private func wordBoundaryCharacter(for keyCode: UInt16) -> String {
        switch keyCode {
        case 0x31: return " "
        case 0x24: return "\n"
        case 0x30: return "\t"
        case 0x4C: return "\n"
        default: return " "
        }
    }

    // MARK: - Backspace

    private func handleBackspace(client: IMKTextInput) -> Bool {
        DrukarLog.debug("backspace: composing='\(composingText)' bufferCount=\(buffer.keystrokeCount)")
        if composingText.isEmpty && buffer.isEmpty {
            return false
        }
        if composingText.isEmpty && !buffer.isEmpty {
            buffer.clear()
            return false
        }
        composingText.removeLast()
        buffer.removeLast()
        if composingText.isEmpty {
            cancelComposingText(client)
        } else {
            updateMarkedText(composingText, client: client)
        }
        return true
    }

    // MARK: - Navigation Keys

    private func isArrowOrNavigationKey(_ keyCode: UInt16) -> Bool {
        let navKeys: Set<UInt16> = [
            UInt16(kVK_UpArrow), UInt16(kVK_DownArrow),
            UInt16(kVK_LeftArrow), UInt16(kVK_RightArrow),
            UInt16(kVK_Home), UInt16(kVK_End),
            UInt16(kVK_PageUp), UInt16(kVK_PageDown),
            UInt16(kVK_F1), UInt16(kVK_F2), UInt16(kVK_F3), UInt16(kVK_F4),
            UInt16(kVK_F5), UInt16(kVK_F6), UInt16(kVK_F7), UInt16(kVK_F8),
        ]
        return navKeys.contains(keyCode)
    }

    // MARK: - Marked Text (Composing Region)

    private func updateMarkedText(_ text: String, client: IMKTextInput) {
        let attrs: [NSAttributedString.Key: Any] = [
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        let attributed = NSAttributedString(string: text, attributes: attrs)
        client.setMarkedText(attributed, selectionRange: NSRange(location: text.count, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
    }

    private func commitComposingText(_ client: IMKTextInput?) {
        guard !composingText.isEmpty, let client else { return }
        client.insertText(composingText, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
        composingText = ""
        buffer.clear()
    }

    private func cancelComposingText(_ client: IMKTextInput) {
        composingText = ""
        buffer.clear()
        client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
    }

    // MARK: - Detection Logic

    private static let singleLetterUA: Set<String> = ["і", "я", "в", "з", "у", "о", "а", "й", "ж", "є"]
    private static let singleLetterEN: Set<String> = ["i", "a"]

    private func evaluateBestInterpretation(enWord: String, uaWord: String) -> String {
        let enLetters = String(enWord.filter { $0.isLetter })
        let uaLetters = String(uaWord.filter { $0.isLetter })

        if enLetters.count <= 1 && uaLetters.count <= 1 {
            let enLower = enLetters.lowercased()
            let uaLower = uaLetters.lowercased()
            let enIsSingle = Self.singleLetterEN.contains(enLower)
            let uaIsSingle = Self.singleLetterUA.contains(uaLower)

            if uaIsSingle && !enIsSingle { return uaWord }
            if enIsSingle && !uaIsSingle { return enWord }
            // Both valid (e.g. "a"/"ф") or neither — use fallback
            return fallbackToLastLayout(enWord: enWord, uaWord: uaWord)
        }

        let enInDict = dictionary.isKnownEnglishWord(enLetters)
        let uaInDict = dictionary.isKnownUkrainianWord(uaLetters)

        DrukarLog.debug("eval: en='\(enWord)'(\(enInDict)) ua='\(uaWord)'(\(uaInDict))")

        if enInDict && uaInDict {
            if uaLetters.count > enLetters.count { return uaWord }
            if enLetters.count > uaLetters.count { return enWord }
            // Same length, both valid — prefer the "real" word over abbreviation/noise
            let uaHasCyrillic = uaLetters.contains { $0 >= "\u{0400}" && $0 <= "\u{04FF}" }
            let enHasLatin = enLetters.contains { ($0 >= "a" && $0 <= "z") || ($0 >= "A" && $0 <= "Z") }
            if uaHasCyrillic && enHasLatin {
                // Both are real scripts — prefer current language context
                return detectedLanguageIsUkrainian ? uaWord : enWord
            }
            return fallbackToLastLayout(enWord: enWord, uaWord: uaWord)
        }
        if enInDict { return enWord }
        if uaInDict { return uaWord }

        let enScore = detector.commonBigramScore(word: enWord, forUkrainian: false)
        let uaScore = detector.commonBigramScore(word: uaWord, forUkrainian: true)

        DrukarLog.debug("bigrams: en=\(String(format: "%.2f", enScore)) ua=\(String(format: "%.2f", uaScore))")

        let threshold = 0.30
        if enScore >= 0.3 && enScore > uaScore + threshold { return enWord }
        if uaScore >= 0.3 && uaScore > enScore + threshold { return uaWord }

        return fallbackToLastLayout(enWord: enWord, uaWord: uaWord)
    }

    private func fallbackToLastLayout(enWord: String, uaWord: String) -> String {
        return detectedLanguageIsUkrainian ? uaWord : enWord
    }

    // MARK: - Layout Resolution

    private func resolveLayouts() {
        for layoutID in LayoutResolver.availableLayoutIDs() {
            if LanguageDetector.isEnglishLayout(layoutID) && enLayoutID == nil {
                enLayoutID = layoutID
                if let source = LayoutResolver.sourceForID(layoutID) {
                    characterMapper.buildMap(for: source, sourceID: layoutID)
                }
            }
            if LanguageDetector.isUkrainianLayout(layoutID) && uaLayoutID == nil {
                uaLayoutID = layoutID
                if let source = LayoutResolver.sourceForID(layoutID) {
                    characterMapper.buildMap(for: source, sourceID: layoutID)
                }
            }
        }
        mapsReady = enLayoutID != nil && uaLayoutID != nil
        DrukarLog.info("Layouts resolved: en=\(enLayoutID ?? "nil") ua=\(uaLayoutID ?? "nil") ready=\(mapsReady)")
    }
}
