import Foundation
import ScreenCaptureKit
import CoreMedia
import CoreVideo

/// Streams frames of a display via ScreenCaptureKit.
///
/// The overlay window must be excluded from the filter, otherwise the overlay
/// captures itself and the image recurses into a feedback tunnel.
final class ScreenCapturer: NSObject, SCStreamOutput {

    enum CaptureError: Error, CustomStringConvertible {
        case noDisplay
        case notPermitted

        var description: String {
            switch self {
            case .noDisplay:
                return "No display available to capture."
            case .notPermitted:
                return "Screen Recording permission is required. Grant it in "
                     + "System Settings > Privacy & Security > Screen Recording."
            }
        }
    }

    /// Asks for Screen Recording access up front.
    ///
    /// Capture would otherwise first be attempted while the lid is closing,
    /// which puts the TCC prompt on a screen the user can no longer see. The
    /// first call triggers the system prompt; later calls just report status.
    static func requestPermission() async -> Bool {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true
            )
            return true
        } catch {
            return false
        }
    }

    private var stream: SCStream?
    private let queue = DispatchQueue(label: "app.lidfold.capture", qos: .userInteractive)

    /// Called on an arbitrary queue with each captured frame.
    var onFrame: ((CVPixelBuffer) -> Void)?

    /// Starts capturing `display`, excluding the given windows from the frame.
    func start(excluding excludedWindows: [SCWindow], frameRate: Int = 60) async throws {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true
            )
        } catch {
            // SCK reports a generic failure when the TCC prompt has not been
            // accepted; surface the actionable message instead.
            throw CaptureError.notPermitted
        }

        guard let display = content.displays.first else { throw CaptureError.noDisplay }

        let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)

        let config = SCStreamConfiguration()
        config.width = display.width * 2      // Retina backing scale
        config.height = display.height * 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.queueDepth = 3
        config.showsCursor = false

        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() async {
        guard let stream else { return }
        try? await stream.stopCapture()
        self.stream = nil
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream,
                didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .screen,
              sampleBuffer.isValid,
              let pixelBuffer = sampleBuffer.imageBuffer else { return }
        onFrame?(pixelBuffer)
    }
}
