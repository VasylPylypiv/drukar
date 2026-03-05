# Drukar (Друкар)

**macOS Input Method that automatically detects whether you're typing Ukrainian or English — and corrects the output in real time.**

No more `Ghbdsn` instead of `Привіт`. No more `ру|щ` instead of `hello`.

<p align="center">

https://github.com/user-attachments/assets/f8591be9-aae8-448d-80f4-96012dcf1a1e

</p>

Drukar intercepts keystrokes *before* they reach your app, analyzes both possible interpretations (UA and EN), and commits the correct one — all in under a millisecond.

## Features

- **Auto-detection** — type in any layout, Drukar figures out the language
- **Atomic replacement** — no backspace flicker, text appears correct from the start
- **5,000-word frequency dictionaries** — logarithmic scoring from Leipzig Corpus (News 2024, 1M sentences)
- **Autocorrect** — fixes typos like "привт" → "привіт", "tset" → "test" (Damerau-Levenshtein, sliding window tolerance: distance 1 for 4–6 chars, distance 2 for 7+)
- **IT dictionary** — 150+ built-in Ukrainian IT terms (логи, деплой, кеш, юзер, фіча...)
- **Custom dictionary** — add your own words via Settings
- **Caps Lock = English mode** — LED on = forced English, LED off = auto-detect
- **Settings UI** — configure autocorrect, word length, custom dictionary, app exclusions
- **Menu bar menu** — click "Д" icon to toggle modes, open settings
- **Per-app exclusion** — auto-disabled in Terminal, iTerm2, Kitty, Warp, 1Password, Bitwarden, Alfred, Raycast; add your own
- **Lightweight** — 0.02% CPU, 6 MB memory, ~350 KB download

## Why?

Every Ukrainian developer knows the pain: you start typing a Slack message and realize three words in that your keyboard layout was wrong. You delete everything, switch layout, retype. Multiple times a day. Every day.

Existing solutions (Caramba Switcher, Punto Switcher) only support Russian/English, use the old CGEvent tap approach (backspace + retype = visible flicker), and are closed-source.

Drukar is different:

| | CGEvent tap (others) | InputMethodKit (Drukar) |
|---|---|---|
| What you see | Wrong text, then corrected | Correct text from the start |
| Replacement | Backspace + retype (~200ms flicker) | Atomic `insertText` (instant) |
| Race conditions | Yes (fast typing loses chars) | None |
| Ukrainian support | No (RU/EN only) | Yes (UA/EN) |
| Open source | No | Yes (MIT) |

## How It Works

1. You type on your physical keyboard — Drukar intercepts each keystroke via `IMKInputController`
2. Each key is mapped to **both** UA and EN characters simultaneously using `UCKeyTranslate`
3. Text appears as **underlined composing text** (like CJK input methods) while you type
4. On word boundary (space, enter), Drukar evaluates both interpretations:
   - **Dictionary lookup** via `NSSpellChecker` (100K+ words per language)
   - **Word frequency comparison** — 5,000 words per language, logarithmic scoring from Leipzig Corpus
   - **IT slang dictionary** (150+ Ukrainian tech terms)
   - **Custom user dictionary** (added via Settings)
   - **Autocorrect** (Damerau-Levenshtein, sliding window: distance 1 for short words, distance 2 for 7+ chars)
   - **NLLanguageRecognizer** (Apple ML model, replaces manual bigram tables)
   - **Single-letter word whitelist** (і, я, в, a, I)
5. The correct interpretation is committed atomically
6. Language context carries over: after a Ukrainian word, the next word displays in Cyrillic; after English — in Latin

## Installation

### Quick Install (no Xcode needed)

1. Download `Drukar.app.zip` from [Releases](../../releases)
2. Unzip and copy to Input Methods:

```bash
unzip Drukar.app.zip
cp -R Drukar.app ~/Library/Input\ Methods/
```

3. Open **System Settings → Keyboard → Input Sources → Edit**
4. Click **"+"** → find **Drukar** → Add
5. Select Drukar as your active input source

> First time: you may need to **log out and back in** for macOS to recognize the new input method.
>
> macOS may warn about "unidentified developer". Go to **System Settings → Privacy & Security** and click "Open Anyway".

### Build from Source

