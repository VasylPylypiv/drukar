import Foundation
import OSLog

enum DrukarLog {
    private static let subsystem = "com.vasylpylypiv.inputmethod.Drukar"

    static let general = Logger(subsystem: subsystem, category: "General")
    static let detection = Logger(subsystem: subsystem, category: "Detection")
    static let layout = Logger(subsystem: subsystem, category: "Layout")

    static func info(_ message: String) {
        general.info("\(message, privacy: .public)")
    }

    static func debug(_ message: String) {
        general.debug("\(message, privacy: .public)")
    }

    static func warning(_ message: String) {
        general.warning("\(message, privacy: .public)")
    }

    static func error(_ message: String) {
        general.error("\(message, privacy: .public)")
    }
}
