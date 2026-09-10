import AppKit

/// Status-bar item: toggle the effect, quit. There is nothing to configure —
/// the look is fixed, so the menu is an off switch and a way out.
@MainActor
final class MenuBarController {

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let controller: FoldController

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

        let quit = NSMenuItem(title: "Quit LidFold", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    @objc private func toggleEnabled() {
        controller.isEnabled.toggle()
    }

    @objc private func quit() {
        controller.stop()
        NSApp.terminate(nil)
    }
}

/// Updates checkmarks and the error line each time the menu opens, so the menu
/// reflects current state without needing to observe the controller.
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
                item.state = controller?.isEnabled ?? true ? .on : .off
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
