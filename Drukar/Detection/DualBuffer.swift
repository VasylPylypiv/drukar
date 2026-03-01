import Carbon.HIToolbox

struct DualKeystroke {
    let keyCode: UInt16
    let enChar: Character?
    let uaChar: Character?
    let isShifted: Bool
}

final class DualBuffer {
    private(set) var keystrokes: [DualKeystroke] = []

    var enWord: String {
        String(keystrokes.compactMap(\.enChar))
    }

    var uaWord: String {
        String(keystrokes.compactMap(\.uaChar))
    }

    var keystrokeCount: Int {
        keystrokes.count
    }

    var isEmpty: Bool {
        keystrokes.isEmpty
    }

    func append(_ keystroke: DualKeystroke) {
        keystrokes.append(keystroke)
    }

    func clear() {
        keystrokes.removeAll()
    }

    func removeLast() {
        guard !keystrokes.isEmpty else { return }
        keystrokes.removeLast()
    }

    static let wordBoundaryKeyCodes: Set<UInt16> = [
        0x31, // space
        0x24, // return
        0x30, // tab
        0x4C, // enter (numpad)
    ]
}
