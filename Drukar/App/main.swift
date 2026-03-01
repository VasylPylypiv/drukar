import Cocoa
import InputMethodKit

enum DrukarApp {
    static let connectionName = "com.vasylpylypiv.inputmethod.Drukar_Connection"
    static let bundleIdentifier = "com.vasylpylypiv.inputmethod.Drukar"
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
