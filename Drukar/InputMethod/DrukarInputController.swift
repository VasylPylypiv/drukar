import Cocoa
import InputMethodKit
import Carbon.HIToolbox

/// Main input controller — one instance per client (app window).
/// IMK calls `handle(_:client:)` for each key event BEFORE it reaches the app.
class DrukarInputController: IMKInputController {
    private let buffer = DualBuffer()
    private let detector = LanguageDetector()
    private let characterMapper = CharacterMapper()
    private let dictionary = WordDictionary()

    private var enLayoutID: String?
    private var uaLayoutID: String?
    private var mapsReady = false

    private var composingText = ""

    // MARK: - Lifecycle

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)
        resolveLayouts()
    }

    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        buffer.clear()
        composingText = ""
        if !mapsReady { resolveLayouts() }
    }

    override func deactivateServer(_ sender: Any!) {
        commitComposingText(sender as? IMKTextInput)
        buffer.clear()
        composingText = ""
        super.deactivateServer(sender)
    }

    // MARK: - Event Handling

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, event.type == .keyDown else { return false }
        guard let client = sender as? IMKTextInput else { return false }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if modifiers.contains(.command) {
            commitComposingText(client)
            return false
        }

        let keyCode = event.keyCode
        let isShifted = modifiers.contains(.shift) || modifiers.contains(.capsLock)

        if keyCode == kVK_Delete {
            return handleBackspace(client: client)
        }

        if keyCode == kVK_Escape {
            cancelComposingText(client)
            return true
        }

        if DualBuffer.wordBoundaryKeyCodes.contains(keyCode) {
            return handleWordBoundary(keyCode: keyCode, client: client)
        }

        guard mapsReady, let enID = enLayoutID, let uaID = uaLayoutID else {
            return false
        }

        let enChar = characterMapper.characterForKeyCode(keyCode, shifted: isShifted, sourceID: enID)
        let uaChar = characterMapper.characterForKeyCode(keyCode, shifted: isShifted, sourceID: uaID)

        guard enChar != nil || uaChar != nil else { return false }

        buffer.append(DualKeystroke(keyCode: keyCode, enChar: enChar, uaChar: uaChar, isShifted: isShifted))

        let currentLayout = LayoutResolver.currentLayoutID()
        let typedChar: Character?
        if LanguageDetector.isUkrainianLayout(currentLayout) {
            typedChar = uaChar ?? enChar
        } else {
            typedChar = enChar ?? uaChar
        }

        if let ch = typedChar {
            composingText.append(ch)
            updateMarkedText(composingText, client: client)
        }

        return true
    }

    // MARK: - Word Boundary

    private func handleWordBoundary(keyCode: UInt16, client: IMKTextInput) -> Bool {
        guard !buffer.isEmpty else { return false }

        let enWord = buffer.enWord
        let uaWord = buffer.uaWord
        buffer.clear()

        let correctedWord = evaluateBestInterpretation(enWord: enWord, uaWord: uaWord)

        let boundaryChar = wordBoundaryCharacter(for: keyCode)
        let textToInsert = correctedWord + boundaryChar

        client.insertText(textToInsert, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
        composingText = ""

        if let targetLayout = targetLayoutID(for: correctedWord, enWord: enWord, uaWord: uaWord) {
            LayoutResolver.switchTo(targetLayout)
        }

        return true
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
        guard !composingText.isEmpty else { return false }
        composingText.removeLast()
        buffer.removeLast()
        if composingText.isEmpty {
            cancelComposingText(client)
        } else {
            updateMarkedText(composingText, client: client)
        }
        return true
    }

    // MARK: - Marked Text (Composing Region)

    private func updateMarkedText(_ text: String, client: IMKTextInput) {
        let attrs: [NSAttributedString.Key: Any] = [
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .foregroundColor: NSColor.textColor,
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

    private func evaluateBestInterpretation(enWord: String, uaWord: String) -> String {
        let enLetters = String(enWord.filter { $0.isLetter })
        let uaLetters = String(uaWord.filter { $0.isLetter })

        guard enLetters.count >= 2 || uaLetters.count >= 2 else {
            return fallbackToCurrentLayout(enWord: enWord, uaWord: uaWord)
        }

        let enInDict = dictionary.isKnownEnglishWord(enLetters)
        let uaInDict = dictionary.isKnownUkrainianWord(uaLetters)

        DrukarLog.debug("eval: en='\(enWord)'(\(enInDict)) ua='\(uaWord)'(\(uaInDict))")

        if enInDict && uaInDict {
            if uaLetters.count > enLetters.count { return uaWord }
            if enLetters.count > uaLetters.count { return enWord }
            return fallbackToCurrentLayout(enWord: enWord, uaWord: uaWord)
        }
        if enInDict { return enWord }
        if uaInDict { return uaWord }

        let enScore = detector.commonBigramScore(word: enWord, forUkrainian: false)
        let uaScore = detector.commonBigramScore(word: uaWord, forUkrainian: true)

        DrukarLog.debug("bigrams: en=\(String(format: "%.2f", enScore)) ua=\(String(format: "%.2f", uaScore))")

        let threshold = 0.30
        if enScore >= 0.3 && enScore > uaScore + threshold { return enWord }
        if uaScore >= 0.3 && uaScore > enScore + threshold { return uaWord }

        return fallbackToCurrentLayout(enWord: enWord, uaWord: uaWord)
    }

    private func fallbackToCurrentLayout(enWord: String, uaWord: String) -> String {
        let current = LayoutResolver.currentLayoutID()
        return LanguageDetector.isUkrainianLayout(current) ? uaWord : enWord
    }

    private func targetLayoutID(for correctedWord: String, enWord: String, uaWord: String) -> String? {
        if correctedWord == enWord, let id = enLayoutID { return id }
        if correctedWord == uaWord, let id = uaLayoutID { return id }
        return nil
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
        DrukarLog.info("Layouts resolved: en=\(enLayoutID ?? "nil") ua=\(uaLayoutID ?? "nil")")
    }
}
