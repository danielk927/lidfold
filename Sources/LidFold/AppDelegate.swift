import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var controller: FoldController?
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let sensor: LidAngleSensor
        do {
            sensor = try LidAngleSensor()
        } catch {
            presentFatal("\(error)")
            return
        }

        let controller = FoldController(sensor: sensor)
        self.controller = controller
        self.menuBar = MenuBarController(controller: controller)
        controller.start()

        // Prompt while the user is still looking at the screen, rather than
        // when the lid is already on its way shut.
        Task { @MainActor in
            if await !ScreenCapturer.requestPermission() {
                presentPermissionNotice()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.stop()
    }

    /// Non-fatal: the app keeps running so the effect starts working as soon
    /// as the user grants access, without needing a relaunch.
    private func presentPermissionNotice() {
        let alert = NSAlert()
        alert.messageText = "LidFold needs Screen Recording access"
        alert.informativeText =
            "The fold effect works by capturing what's on screen. Grant access "
            + "in System Settings > Privacy & Security > Screen Recording, then "
            + "reopen LidFold."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
            )!
            NSWorkspace.shared.open(url)
        }
    }

    private func presentFatal(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "LidFold can't run on this Mac"
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Quit")
        alert.runModal()
        NSApp.terminate(nil)
    }
}

/// Boots the menu-bar app. Never returns; `NSApplication.run()` only exits
/// through `NSApp.terminate`.
@MainActor
func runLidFoldApp() -> Never {
    let app = NSApplication.shared
    // Accessory: menu bar only, no Dock icon and no main window.
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    app.delegate = delegate
    // NSApplication holds its delegate weakly, so keep it alive across run().
    withExtendedLifetime(delegate) { app.run() }
    exit(0)
}
