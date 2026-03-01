import Carbon.HIToolbox
import Foundation

struct KeyMapping {
    let keyCode: UInt16
    let needsShift: Bool
}

struct KeycodeCharacters {
    let normal: Character?
    let shifted: Character?
}

final class CharacterMapper {
    private var forwardMaps: [String: [Character: KeyMapping]] = [:]
    private var reverseMaps: [String: [UInt16: KeycodeCharacters]] = [:]

    private static let maxKeyCode: UInt16 = 127

    func buildMap(for source: TISInputSource, sourceID: String) {
        if forwardMaps[sourceID] != nil { return }

        guard let layoutDataPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            DrukarLog.warning("buildMap: layoutData missing for \(sourceID)")
            return
        }

        let layoutData = Unmanaged<CFData>.fromOpaque(layoutDataPtr).takeUnretainedValue()
        let dataPtr = CFDataGetBytePtr(layoutData)!
        let keyboardLayout = dataPtr.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { $0 }
        let keyboardType = UInt32(LMGetKbdType())

        var forwardMap: [Character: KeyMapping] = [:]
        var reverseMap: [UInt16: KeycodeCharacters] = [:]

        for keyCode: UInt16 in 0...Self.maxKeyCode {
            let normalChar = translateKeyCode(keyCode, shift: false, layout: keyboardLayout, keyboardType: keyboardType)
            let shiftedChar = translateKeyCode(keyCode, shift: true, layout: keyboardLayout, keyboardType: keyboardType)

            reverseMap[keyCode] = KeycodeCharacters(normal: normalChar, shifted: shiftedChar)

            if let char = normalChar, forwardMap[char] == nil {
                forwardMap[char] = KeyMapping(keyCode: keyCode, needsShift: false)
            }
            if let char = shiftedChar, forwardMap[char] == nil {
                forwardMap[char] = KeyMapping(keyCode: keyCode, needsShift: true)
            }
        }

        forwardMaps[sourceID] = forwardMap
        reverseMaps[sourceID] = reverseMap
    }

    func characterForKeyCode(_ keyCode: UInt16, shifted: Bool, sourceID: String) -> Character? {
        guard let reverseMap = reverseMaps[sourceID],
              let chars = reverseMap[keyCode] else { return nil }
        return shifted ? chars.shifted : chars.normal
    }

    func invalidateCache() {
        forwardMaps.removeAll()
        reverseMaps.removeAll()
    }

    private func translateKeyCode(
        _ keyCode: UInt16,
        shift: Bool,
        layout: UnsafePointer<UCKeyboardLayout>,
        keyboardType: UInt32
    ) -> Character? {
        let modifierKeyState: UInt32 = shift ? (UInt32(shiftKey >> 8) & 0xFF) : 0
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length: Int = 0

        let status = UCKeyTranslate(
            layout,
            keyCode,
            UInt16(kUCKeyActionDisplay),
            modifierKeyState,
            keyboardType,
            UInt32(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            chars.count,
            &length,
            &chars
        )

        guard status == noErr, length > 0 else { return nil }
        guard let scalar = UnicodeScalar(chars[0]) else { return nil }
        let character = Character(scalar)

        if character.isNewline || character.asciiValue == 0 { return nil }
        return character
    }
}
