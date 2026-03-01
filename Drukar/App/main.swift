import Cocoa
import InputMethodKit

@main
struct DrukarApp {
    static let connectionName = "Drukar_Connection"
    static let bundleIdentifier = "com.vasylpylypiv.inputmethod.Drukar"

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
