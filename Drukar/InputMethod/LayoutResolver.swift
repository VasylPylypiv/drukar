import Carbon.HIToolbox
import Foundation

/// Thin wrapper around TIS APIs for querying and switching keyboard layouts.
enum LayoutResolver {

    static func currentLayoutID() -> String {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return ""
        }
        return Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
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
