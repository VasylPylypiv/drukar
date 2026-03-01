import Cocoa
import InputMethodKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var server: IMKServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        server = IMKServer(
            name: Bundle.main.infoDictionary?["InputMethodConnectionName"] as? String
                  ?? DrukarApp.connectionName,
            bundleIdentifier: Bundle.main.bundleIdentifier ?? DrukarApp.bundleIdentifier
        )
        DrukarLog.info("IMKServer started: bundle=\(Bundle.main.bundleIdentifier ?? "?") connection=\(Bundle.main.infoDictionary?["InputMethodConnectionName"] as? String ?? "?")")
    }

    func applicationWillTerminate(_ notification: Notification) {
        DrukarLog.info("Drukar terminating")
    }
}
