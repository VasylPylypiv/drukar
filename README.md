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
- **3.7M Ukrainian word forms** — [VESUM](https://github.com/brown-uk/dict_uk) morphological dictionary via memory-mapped binary search (all declensions, conjugations, cases)
- **134K English words** — [SCOWL](http://wordlist.aspell.net/) word list, also memory-mapped
- **Norvig autocorrect** — generates ~700 candidate mutations per typo, validates against full dictionary via mmap. Fixes "перезавнтажив" → "Перезавантажив", "настикаю" → "натискаю"
- **Case preservation** — autocorrect keeps original capitalization (Слово → Слово, СЛОВО → СЛОВО)
- **IT dictionary** — 230+ built-in Ukrainian IT terms (верифікація, деплой, кеш, юзер, імплементація...)
- **Custom dictionary** — add your own words via Settings (highest priority in detection)
- **Frequency scoring** — 50K words per language from Leipzig Corpus for tie-breaking
- **Caps Lock = English mode** — LED on = forced English, LED off = auto-detect
- **Settings UI** — configure autocorrect, word length, custom dictionary, app exclusions
- **Menu bar menu** — click "Д" icon to toggle modes, open settings
- **Per-app exclusion** — auto-disabled in Terminal, iTerm2, Kitty, Warp, 1Password, Bitwarden, Alfred, Raycast
- **Lightweight** — 0.02% CPU, **8 MB memory** (3.7M dictionary with zero RAM via mmap)

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
   - **IT slang + Custom dictionary** (highest priority — user-defined words always win)
   - **Dictionary lookup** — mmap binary search in VESUM 3.7M / SCOWL 134K
   - **Word frequency comparison** — 50K words per language, logarithmic scoring
   - **Autocorrect** — Norvig ED=1 (~700 mutations × mmap lookup), double transposition fallback
   - **NLLanguageRecognizer** — Apple ML model as final tiebreaker
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
./scripts/decompress_wordlists.sh   # decompress VESUM/SCOWL word lists
xcodegen generate
open Drukar.xcodeproj
```

In Xcode: set Team in Signing & Capabilities, then Cmd+R to build.

To install after building:

```bash
kill -9 $(pgrep -x Drukar)
cp -R "$HOME/Library/Developer/Xcode/DerivedData/Drukar-*/Build/Products/Debug/Drukar.app" "$HOME/Library/Input Methods/"
```

### Regenerating Dictionaries

Frequency dictionaries (Leipzig Corpus):

```bash
python3 scripts/generate_freq.py
```

Word lists (VESUM + SCOWL):

```bash
python3 scripts/generate_wordlists.py
./scripts/decompress_wordlists.sh
```

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
│   ├── LanguageDetector.swift   # Layout identification + bigram tables
│   ├── WordDictionary.swift     # Norvig autocorrect + mmap isKnown
│   ├── WordFrequency.swift      # JSON-loaded frequency scores (50K/lang)
│   ├── MappedDictionary.swift   # Memory-mapped binary search (zero RAM)
│   ├── CharacterMapper.swift    # UCKeyTranslate keycode↔character mapping
│   └── ITDictionary.swift       # Built-in IT slang (230+ words)
├── Settings/
│   ├── DrukarSettings.swift     # UserDefaults persistence
│   ├── SettingsView.swift       # SwiftUI settings window
│   └── SettingsWindowController.swift
├── Resources/
│   ├── Info.plist               # IMK configuration
│   ├── words_uk.txt.gz          # VESUM Ukrainian word forms (3.7M, compressed)
│   ├── words_en.txt.gz          # SCOWL English words (134K, compressed)
│   ├── ua_freq.json             # Ukrainian frequency scores (50K, Leipzig)
│   ├── en_freq.json             # English frequency scores (50K, Leipzig)
│   └── Assets.xcassets/
└── scripts/
    ├── generate_freq.py         # Regenerate frequency JSONs from Leipzig data
    ├── generate_wordlists.py    # Generate sorted word lists from VESUM/SCOWL
    └── decompress_wordlists.sh  # Decompress .gz for Xcode build
```

## Performance

- **CPU**: 0.02% idle, <1% during typing
- **Memory**: 8 MB (3.7M dictionary via mmap — zero RAM overhead)
- **Threads**: 3
- **Hangs**: 0
- **Universal binary**: arm64 (Apple Silicon) + x86_64 (Intel)

## Changelog

### v0.7

- **VESUM dictionary**: 3,679,690 Ukrainian word forms via memory-mapped binary search — all declensions, conjugations, cases. "верифікації", "натискаю", "конфігурацією" — all recognized
- **SCOWL dictionary**: 133,746 English words replacing NSSpellChecker — no more false positives on gibberish
- **Norvig autocorrect**: generates ~700 candidate mutations per typo (inserts, deletes, replaces, transposes), validates each via mmap binary search against full dictionary. Zero additional RAM
- **NSSpellChecker fully removed**: replaced by own dictionaries for deterministic, predictable behavior
- **SymSpell removed**: Norvig + mmap provides same correction quality with zero RAM overhead (8 MB total vs 193 MB with SymSpell)
- **Case preservation**: autocorrect maintains original capitalization
- **IT dictionary expanded**: 230+ terms including верифікація, валідація, імплементація, оптимізація, конфігурація
- **Custom dictionary priority**: user-defined words now checked before general dictionary — always win

### v0.5

- **SymSpell autocorrect** (later replaced by Norvig in v0.7)
- **NSSpellChecker false positive protection**

### v0.4

- **Expanded frequency dictionaries**: 500 → 50,000 word forms per language (Leipzig Corpus)
- **Logarithmic scoring**: `log10(totalWords / rank)` for better frequency discrimination
- **Double transposition autocorrect**: fixes "настикаю" → "натискаю"
- **Expanded app blacklist**: 1Password, Bitwarden, Alfred, Raycast

### v0.3

- Initial public release with NSSpellChecker detection, IT dictionary, autocorrect, NLLanguageRecognizer fallback

## Known Limitations

- **Terminal apps** — Terminal.app, iTerm2 etc. are auto-excluded (don't support IMK marked text)
- **Some web input fields** — certain custom text fields (React/Angular ContentEditable) may not support IMK marked text protocol
- **Ambiguous short words** (e.g., "це"/"wt" — both valid in dictionaries) — resolved by language context from previous word

## Background

This project started as a fork of [rmarinsky/papuga](https://github.com/rmarinsky/papuga) — a macOS menu bar utility for manual UA/EN layout switching. I added automatic wrong-layout detection using CGEvent tap, but hit fundamental limitations: visible text flicker during correction, race conditions with fast typing, unreliable layout switching in Electron apps.

Drukar is a clean-room rewrite using InputMethodKit — the proper macOS API for input methods. The detection algorithms (dual buffer, frequency analysis, autocorrect) are preserved; the replacement mechanism is entirely new.

## Dictionary Credits

- **VESUM** (Великий електронний словник української мови) by Andriy Rysin, Vasyl Starko & BrUK team — [brown-uk/dict_uk](https://github.com/brown-uk/dict_uk) (CC BY-NC-SA 4.0)
- **SCOWL** (Spell Checker Oriented Word Lists) by Kevin Atkinson — [wordlist.aspell.net](http://wordlist.aspell.net/)
- **Leipzig Corpora Collection** — [wortschatz.uni-leipzig.de](https://wortschatz.uni-leipzig.de/)

## Contributing

Issues and PRs are welcome. The main areas that need improvement:

- [ ] Undo correction (backspace after space reverts to original)
- [ ] Prefix matching (early language detection during typing via mmap lower_bound)
- [ ] Support for more language pairs (RU/EN, PL/EN, etc.)
- [ ] Apple Developer ID signing (eliminate "unidentified developer" warning)
- [ ] Homebrew Cask distribution

## License

MIT — see [LICENSE](LICENSE).

Dictionary data (VESUM) is licensed under CC BY-NC-SA 4.0.
