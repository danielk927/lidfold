import Foundation

// `lidfold --angle [count]` prints the live hinge angle. Useful for confirming
// the sensor works on a given machine before worrying about the overlay.
// Without a count it streams until interrupted.
if let flagIndex = CommandLine.arguments.firstIndex(of: "--angle") {
    let limit = CommandLine.arguments.dropFirst(flagIndex + 1).first.flatMap(Int.init)
    do {
        let sensor = try LidAngleSensor()
        var taken = 0
        while limit == nil || taken < limit! {
            if let angle = sensor.currentAngle() {
                print(String(format: "  %5.1f°", angle))
            } else {
                print("  (read failed)")
            }
            fflush(stdout)
            taken += 1
            if limit == nil || taken < limit! { Thread.sleep(forTimeInterval: 0.25) }
        }
        exit(0)
    } catch {
        FileHandle.standardError.write("\(error)\n".data(using: .utf8)!)
        exit(1)
    }
}
