import Foundation
import IOKit
import IOKit.hid

/// Reads the hinge angle from the MacBook's built-in lid angle sensor.
///
/// The sensor is exposed as a HID device on the Sensor usage page (0x20)
/// with usage 0x8A. Feature report 1 carries the angle as a little-endian
/// 9-bit value in degrees (logical range 0...360):
///
///     byte 0: report ID (0x01)
///     byte 1: angle low byte
///     byte 2: angle high bit
///
/// Determined empirically by walking the device's HID element tree; the
/// element for report 1 is usage 0x047F with logicalMax 360.
final class LidAngleSensor {

    enum SensorError: Error, CustomStringConvertible {
        case notFound
        case openFailed(IOReturn)

        var description: String {
            switch self {
            case .notFound:
                return "No lid angle sensor found. This Mac may not have one "
                     + "(it requires an Apple silicon MacBook)."
            case .openFailed(let r):
                return "Could not open the lid angle sensor (IOReturn 0x"
                     + String(format: "%08X", UInt32(bitPattern: r)) + ")."
            }
        }
    }

    private static let sensorUsagePage = 0x20
    private static let sensorUsage = 0x8A
    private static let angleReportID: CFIndex = 1

    private let device: IOHIDDevice

    init() throws {
        guard let device = Self.findSensorDevice() else { throw SensorError.notFound }
        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else { throw SensorError.openFailed(result) }
        self.device = device
    }

    deinit {
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    /// Current hinge angle in degrees, or nil if the report read failed.
    ///
    /// Roughly: 0 = fully closed, ~90 = upright, up to ~130+ fully open.
    func currentAngle() -> Double? {
        var report = [UInt8](repeating: 0, count: 8)
        var length = report.count

        let result = IOHIDDeviceGetReport(
            device, kIOHIDReportTypeFeature, Self.angleReportID, &report, &length
        )
        guard result == kIOReturnSuccess, length >= 3 else { return nil }

        let raw = Int(report[1]) | (Int(report[2]) << 8)
        // The element is declared 0...360; anything outside is a bad read.
        guard (0...360).contains(raw) else { return nil }
        return Double(raw)
    }

    private static func findSensorDevice() -> IOHIDDevice? {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, nil)
        // Opening the manager reports "not privileged" for the full device set,
        // but individual sensor devices still open fine, so the result is ignored.
        _ = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            return nil
        }
        return devices.first { device in
            property(device, kIOHIDPrimaryUsagePageKey) == sensorUsagePage &&
            property(device, kIOHIDPrimaryUsageKey) == sensorUsage
        }
    }

    private static func property(_ device: IOHIDDevice, _ key: String) -> Int? {
        IOHIDDeviceGetProperty(device, key as CFString) as? Int
    }
}
