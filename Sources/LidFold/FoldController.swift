import AppKit
import ScreenCaptureKit

/// Wires the sensor to the overlay: starts capture when the lid begins to
/// close, drives the fold, and tears everything down once the lid is open
/// again so an idle machine isn't paying for a 60fps screen capture.
@MainActor
final class FoldController {

    private let monitor: LidAngleMonitor
    private let capturer = ScreenCapturer()
    private var overlay: FoldOverlayWindow?

    private enum CaptureState { case idle, starting, running, stopping }
    private var captureState: CaptureState = .idle

    /// Whether the overlay belongs on screen. The single owner of that answer —
    /// capture state can't be it, because the stream keeps delivering frames
    /// while it winds down.
    private var isFolding = false

    /// Reported to the menu bar so it can show why the effect isn't running.
    private(set) var lastError: String?

    /// When non-nil, drives the fold directly and the sensor is ignored. The
    /// effect is otherwise only observable while the lid is shut, which is
    /// exactly when nobody can look at it.
    var previewProgress: Double? {
        didSet { apply(progress: previewProgress ?? 0) }
    }

    init(sensor: LidAngleSensor) {
        monitor = LidAngleMonitor(sensor: sensor)
        monitor.onProgressChange = { [weak self] progress in
            self?.handle(progress: progress)
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

    private func handle(progress: Double) {
        guard previewProgress == nil else { return }
        apply(progress: progress)
    }

    private func apply(progress: Double) {
        guard FoldSettings.shared.isEnabled, progress > 0 else {
            teardown()
            return
        }

        isFolding = true
        ensureOverlay()
        overlay?.foldView.setProgress(progress)

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
