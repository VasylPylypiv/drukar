# Drukar (Друкар)

**macOS Input Method that automatically detects whether you're typing Ukrainian or English — and corrects the output in real time.**

No more `Ghbdsn` instead of `Привіт`. No more `ру|щ` instead of `hello`.

<p align="center">
  <video src="[Demo.mp4](https://github.com/user-attachments/assets/cd4dd326-1e88-4e6d-8a79-5eb6a1183db9)" width="600" autoplay loop muted>
  </video>
</p>

> **Note:** The video above will render after publishing to GitHub. To preview locally, open `assets/demo.mp4`.

Drukar intercepts keystrokes *before* they reach your app, analyzes both possible interpretations (UA and EN), and commits the correct one — all in under a millisecond.

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
   - **Bigram frequency analysis** as fallback
   - **Single-letter word whitelist** (і, я, в, a, I)
5. The correct interpretation is committed atomically
6. Language context carries over: after a Ukrainian word, the next word displays in Cyrillic; after English — in Latin

## Installation

### Quick Install (no Xcode needed)

1. Download `Drukar.app.zip` from [Releases](../../releases)
2. Unzip and run the installer:

```bash
unzip Drukar.app.zip
./install.sh
```

Or install manually:

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
│   ├── WordDictionary.swift     # NSSpellChecker wrapper
│   └── CharacterMapper.swift    # UCKeyTranslate keycode↔character mapping
└── Resources/
    ├── Info.plist               # IMK configuration
    └── Assets.xcassets/
```

## Test Results

All 9 test chapters passed:

| Chapter | Status |
|---|---|
| Basic detection (UA/EN words) | Passed |
| Mid-text language switching | Passed |
| Problematic words (short, IT terms) | Passed* |
| Special characters & punctuation | Passed |
| Backspace & editing | Passed |
| Modifier keys (Cmd, Ctrl, arrows) | Passed |
| App compatibility (TextEdit, Safari, VS Code, Sublime, Finder, Spotlight) | Passed |
| Stability & performance (CPU 0.02%, Memory 6.1 MB) | Passed |
| Punctuation as word boundary | Passed |

*Known limitations: Terminal.app doesn't fully support IMK marked text; IT jargon not in NSSpellChecker relies on bigram context.

## Performance

- **CPU**: 0.02% idle, <5% during typing
- **Private Memory**: 6.1 MB
- **Threads**: 4
- **Hangs**: 0

## Known Limitations

- **Terminal.app** — doesn't support IMK `setMarkedText` properly
- **IT jargon** (e.g., "кешування") — not in NSSpellChecker dictionary, detected via bigrams + language context
- **Ambiguous short words** (e.g., "це"/"wt" — both valid in their dictionaries) — resolved by language context from previous word

## Background

This project started as a fork of [rmarinsky/papuga](https://github.com/rmarinsky/papuga) — a macOS menu bar utility for manual UA/EN layout switching. I added automatic wrong-layout detection using CGEvent tap, but hit fundamental limitations: visible text flicker during correction, race conditions with fast typing, unreliable layout switching in Electron apps.

Drukar is a clean-room rewrite using InputMethodKit — the proper macOS API for input methods. The detection algorithms (dual buffer, NSSpellChecker, bigram analysis) are preserved; the replacement mechanism is entirely new.

## Contributing

Issues and PRs are welcome. The main areas that need improvement:

- [ ] Better heuristics for ambiguous words (both valid in EN and UA dictionaries)
- [ ] Custom user dictionary for IT/domain-specific terms
- [ ] Settings UI (enable/disable, minimum word length, exclusion list)
- [ ] Menu bar status indicator
- [ ] Per-app exclusion list (e.g., disable in Terminal)

## License

MIT — see [LICENSE](LICENSE).
