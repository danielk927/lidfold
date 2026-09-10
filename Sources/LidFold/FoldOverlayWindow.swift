import AppKit

/// A full-screen, click-through window that hosts the fold effect.
///
/// It sits above ordinary windows but must never take focus or swallow input:
/// the user is closing their laptop, not interacting with us.
final class FoldOverlayWindow: NSWindow {

    let foldView: FoldView

    init(screen: NSScreen) {
        let view = FoldView(frame: NSRect(origin: .zero, size: screen.frame.size))
        self.foldView = view

        // Must be the designated initializer. The `screen:` variant is a
        // convenience initializer that re-dispatches to this one on `self`,
        // which traps here because the subclass doesn't inherit it. `contentRect`
        // is in global coordinates, so `screen.frame` already targets that screen.
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        // Above normal windows and full-screen apps, below the login shield.
        level = NSWindow.Level(Int(CGShieldingWindowLevel()) - 1)
        collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .fullScreenAuxiliary,
            .ignoresCycle,
        ]
        // Keeps the window out of Mission Control and screenshot pickers.
        isExcludedFromWindowsMenu = true
        contentView = view
        alphaValue = 0
    }

    /// Borderless windows refuse key status by default; make that explicit so
    /// nothing steals focus from whatever the user was doing.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show() {
        guard !isVisible else { return }
        orderFrontRegardless()
    }

    func hide() {
        guard isVisible else { return }
        orderOut(nil)
    }

    /// Overall opacity of the effect, driven by fold progress so the overlay
    /// fades in rather than popping on at the threshold angle.
    func setEffectOpacity(_ value: Double) {
        alphaValue = CGFloat(min(max(value, 0), 1))
    }
}
