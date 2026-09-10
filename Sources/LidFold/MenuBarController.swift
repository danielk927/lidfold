import AppKit

/// Status-bar item: toggle the effect, open settings, quit.
@MainActor
final class MenuBarController {

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let controller: FoldController
    private lazy var preferences = PreferencesWindow()

    init(controller: FoldController) {
        self.controller = controller

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "laptopcomputer",
                accessibilityDescription: "LidFold"
            )
        }
        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = MenuRefresher.shared
        MenuRefresher.shared.controller = controller

        let toggle = NSMenuItem(
            title: "Enable Fold Effect",
            action: #selector(toggleEnabled),
            keyEquivalent: ""
        )
        toggle.target = self
        toggle.identifier = MenuRefresher.toggleIdentifier
        menu.addItem(toggle)

        let status = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        status.identifier = MenuRefresher.statusIdentifier
        status.isHidden = true
        status.isEnabled = false
        menu.addItem(status)

        menu.addItem(.separator())

        let settings = NSMenuItem(
            title: "Settings…", action: #selector(openSettings), keyEquivalent: ","
        )
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit LidFold", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    @objc private func toggleEnabled() {
        FoldSettings.shared.isEnabled.toggle()
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        preferences.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() {
        controller.stop()
        NSApp.terminate(nil)
    }
}

/// Updates checkmarks and the error line each time the menu opens, so the menu
/// reflects current state without needing to observe every setting.
@MainActor
final class MenuRefresher: NSObject, NSMenuDelegate {
    static let shared = MenuRefresher()
    static let toggleIdentifier = NSUserInterfaceItemIdentifier("toggle")
    static let statusIdentifier = NSUserInterfaceItemIdentifier("status")

    weak var controller: FoldController?

    func menuNeedsUpdate(_ menu: NSMenu) {
        for item in menu.items {
            switch item.identifier {
            case Self.toggleIdentifier:
                item.state = FoldSettings.shared.isEnabled ? .on : .off
            case Self.statusIdentifier:
                if let error = controller?.lastError {
                    item.title = error
                    item.isHidden = false
                } else {
                    item.isHidden = true
                }
            default:
                break
            }
        }
    }
}