Requires macOS 14.0+, Xcode 16.0+, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
git clone https://github.com/VasylPylypiv/drukar.git
cd drukar
xcodegen generate
open Drukar.xcodeproj
```

In Xcode: set Team in Signing & Capabilities, then Cmd+R to build.

To install after building:

```bash
kill -9 $(pgrep -x Drukar)
cp -R "$HOME/Library/Developer/Xcode/DerivedData/Drukar-*/Build/Products/Debug/Drukar.app" "$HOME/Library/Input Methods/"
```

### Regenerating Frequency Dictionaries

The frequency JSON files are included in the repo. To regenerate from fresh Leipzig Corpus data:

```bash
python3 scripts/generate_freq.py
```

This downloads the latest Ukrainian and English news corpora (1M sentences each) and produces `Drukar/Resources/ua_freq.json` and `Drukar/Resources/en_freq.json` with 5,000 words per language.

## Project Structure

```
Drukar/
├── App/
│   ├── main.swift              # Entry point, IMKServer setup
│   ├── AppDelegate.swift       # NSApplicationDelegate
│   └── DrukarLog.swift         # OSLog wrapper
├── InputMethod/
│   ├── DrukarInputController.swift  # IMKInputController — core logic
│   └── LayoutResolver.swift         # TIS layout queries & switching
├── Detection/
│   ├── DualBuffer.swift         # Dual EN/UA keystroke buffer
│   ├── LanguageDetector.swift   # Bigram tables and scoring
│   ├── WordDictionary.swift     # NSSpellChecker + autocorrect
│   ├── WordFrequency.swift      # JSON-loaded word frequency scores (5K words/lang)
│   ├── CharacterMapper.swift    # UCKeyTranslate keycode↔character mapping
│   └── ITDictionary.swift       # Built-in IT slang (150+ words)
├── Settings/
│   ├── DrukarSettings.swift     # UserDefaults persistence
│   ├── SettingsView.swift       # SwiftUI settings window
│   └── SettingsWindowController.swift
├── Resources/
│   ├── Info.plist               # IMK configuration
│   ├── ua_freq.json             # Ukrainian word frequencies (5K, Leipzig Corpus)
│   ├── en_freq.json             # English word frequencies (5K, Leipzig Corpus)
│   └── Assets.xcassets/
└── scripts/
    └── generate_freq.py         # Regenerate frequency JSONs from Leipzig data
```

## Performance

- **CPU**: 0.02% idle, <5% during typing
- **Private Memory**: 6 MB
- **Threads**: 4
- **Hangs**: 0
- **Download**: ~350 KB

## Changelog

### v0.4

- **Expanded frequency dictionaries**: 500 → 5,000 words per language, sourced from Leipzig Corpus (News 2024, 1M sentences)
- **Logarithmic scoring**: `log10(totalWords / rank)` replaces linear `1 - rank/501` for better discrimination across frequency ranks
- **JSON-loaded dictionaries**: frequency data loaded from bundled JSON files instead of hardcoded Swift arrays
- **Expanded app blacklist**: added 1Password, Bitwarden, Alfred, Raycast to auto-excluded apps
- **Sliding window autocorrect**: distance 1 for 4–6 character words, distance 2 for 7+ characters; relaxed first-letter rule for longer words
- **Regeneration script**: `scripts/generate_freq.py` downloads and processes Leipzig corpus data

### v0.3

- Initial public release with NSSpellChecker detection, IT dictionary, autocorrect, NLLanguageRecognizer fallback

## Known Limitations

- **Terminal apps** — Terminal.app, iTerm2 etc. are auto-excluded (don't support IMK marked text)
- **Ambiguous short words** (e.g., "це"/"wt" — both valid in dictionaries) — resolved by language context from previous word
- **Intermittent state issues** in Telegram/Slack after rapid window switching

## Background

This project started as a fork of [rmarinsky/papuga](https://github.com/rmarinsky/papuga) — a macOS menu bar utility for manual UA/EN layout switching. I added automatic wrong-layout detection using CGEvent tap, but hit fundamental limitations: visible text flicker during correction, race conditions with fast typing, unreliable layout switching in Electron apps.

Drukar is a clean-room rewrite using InputMethodKit — the proper macOS API for input methods. The detection algorithms (dual buffer, NSSpellChecker, bigram analysis) are preserved; the replacement mechanism is entirely new.

## Contributing

Issues and PRs are welcome. The main areas that need improvement:

- [ ] Undo correction (backspace after space reverts to original)
- [ ] Retrospective correction (re-evaluate previous 2-3 words together)
- [ ] Support for more language pairs (RU/EN, PL/EN, etc.)
- [ ] Apple Developer ID signing (eliminate "unidentified developer" warning)
- [ ] Homebrew Cask distribution

## License

MIT — see [LICENSE](LICENSE).
