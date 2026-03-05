import Cocoa
import SwiftUI

final class SettingsWindowController: NSObject, NSWindowDelegate, @unchecked Sendable {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    private override init() {
        super.init()
    }

    func showSettings() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            if let window = self.window, window.isVisible {
                window.makeKeyAndOrderFront(nil)
                NSApp.setActivationPolicy(.accessory)
                NSApp.activate(ignoringOtherApps: true)
                return
            }

            let settingsView = SettingsView()
            let hostingController = NSHostingController(rootView: settingsView)

            let window = NSWindow(contentViewController: hostingController)
            window.title = "Друкар — Налаштування"
            window.styleMask = [.titled, .closable]
            window.center()
            window.isReleasedWhenClosed = false
            window.level = .floating
            window.delegate = self

            self.window = window

            NSApp.setActivationPolicy(.accessory)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.prohibited)
        }
    }
}
