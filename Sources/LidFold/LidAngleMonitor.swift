import Foundation

/// Polls the lid angle sensor and reports a normalised "fold progress".
///
/// The sensor jitters by about a degree at rest, so raw readings are run
/// through an exponential smoother before being mapped to progress. Without
/// that the overlay visibly shimmers while the lid is held still.
final class LidAngleMonitor {

    /// Effect begins once the lid drops below this angle.
    static let foldStartAngle: Double = 75
    /// Effect is fully applied at or below this angle.
    static let foldEndAngle: Double = 5

    /// Weight of each new sample. Lower = smoother but laggier.
    private static let smoothingFactor: Double = 0.35

    /// Consecutive failed reads tolerated before the effect is torn down.
    /// Half a second at the default 60Hz.
    private static let maxFailedReads = 30

    /// How long "closing" stays latched after the lid stops moving down, so a
    /// pause partway through doesn't disarm the capture. 0.75s at 60Hz.
    private static let closingHoldTicks = 45
    /// Downward movement per tick that counts as closing rather than jitter.
    /// The sensor wanders about a degree at rest even after smoothing.
    private static let closingThreshold: Double = 0.15

    private var previousAngle: Double?
    private var closingTicks = 0
    private var failedReads = 0
    private let sensor: LidAngleSensor
    private let queue = DispatchQueue(label: "app.lidfold.sensor", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private var smoothedAngle: Double?

    /// Called on the main queue with fold progress in 0...1 and the smoothed
    /// hinge angle. The angle comes along because the capture needs to be up
    /// before the fold starts, which is a decision about angle, not progress.
    var onSample: ((_ progress: Double, _ angle: Double, _ isClosing: Bool) -> Void)?

    init(sensor: LidAngleSensor) {
        self.sensor = sensor
    }

    deinit { stop() }

    func start(hz: Double = 60) {
        stop()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 1.0 / hz)
        timer.setEventHandler { [weak self] in self?.sample() }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
        smoothedAngle = nil
        previousAngle = nil
        closingTicks = 0
        failedReads = 0
    }

    private func sample() {
        guard let raw = sensor.currentAngle() else {
            // The odd dropped read is normal. A run of them means the sensor
            // is gone, and staying silent would leave the overlay frozen on
            // screen at the last angle with nothing to bring it down — so
            // report the lid as open and let the effect tear itself down.
            failedReads += 1
            if failedReads == Self.maxFailedReads {
                // Report the lid as wide open so everything tears down.
                DispatchQueue.main.async { [weak self] in self?.onSample?(0, 180, false) }
            }
            return
        }
        failedReads = 0

        let smoothed: Double
        if let previous = smoothedAngle {
            smoothed = previous + (raw - previous) * Self.smoothingFactor
        } else {
            smoothed = raw
        }
        smoothedAngle = smoothed

        // Latched so a pause mid-close doesn't drop the capture and force it
        // to spin up again.
        if let previous = previousAngle, smoothed < previous - Self.closingThreshold {
            closingTicks = Self.closingHoldTicks
        } else if closingTicks > 0 {
            closingTicks -= 1
        }
        previousAngle = smoothed
        let isClosing = closingTicks > 0

        let progress = Self.progress(forAngle: smoothed)
        DispatchQueue.main.async { [weak self] in
            self?.onSample?(progress, smoothed, isClosing)
        }
    }

    /// Maps a hinge angle to 0 (untouched) ... 1 (fully folded).
    static func progress(forAngle angle: Double) -> Double {
        let span = foldStartAngle - foldEndAngle
        let raw = (foldStartAngle - angle) / span
        return min(max(raw, 0), 1)
    }
}
