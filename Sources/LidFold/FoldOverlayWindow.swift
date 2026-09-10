import AppKit

/// A full-screen, click-through window that hosts the fold effect.
///
/// It sits above ordinary windows but must never take focus or swallow input:
/// the user is closing their laptop, not interacting with us.
final class FoldOverlayWindow: NSWindow {

    let foldView: MetalFoldView

    init(screen: NSScreen) {
        let view = MetalFoldView(frame: NSRect(origin: .zero, size: screen.frame.size))
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

    /// How long the overlay takes to come up.
    static let revealDuration: TimeInterval = 0.18

    /// Reveals the overlay by dissolving it in over the desktop.
    ///
    /// It has to end fully opaque — it stands in for the screen, and holding it
    /// part-transparent while the fold deepens shows the sharp desktop through
    /// the folded image as a double exposure. But swapping straight to opaque
    /// is a hard cut, and a hard cut between two nearly-identical images still
    /// reads as a jump: whatever slight difference remains — a frame of
    /// capture latency, a cursor mid-move — arrives all at once.
    ///
    /// So it fades, briefly, and only here. The fade finishes while progress is
    /// still near zero and the shader is drawing the capture 1:1, so there is
    /// no fold to double-expose. Idempotent, because this is called on every
    /// captured frame and restarting the fade would stutter it.
    func show() {
        guard !isVisible else { return }
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.revealDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }
    }

    func hide() {
        guard isVisible else { return }
        // Cancel any fade still in flight, or it carries on setting alpha back
        // up on a window that is meant to be coming down.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            animator().alphaValue = 0
        }
        alphaValue = 0
        orderOut(nil)
    }
}
