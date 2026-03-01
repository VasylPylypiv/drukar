import Cocoa
import InputMethodKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var server: IMKServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        server = IMKServer(
            name: DrukarApp.connectionName,
            bundleIdentifier: DrukarApp.bundleIdentifier
        )
        DrukarLog.info("IMKServer started: \(DrukarApp.connectionName)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        DrukarLog.info("Drukar terminating")
    }
}
