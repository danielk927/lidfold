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
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.stop()
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
