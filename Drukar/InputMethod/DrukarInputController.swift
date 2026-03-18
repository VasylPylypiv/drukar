import Cocoa
import InputMethodKit
import Carbon.HIToolbox
import NaturalLanguage

class DrukarInputController: IMKInputController {
    private let buffer = DualBuffer()
    private let detector = LanguageDetector()
    private let characterMapper = CharacterMapper()
    private let dictionary = WordDictionary.shared

    private var enLayoutID: String?
    private var uaLayoutID: String?
    private var mapsReady = false

    // MARK: - State Machine

    private enum State {
        case idle
        case composing
        case pending(PendingWord)
    }

    private struct PendingWord {
        let enWord: String
        let uaWord: String
        let displayText: String
        let keystrokes: [DualKeystroke]
    }

    private var state: State = .idle
    private var composingText = ""
    private var detectedLanguageIsUkrainian = true
    private var lastCommittedWord = ""

    // MARK: - Input Mode

    enum InputMode { case auto, english }

    private nonisolated(unsafe) static var forceEnglish = false

    private var mode: InputMode {
        if Self.forceEnglish { return .english }
        return NSEvent.modifierFlags.contains(.capsLock) ? .english : .auto
    }

    // MARK: - Lifecycle

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)
        resolveLayouts()
    }

    private static let excludedBundleIDs: Set<String> = [
        // Terminal emulators
        "com.apple.Terminal", "com.googlecode.iterm2", "net.kovidgoyal.kitty",
        "com.github.wez.wezterm", "co.zeit.hyper", "dev.warp.Warp-Stable",
        // Password managers
        "com.1password.1password", "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        // Launchers
        "com.runningwithcrayons.Alfred", "com.runningwithcrayons.Alfred-Preferences",
        "com.raycast.macos",
    ]

    private var isExcludedApp = false

    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        resetState()
        if !mapsReady { resolveLayouts() }

        if let client = sender as? IMKTextInput {
            let bundleID = client.bundleIdentifier() ?? ""
            isExcludedApp = Self.excludedBundleIDs.contains(bundleID)
                || DrukarSettings.shared.isExcludedApp(bundleID)
                || bundleID == DrukarApp.bundleIdentifier
            DrukarLog.info("activateServer: app=\(bundleID) excluded=\(isExcludedApp)")
        }
    }

    override func deactivateServer(_ sender: Any!) {
        commitAllPending(sender as? IMKTextInput)
        super.deactivateServer(sender)
    }

    override func commitComposition(_ sender: Any!) {
        commitAllPending(sender as? IMKTextInput)
    }

    private func resetState() {
        state = .idle
        composingText = ""
        buffer.clear()
    }

    private func commitAllPending(_ client: IMKTextInput?) {
        guard let client else { resetState(); return }
        switch state {
        case .pending(let pw):
            let word = detectedLanguageIsUkrainian ? pw.uaWord : pw.enWord
            client.insertText(word + " ", replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
            DrukarLog.debug("commitPending as-is: '\(word)'")
            state = .idle
            composingText = ""
            buffer.clear()
        case .composing:
            if !composingText.isEmpty {
                client.insertText(composingText, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
            }
            state = .idle
            composingText = ""
            buffer.clear()
        case .idle:
            break
        }
    }

    // MARK: - Menu

    override func menu() -> NSMenu! {
        let menu = NSMenu(title: "Drukar")

        let modeItem = NSMenuItem(title: mode == .auto ? "✓ Авто-визначення" : "  Авто-визначення",
                                  action: #selector(toggleAutoMode(_:)), keyEquivalent: "")
        modeItem.target = self
        menu.addItem(modeItem)

        let enItem = NSMenuItem(title: mode == .english ? "✓ Тільки English" : "  Тільки English",
                                action: #selector(toggleEnglishMode(_:)), keyEquivalent: "")
        enItem.target = self
        menu.addItem(enItem)

        menu.addItem(NSMenuItem.separator())

        let autocorrectItem = NSMenuItem(
            title: DrukarSettings.shared.autocorrectEnabled ? "✓ Автовиправлення" : "  Автовиправлення",
            action: #selector(toggleAutocorrect(_:)), keyEquivalent: "")
        autocorrectItem.target = self
        menu.addItem(autocorrectItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "Налаштування...", action: #selector(openSettings(_:)), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let aboutItem = NSMenuItem(title: "Про Друкар v0.7", action: #selector(showAbout(_:)), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        return menu
    }

    @objc private func toggleAutoMode(_ sender: Any?) { Self.forceEnglish = false }
    @objc private func toggleEnglishMode(_ sender: Any?) { Self.forceEnglish = !Self.forceEnglish }
    @objc private func toggleAutocorrect(_ sender: Any?) {
        DrukarSettings.shared.autocorrectEnabled = !DrukarSettings.shared.autocorrectEnabled
    }
    @objc private func openSettings(_ sender: Any?) { SettingsWindowController.shared.showSettings() }
    @objc private func showAbout(_ sender: Any?) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Друкар (Drukar) v0.7"
            alert.informativeText = "macOS Input Method для автоматичного визначення мови UA/EN.\n\nВЕСУМ 3.7M + Norvig autocorrect\nCaps Lock = English mode\n\ngithub.com/VasylPylypiv/drukar"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    // MARK: - Event Handling

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, event.type == .keyDown else { return false }
        guard let client = sender as? IMKTextInput else { return false }
        if isExcludedApp { return false }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let keyCode = event.keyCode

        if modifiers.contains(.command) || modifiers.contains(.control) {
            commitAllPending(client)
            return false
        }

        if keyCode == UInt16(kVK_Delete) || keyCode == UInt16(kVK_ForwardDelete) {
            return handleBackspace(client: client)
        }

        if keyCode == UInt16(kVK_Escape) {
            if case .idle = state { return false }
            cancelAll(client)
            return true
        }

        if isArrowOrNavigationKey(keyCode) || keyCode > 0x7E {
            commitAllPending(client)
            return false
        }

        // EN mode bypass
        if mode == .english {
            commitAllPending(client)
            return handleEnglishMode(event: event, keyCode: keyCode, client: client)
        }

        // Word boundaries: space, enter, tab
        if DualBuffer.wordBoundaryKeyCodes.contains(keyCode) {
            let isSpace = keyCode == 0x31
            handleWordBoundary(isSpace: isSpace, client: client)
            return isSpace
        }

        // Punctuation as word boundary
        if isPunctuation(event) {
            handlePunctuation(event: event, client: client)
            return true
        }

        return handleCharacterInput(event: event, keyCode: keyCode, client: client)
    }

    // MARK: - English Mode

    private func handleEnglishMode(event: NSEvent, keyCode: UInt16, client: IMKTextInput) -> Bool {
        if DualBuffer.wordBoundaryKeyCodes.contains(keyCode) {
            let isSpace = keyCode == 0x31
            if isSpace {
                client.insertText(" ", replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
                return true
            }
            return false
        }
        if mapsReady, let enID = enLayoutID,
           let enChar = characterMapper.characterForKeyCode(keyCode, shifted: event.modifierFlags.contains(.shift), sourceID: enID) {
            client.insertText(String(enChar), replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
            return true
        }
        if let chars = event.characters, !chars.isEmpty {
            client.insertText(chars, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
            return true
        }
        return false
    }

    // MARK: - Character Input

    private func handleCharacterInput(event: NSEvent, keyCode: UInt16, client: IMKTextInput) -> Bool {
        let isShifted = event.modifierFlags.contains(.shift)

        guard mapsReady, let enID = enLayoutID, let uaID = uaLayoutID else {
            if let chars = event.characters, !chars.isEmpty {
                commitAllPending(client)
                client.insertText(chars, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
                return true
            }
            return false
        }

        let enChar = characterMapper.characterForKeyCode(keyCode, shifted: isShifted, sourceID: enID)
        let uaChar = characterMapper.characterForKeyCode(keyCode, shifted: isShifted, sourceID: uaID)

        guard enChar != nil || uaChar != nil else {
            if let chars = event.characters, !chars.isEmpty {
                commitAllPending(client)
                client.insertText(chars, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
                return true
            }
            return false
        }

        buffer.append(DualKeystroke(keyCode: keyCode, enChar: enChar, uaChar: uaChar, isShifted: isShifted))

        let displayChar = detectedLanguageIsUkrainian ? (uaChar ?? enChar) : (enChar ?? uaChar)
        if let ch = displayChar {
            composingText.append(ch)
            updateMarkedText(client: client)
            if case .idle = state { state = .composing }
            return true
        }
        return false
    }

    // MARK: - Word Boundary (Space)

    private func handleWordBoundary(isSpace: Bool, client: IMKTextInput) {
        guard !buffer.isEmpty else {
            // Empty buffer — handle pending or insert space
            if case .pending(let pw) = state {
                let word = detectedLanguageIsUkrainian ? pw.uaWord : pw.enWord
                client.insertText(word + " ", replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
                state = .idle
                composingText = ""
            } else if isSpace {
                client.insertText(" ", replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
            }
            return
        }

        let enWord = buffer.enWord
        let uaWord = buffer.uaWord
        let enLetters = String(enWord.filter { $0.isLetter })
        let uaLetters = String(uaWord.filter { $0.isLetter })
        buffer.clear()
        composingText = ""

        let correctedWord = evaluateBestInterpretation(enWord: enWord, uaWord: uaWord)
        let currentIsEN = (correctedWord != uaWord) || (!detectedLanguageIsUkrainian && correctedWord == enWord)
        let enInDict = dictionary.isKnownEnglishWord(enLetters)
        let uaInDict = dictionary.isKnownUkrainianWord(uaLetters)
        // Not ambiguous if frequency clearly resolves it
        let enFreq = WordFrequency.score(of: enLetters, language: "en")
        let uaFreq = WordFrequency.score(of: uaLetters, language: "uk")
        let freqResolved = abs(enFreq - uaFreq) > 0.3
        let isAmbiguous = enInDict && uaInDict && enLetters.count == uaLetters.count && !freqResolved

        // Check if current word resolves a PENDING ambiguous word
        if case .pending(let pw) = state {
            let pwEnLetters = String(pw.enWord.filter { $0.isLetter })
            let pwUaLetters = String(pw.uaWord.filter { $0.isLetter })
            let pwEnInDict = dictionary.isKnownEnglishWord(pwEnLetters)
            let pwUaInDict = dictionary.isKnownUkrainianWord(pwUaLetters)
            let currentWordIsUnambiguousEN = enInDict && !uaInDict
            let currentWordIsUnambiguousUA = uaInDict && !enInDict

            if currentWordIsUnambiguousEN && pwEnInDict {
                // Current word is clearly EN → retrofix pending to EN
                let retroWord = pw.enWord
                DrukarLog.debug("retrofix: '\(pw.displayText)' → '\(retroWord)' (triggered by EN '\(correctedWord)')")
                client.insertText(retroWord + " " + correctedWord + (isSpace ? " " : ""),
                                  replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
                detectedLanguageIsUkrainian = false
                lastCommittedWord = correctedWord
                state = .idle
                return
            } else if currentWordIsUnambiguousUA && pwUaInDict {
                // Current word is clearly UA → retrofix pending to UA
                let retroWord = pw.uaWord
                DrukarLog.debug("retrofix: '\(pw.displayText)' → '\(retroWord)' (triggered by UA '\(correctedWord)')")
                client.insertText(retroWord + " " + correctedWord + (isSpace ? " " : ""),
                                  replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
                detectedLanguageIsUkrainian = true
                lastCommittedWord = correctedWord
                state = .idle
                return
            } else {
                // Can't resolve — commit pending as-is
                let pendingWord = detectedLanguageIsUkrainian ? pw.uaWord : pw.enWord
                client.insertText(pendingWord + " ", replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
                DrukarLog.debug("commitPending as-is: '\(pendingWord)'")
            }
        }

        // Current word: ambiguous → go PENDING, otherwise commit
        if isAmbiguous {
            let displayWord = detectedLanguageIsUkrainian ? uaWord : enWord
            let pending = PendingWord(enWord: enWord, uaWord: uaWord, displayText: displayWord,
                                      keystrokes: [])
            state = .pending(pending)
            composingText = displayWord + " "
            updateMarkedText(client: client)
            DrukarLog.debug("→ PENDING: '\(displayWord)' (en='\(enWord)' ua='\(uaWord)')")
        } else {
            let textToInsert = isSpace ? correctedWord + " " : correctedWord
            client.insertText(textToInsert, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
            detectedLanguageIsUkrainian = !currentIsEN
            lastCommittedWord = correctedWord
            state = .idle
            DrukarLog.debug("commit: '\(correctedWord)' (nextUA=\(detectedLanguageIsUkrainian))")
        }
    }

    // MARK: - Punctuation

    private static let punctuationChars: Set<Character> = [".", ",", "!", "?", ";", ":", "\"", "'", "(", ")", "-"]

    private func isPunctuation(_ event: NSEvent) -> Bool {
        guard let chars = event.characters, let ch = chars.first else { return false }
        guard Self.punctuationChars.contains(ch) else { return false }

        // Only treat as punctuation if NEITHER layout maps this key to a letter
        let keyCode = event.keyCode
        let isShifted = event.modifierFlags.contains(.shift)
        if mapsReady {
            if let enID = enLayoutID,
               let enChar = characterMapper.characterForKeyCode(keyCode, shifted: isShifted, sourceID: enID),
               enChar.isLetter { return false }
            if let uaID = uaLayoutID,
               let uaChar = characterMapper.characterForKeyCode(keyCode, shifted: isShifted, sourceID: uaID),
               uaChar.isLetter { return false }
        }
        return true
    }

    private func handlePunctuation(event: NSEvent, client: IMKTextInput) {
        let keyCode = event.keyCode
        let isShifted = event.modifierFlags.contains(.shift)

        // Get punctuation character from the correct layout
        var punct = event.characters ?? ""
        if mapsReady {
            let layoutID = detectedLanguageIsUkrainian ? uaLayoutID : enLayoutID
            if let id = layoutID, let ch = characterMapper.characterForKeyCode(keyCode, shifted: isShifted, sourceID: id) {
                punct = String(ch)
            }
        }

        // Commit pending as-is with punctuation
        if case .pending(let pw) = state {
            let word = detectedLanguageIsUkrainian ? pw.uaWord : pw.enWord
            if buffer.isEmpty {
                client.insertText(word + punct, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
            } else {
                let currentWord = evaluateBestInterpretation(enWord: buffer.enWord, uaWord: buffer.uaWord)
                client.insertText(word + " " + currentWord + punct,
                                  replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
                buffer.clear()
            }
            state = .idle
            composingText = ""
            return
        }

        // Commit current composing word with punctuation
        if !buffer.isEmpty {
            let enWord = buffer.enWord
            let uaWord = buffer.uaWord
            buffer.clear()
            composingText = ""

            let correctedWord = evaluateBestInterpretation(enWord: enWord, uaWord: uaWord)
            detectedLanguageIsUkrainian = (correctedWord == uaWord)
            lastCommittedWord = correctedWord
            client.insertText(correctedWord + punct, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
            state = .idle
        } else {
            client.insertText(punct, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
        }
    }

    // MARK: - Backspace

    private func handleBackspace(client: IMKTextInput) -> Bool {
        switch state {
        case .pending(let pw):
            if buffer.isEmpty {
                // Backspace on pending word space → go back to COMPOSING the pending word
                state = .composing
                // Rebuild buffer from pending word's keystrokes
                composingText = pw.displayText
                // We don't have original keystrokes stored fully, so just show the text
                updateMarkedText(client: client)
                DrukarLog.debug("backspace: PENDING → COMPOSING '\(composingText)'")
                return true
            } else {
                // Backspace on new word being typed after pending
                composingText.removeLast()
                buffer.removeLast()
                updateMarkedText(client: client)
                return true
            }

        case .composing:
            if composingText.isEmpty { return false }
            composingText.removeLast()
            buffer.removeLast()
            if composingText.isEmpty && buffer.isEmpty {
                cancelAll(client)
            } else {
                updateMarkedText(client: client)
            }
            return true

        case .idle:
            return false
        }
    }

    private func cancelAll(_ client: IMKTextInput) {
        state = .idle
        composingText = ""
        buffer.clear()
        client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
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

    // MARK: - Marked Text

    private func updateMarkedText(client: IMKTextInput) {
        // Underline word part, not trailing space
        let text = composingText
        let wordPart = text.hasSuffix(" ") ? String(text.dropLast()) : text
        let spacePart = text.hasSuffix(" ") ? " " : ""

        let attributed = NSMutableAttributedString()
        if !wordPart.isEmpty {
            attributed.append(NSAttributedString(string: wordPart, attributes: [
                .underlineStyle: NSUnderlineStyle.single.rawValue,
            ]))
        }
        if !spacePart.isEmpty {
            attributed.append(NSAttributedString(string: spacePart))
        }

        client.setMarkedText(attributed, selectionRange: NSRange(location: text.count, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
    }

    // MARK: - Detection Logic

    private static let singleLetterUA: Set<String> = ["і", "я", "в", "з", "у", "о", "а", "й", "ж", "є"]
    private static let singleLetterEN: Set<String> = ["i", "a"]

    private func evaluateBestInterpretation(enWord: String, uaWord: String) -> String {
        // Bypass: code tokens (ALL_CAPS, camelCase, digits, URLs, etc.) → pass as EN
        if BypassFilter.shouldBypass(enWord: enWord, uaWord: uaWord) {
            DrukarLog.debug("bypass: '\(enWord)' (code/IT token)")
            return enWord
        }

        let enLetters = String(enWord.filter { $0.isLetter })
        let uaLetters = String(uaWord.filter { $0.isLetter })

        if enLetters.count <= 1 && uaLetters.count <= 1 {
            let enIsSingle = Self.singleLetterEN.contains(enLetters.lowercased())
            let uaIsSingle = Self.singleLetterUA.contains(uaLetters.lowercased())
            if uaIsSingle && !enIsSingle { return uaWord }
            if enIsSingle && !uaIsSingle { return enWord }
            return detectedLanguageIsUkrainian ? uaWord : enWord
        }

        if enWord.count == uaWord.count && uaLetters.count != enLetters.count {
            let moreLettersIsUA = uaLetters.count > enLetters.count
            let moreLettersWord = moreLettersIsUA ? uaWord : enWord
            let moreLettersStr = moreLettersIsUA ? uaLetters : enLetters
            let lang = moreLettersIsUA ? "uk" : "en"
            if dictionary.isKnownWord(moreLettersStr, language: lang) {
                return moreLettersWord
            }
        }

        let enInDict = dictionary.isKnownEnglishWord(enLetters)
        let uaInDict = dictionary.isKnownUkrainianWord(uaLetters)
        let enInFreq = WordFrequency.isKnown(enLetters, language: "en")
        let uaInFreq = WordFrequency.isKnown(uaLetters, language: "uk")

        DrukarLog.debug("eval: en='\(enWord)'(\(enInDict)) ua='\(uaWord)'(\(uaInDict))")

        // IT dictionary and custom dictionary — highest priority (user-defined words)
        let enIsIT = ITDictionary.isKnownITWord(enLetters, language: "en")
        let uaIsIT = ITDictionary.isKnownITWord(uaLetters, language: "uk")
        let enIsCustom = DrukarSettings.shared.isCustomWord(enLetters, language: "en")
        let uaIsCustom = DrukarSettings.shared.isCustomWord(uaLetters, language: "uk")

        if (enIsIT || enIsCustom) && !(uaIsIT || uaIsCustom) { return enWord }
        if (uaIsIT || uaIsCustom) && !(enIsIT || enIsCustom) { return uaWord }

        if enInDict && uaInDict {
            // If only one side is in our own frequency dictionary, trust it over NSSpellChecker
            if uaInFreq && !enInFreq { return uaWord }
            if enInFreq && !uaInFreq { return enWord }

            // Neither in freq dict — check high-confidence (our own VESUM/SCOWL dictionaries)
            if !uaInFreq && !enInFreq {
                let uaHighConf = dictionary.isHighConfidence(uaLetters, language: "uk")
                let enHighConf = dictionary.isHighConfidence(enLetters, language: "en")
                if uaHighConf && !enHighConf { return uaWord }
                if enHighConf && !uaHighConf { return enWord }
                // Both only known via NSSpellChecker — use NLLanguageRecognizer to break the tie
                if !uaHighConf && !enHighConf {
                    if let nlWinner = detectLanguageNL(uaWord: uaWord, enWord: enWord) {
                        DrukarLog.debug("NL early tiebreak: '\(nlWinner)' (both NSSpellChecker-only)")
                        return nlWinner
                    }
                }
            }

            if uaLetters.count > enLetters.count { return uaWord }
            if enLetters.count > uaLetters.count { return enWord }
            // Both valid, same length — compare word frequencies
            let enFreq = WordFrequency.score(of: enLetters, language: "en")
            let uaFreq = WordFrequency.score(of: uaLetters, language: "uk")
            if enFreq > 0 || uaFreq > 0 {
                if enFreq > uaFreq + 0.3 {
                    DrukarLog.debug("freq: '\(enWord)' wins (en=\(String(format: "%.2f", enFreq)) ua=\(String(format: "%.2f", uaFreq)))")
                    return enWord
                }
                if uaFreq > enFreq + 0.3 {
                    DrukarLog.debug("freq: '\(uaWord)' wins (ua=\(String(format: "%.2f", uaFreq)) en=\(String(format: "%.2f", enFreq)))")
                    return uaWord
                }
            }
            return detectedLanguageIsUkrainian ? uaWord : enWord
        }
        if enInDict { return enWord }
        if uaInDict { return uaWord }

        if DrukarSettings.shared.autocorrectEnabled {
            let probableLang = detectedLanguageIsUkrainian ? "uk" : "en"
            let primaryWord = detectedLanguageIsUkrainian ? uaLetters : enLetters
            if let fixed = safeCorrection(for: primaryWord, language: probableLang) {
                DrukarLog.debug("autocorrect: '\(primaryWord)' → '\(fixed)' (\(probableLang))")
                return fixed
            }
            let secondaryLang = detectedLanguageIsUkrainian ? "en" : "uk"
            let secondaryWord = detectedLanguageIsUkrainian ? enLetters : uaLetters
            if let fixed = safeCorrection(for: secondaryWord, language: secondaryLang) {
                DrukarLog.debug("autocorrect fallback: '\(secondaryWord)' → '\(fixed)' (\(secondaryLang))")
                return fixed
            }
        }

        let nlWinner = detectLanguageNL(uaWord: uaWord, enWord: enWord)
        if let winner = nlWinner { return winner }

        return detectedLanguageIsUkrainian ? uaWord : enWord
    }

    private let languageRecognizer = NLLanguageRecognizer()

    private func detectLanguageNL(uaWord: String, enWord: String) -> String? {
        languageRecognizer.reset()
        languageRecognizer.languageConstraints = [.ukrainian, .english]

        let uaPhrase = lastCommittedWord.isEmpty ? uaWord : lastCommittedWord + " " + uaWord
        let enPhrase = lastCommittedWord.isEmpty ? enWord : lastCommittedWord + " " + enWord

        languageRecognizer.processString(uaPhrase)
        let uaConf = languageRecognizer.languageHypotheses(withMaximum: 2)[.ukrainian] ?? 0
        languageRecognizer.reset()

        languageRecognizer.processString(enPhrase)
        let enConf = languageRecognizer.languageHypotheses(withMaximum: 2)[.english] ?? 0
        languageRecognizer.reset()

        if uaConf > enConf + 0.1 && uaConf >= 0.3 { return uaWord }
        if enConf > uaConf + 0.1 && enConf >= 0.3 { return enWord }
        return nil
    }

    private func safeCorrection(for word: String, language: String) -> String? {
        guard word.count >= 4 else { return nil }
        guard let corrected = dictionary.correction(for: word, language: language) else { return nil }
        let wLower = word.lowercased(), cLower = corrected.lowercased()
        let sameFirst = cLower.first == wLower.first
        let wArr = Array(wLower), cArr = Array(cLower)
        let transposedFirst = wArr.count >= 2 && cArr.count >= 2
            && cArr[0] == wArr[1] && cArr[1] == wArr[0]
        // For longer words (7+), allow any first letter if total edit distance is acceptable
        let relaxedForLong = word.count >= 7
        guard sameFirst || transposedFirst || relaxedForLong else { return nil }
        return corrected
    }

    // MARK: - Layout Resolution

    private func resolveLayouts() {
        for layoutID in LayoutResolver.availableLayoutIDs() {
            if LanguageDetector.isEnglishLayout(layoutID) && enLayoutID == nil {
                enLayoutID = layoutID
                if let source = LayoutResolver.sourceForID(layoutID) { characterMapper.buildMap(for: source, sourceID: layoutID) }
            }
            if LanguageDetector.isUkrainianLayout(layoutID) && uaLayoutID == nil {
                uaLayoutID = layoutID
                if let source = LayoutResolver.sourceForID(layoutID) { characterMapper.buildMap(for: source, sourceID: layoutID) }
            }
        }
        mapsReady = enLayoutID != nil && uaLayoutID != nil
        DrukarLog.info("Layouts: en=\(enLayoutID ?? "nil") ua=\(uaLayoutID ?? "nil") ready=\(mapsReady)")
    }
}
