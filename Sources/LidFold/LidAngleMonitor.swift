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

    private let sensor: LidAngleSensor
    private let queue = DispatchQueue(label: "app.lidfold.sensor", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private var smoothedAngle: Double?

    /// Called on the main queue with progress in 0...1 whenever it changes.
    var onProgressChange: ((Double) -> Void)?

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
    }

    private func sample() {
        guard let raw = sensor.currentAngle() else { return }

        let smoothed: Double
        if let previous = smoothedAngle {
            smoothed = previous + (raw - previous) * Self.smoothingFactor
        } else {
            smoothed = raw
        }
        smoothedAngle = smoothed

        let progress = Self.progress(forAngle: smoothed)
        DispatchQueue.main.async { [weak self] in
            self?.onProgressChange?(progress)
        }
    }

    /// Maps a hinge angle to 0 (untouched) ... 1 (fully folded).
    static func progress(forAngle angle: Double) -> Double {
        let span = foldStartAngle - foldEndAngle
        let raw = (foldStartAngle - angle) / span
        return min(max(raw, 0), 1)
    }
}
