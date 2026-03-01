# Drukar (Друкар)

macOS Input Method for automatic keyboard layout detection and correction (UA/EN).

Built with **InputMethodKit** — receives keystrokes *before* they reach the foreground app, enabling atomic text replacement with zero race conditions.

## Architecture

Unlike CGEvent tap approaches (backspace+retype), Drukar is a proper Input Method:

- Intercepts keystrokes via `IMKInputController.handle(_:client:)` before they reach the app
- Shows composing text as **marked (underlined) text** while analyzing
- Replaces atomically via `insertText(_:replacementRange:)` — no backspace flicker
- Works in ALL apps (native, Electron, web)

### Detection (reused from papuga auto-detection)

- **Keycode-based dual interpretation**: each keystroke is mapped to both EN and UA characters via `UCKeyTranslate`
- **NSSpellChecker**: macOS built-in dictionary (100K+ words per language)
- **Bigram frequency analysis**: fallback for words not in spell checker

### Key Files

```
Drukar/
├── App/
│   ├── main.swift              # Entry point, IMKServer setup
│   ├── AppDelegate.swift       # NSApplicationDelegate
│   └── DrukarLog.swift         # OSLog wrapper
├── InputMethod/
│   ├── DrukarInputController.swift  # IMKInputController — main logic
│   └── LayoutResolver.swift         # TIS layout queries & switching
├── Detection/
│   ├── DualBuffer.swift         # Dual EN/UA keystroke buffer
│   ├── LanguageDetector.swift   # Bigram tables and scoring
│   ├── WordDictionary.swift     # NSSpellChecker wrapper
│   └── CharacterMapper.swift    # UCKeyTranslate keycode↔character
└── Resources/
    ├── Info.plist               # IMK configuration
    ├── Drukar.entitlements
    └── Assets.xcassets/
```

## Build

### Prerequisites

- Xcode 16.3+, macOS 14.0+ (Sonoma)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (optional, for regenerating project)

### Build & Run

```bash
cd /Users/vasyl.pylypiv/repos/drukar

# Regenerate Xcode project (if project.yml changed)
xcodegen generate

# Open in Xcode
open Drukar.xcodeproj
```

In Xcode:
1. Set **Team** to Personal Team in Signing & Capabilities
2. **Cmd+R** to build and run

### Install as Input Method

After building, copy the `.app` to Input Methods:

```bash
cp -R ~/Library/Developer/Xcode/DerivedData/Drukar-*/Build/Products/Debug/Drukar.app ~/Library/Input\ Methods/
```

Then:
1. Open **System Settings → Keyboard → Input Sources**
2. Click **+** → find **Drukar**
3. Add it as an input source

## How It Works

1. User types with any keyboard layout active
2. Drukar intercepts each keystroke, maps it to both EN and UA characters
3. Text appears as **underlined composing text** (like CJK input methods)
4. On word boundary (space/enter), Drukar evaluates both interpretations:
   - Dictionary lookup (strongest signal)
   - Bigram frequency analysis (fallback)
5. Inserts the correct interpretation atomically
6. Switches system layout to match the detected language

## Comparison with CGEvent Tap Approach

| Aspect | CGEvent Tap (papuga) | InputMethodKit (Drukar) |
|---|---|---|
| Text appears | Wrong first, corrected after space | Underlined, then correct |
| Replacement | Backspace+retype (~200ms) | Atomic `insertText` (instant) |
| Race conditions | Yes (fast typing loses chars) | None |
| Layout switch | Unreliable (tickle hack) | Clean (TISSelectInputSource) |
| App compatibility | Most apps | ALL apps |
| User setup | Accessibility permission | Add as Input Source |

## License

Private / not yet decided.
