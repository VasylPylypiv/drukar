import Carbon.HIToolbox
import Foundation

/// Thin wrapper around TIS APIs for querying and switching keyboard layouts.
enum LayoutResolver {

    private static let drukarBundlePrefix = "com.vasylpylypiv.inputmethod"
    private nonisolated(unsafe) static var _lastNonDrukarID: String?

    static func currentLayoutID() -> String {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return ""
        }
        let layoutID = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String

        if !layoutID.hasPrefix(drukarBundlePrefix) {
            _lastNonDrukarID = layoutID
        }

        return layoutID
    }

    /// Returns the last keyboard layout that was active before Drukar.
    /// Falls back to first available EN/UA layout.
    static func lastNonDrukarLayoutID() -> String? {
        if let cached = _lastNonDrukarID { return cached }

        // Try to find a sensible default from available layouts
        for layoutID in availableLayoutIDs() {
            if !layoutID.hasPrefix(drukarBundlePrefix) {
                _lastNonDrukarID = layoutID
                return layoutID
            }
        }
        return nil
    }

    static func availableLayoutIDs() -> [String] {
        let conditions = [
            kTISPropertyInputSourceCategory!: kTISCategoryKeyboardInputSource!,
            kTISPropertyInputSourceIsSelectCapable!: true,
        ] as CFDictionary

        guard let sourceList = TISCreateInputSourceList(conditions, false)?.takeRetainedValue() as? [TISInputSource] else {
            return []
        }

        return sourceList.compactMap { source in
            guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
            return Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
        }
    }

    static func sourceForID(_ layoutID: String) -> TISInputSource? {
        let conditions = [
            kTISPropertyInputSourceID!: layoutID,
        ] as CFDictionary

        guard let sourceList = TISCreateInputSourceList(conditions, false)?.takeRetainedValue() as? [TISInputSource],
              let source = sourceList.first else {
            return nil
        }
        return source
    }

    static func switchTo(_ layoutID: String) {
        guard let source = sourceForID(layoutID) else {
            DrukarLog.warning("switchTo: source not found for \(layoutID)")
            return
        }
        TISSelectInputSource(source)
        DrukarLog.debug("Switched layout to \(layoutID)")
    }
}
