import AppKit
import ScreenCaptureKit

/// Wires the sensor to the overlay: starts capture when the lid begins to
/// close, drives the fold, and tears everything down once the lid is open
/// again so an idle machine isn't paying for a 60fps screen capture.
@MainActor
final class FoldController {

    /// The capture is brought up at this angle — but only while the lid is
    /// actually on its way down. Starting it at the fold threshold instead
    /// means SCStream is still spinning up as the lid keeps travelling, and the
    /// first frame lands with the fold already part way in, which is the snap
    /// you see in place of a transition. Arming on angle alone would leave a
    /// 60fps capture running through ordinary use, since people work at well
    /// under this angle.
    private static let preArmAngle = LidAngleMonitor.foldStartAngle + 25

    private let monitor: LidAngleMonitor
    private let capturer = ScreenCapturer()
    private var overlay: FoldOverlayWindow?

    private enum CaptureState { case idle, starting, running, stopping }
    private var captureState: CaptureState = .idle

    /// Whether the overlay belongs on screen. The single owner of that answer —
    /// capture state can't be it, because the stream keeps delivering frames
    /// while it winds down.
    private var isFolding = false

    /// The fold angle actually being drawn, easing toward the sensor's. The
    /// gate that holds progress at zero until the lid is confirmed to be
    /// closing releases as a step: the moment it opens, progress goes straight
    /// from nothing to wherever the lid already is, and the screen lurches into
    /// a fold rather than starting one. Easing turns any such step into a
    /// ramp, wherever it comes from.
    private var drawnProgress: Double = 0
    private var lastTick: CFTimeInterval?
    /// Time constant. Long enough to swallow a step, short enough that the fold
    /// still tracks the hinge rather than lagging behind it.
    private static let followTau: Double = 0.09

    /// Reported to the menu bar so it can show why the effect isn't running.
    private(set) var lastError: String?

    /// When non-nil, drives the fold directly and the sensor is ignored. The
    /// effect is otherwise only observable while the lid is shut, which is
    /// exactly when nobody can look at it.
    var previewProgress: Double? {
        didSet {
            // Angle 0 keeps the capture armed for as long as the preview is on.
            if let previewProgress { apply(progress: previewProgress, armed: true) }
            else { teardown() }
        }
    }

    init(sensor: LidAngleSensor) {
        monitor = LidAngleMonitor(sensor: sensor)
        monitor.onSample = { [weak self] progress, angle, isClosing in
            self?.handle(progress: progress, angle: angle, isClosing: isClosing)
        }
        capturer.onFrame = { [weak self] buffer in
            Task { @MainActor in
                guard let self, let overlay = self.overlay else { return }
                overlay.foldView.update(with: buffer)
                // Reveal only once there is a frame to draw — an empty overlay
                // is a black rectangle over the desktop — and only while the
                // fold is still meant to be up. Frames keep arriving for a
                // moment after teardown because the stream stops asynchronously,
                // and revealing on one of those strands a full-screen opaque
                // window on the display with nothing left to take it down.
                guard self.isFolding else { return }
                overlay.show()
            }
        }
    }

    func start() { monitor.start() }

    func stop() {
        monitor.stop()
        teardown()
    }

    private func handle(progress: Double, angle: Double, isClosing: Bool) {
        guard previewProgress == nil else { return }
        // Progress is gated on the lid actually travelling downward. The fold
        // now starts at 95 degrees, which people work at, so angle alone would
        // leave the desktop folded while they sat in front of it.
        apply(progress: isClosing ? progress : 0,
              armed: isClosing && angle <= Self.preArmAngle)
    }

    private func apply(progress: Double, armed: Bool) {
        guard FoldSettings.shared.isEnabled, armed || progress > 0 else {
            teardown()
            return
        }

        ensureOverlay()

        // Up for the whole close, including the stretch before the fold starts,
        // where the shader draws the capture 1:1 and the overlay is
        // indistinguishable from the desktop behind it.
        //
        // Toggling on progress crossing zero instead means the window gets
        // ordered in and out of the window server as the smoothed angle jitters
        // across the threshold — at 60Hz, which is the screen visibly popping
        // out and dropping back.
        isFolding = true

        let now = CACurrentMediaTime()
        let dt = min(now - (lastTick ?? now - 1.0 / 60.0), 0.1)
        lastTick = now
        drawnProgress += (progress - drawnProgress) * (1 - exp(-dt / Self.followTau))
        if abs(progress - drawnProgress) < 0.001 { drawnProgress = progress }
        overlay?.foldView.setProgress(drawnProgress)

        if captureState == .idle { beginCapture() }
    }

    private func ensureOverlay() {
        guard overlay == nil, let screen = NSScreen.main else { return }
        overlay = FoldOverlayWindow(screen: screen)
    }

    private func beginCapture() {
        captureState = .starting
        Task { @MainActor in
            do {
                let excluded = await self.overlayWindowsToExclude()
                try await capturer.start(excluding: excluded)
                // The lid may have reopened while we were awaiting permission.
                if captureState == .starting {
                    captureState = .running
                    lastError = nil
                } else {
                    await capturer.stop()
                    captureState = .idle
                }
            } catch {
                lastError = "\(error)"
                captureState = .idle
                isFolding = false
                overlay?.hide()
            }
        }
    }

    /// Finds our own overlay in the shareable content so the capture filter can
    /// drop it. Matching is by CGWindowID, which is what SCWindow exposes.
    private func overlayWindowsToExclude() async -> [SCWindow] {
        guard let overlay else { return [] }
        let overlayID = CGWindowID(overlay.windowNumber)
        guard let content = try? await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: false
        ) else { return [] }
        return content.windows.filter { $0.windowID == overlayID }
    }

    private func teardown() {
        // Unconditional, on every path. The overlay is a full-screen opaque
        // window sitting just below the shielding level, so leaving it up by
        // mistake locks the user out of their own display — clicks land on
        // windows they can no longer see, and the menu bar is covered. It has
        // to come down regardless of what the capture state believes.
        isFolding = false
        drawnProgress = 0
        lastTick = nil
        overlay?.hide()
        guard captureState == .running || captureState == .starting else {
            captureState = .idle
            return
        }
        captureState = .stopping
        Task { @MainActor in
            await capturer.stop()
            captureState = .idle
        }
    }
}
