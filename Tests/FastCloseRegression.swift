import Foundation
@main struct FastCloseRegression {
    static func main() {
        var failures = 0
        let size = CGSize(width: 1512, height: 982)
        for fps in [30, 60, 120] {
            var motion = PerspectiveMotion()
            var previous = 0.0
            var maxSpeed = 0.0
            var earlyInset = 0.0
            // First usable capture arrives after the lid has already travelled
            // 35 degrees. The same geometry boundary must still reveal gently.
            let target = DepthGeometry().corners(startAngle: 90, currentAngle: 55,
                viewingDistanceRatio: 6, recession: 0.5, screenSize: size)
            for frame in 1...(fps * 3) {
                let points = motion.advance(to: target, screenSize: size, dt: 1 / Double(fps))
                maxSpeed = max(maxSpeed, abs(points[3].x - previous) * Double(fps) / size.width)
                previous = points[3].x
                if frame == Int(Double(fps) * 0.1) { earlyInset = previous }
            }
            print("\(fps) Hz: first 100 ms \(earlyInset) pt, peak \(maxSpeed * size.width) pt/s")
            if earlyInset > 2 { print("FAIL: fast close abruptly reveals side borders"); failures += 1 }
            if maxSpeed > 0.055 { print("FAIL: borders accelerate to catch up with lid"); failures += 1 }
            if abs(previous - target[3].x) > 1 { print("FAIL: held target never settles"); failures += 1 }
        }
        if failures > 0 { exit(1) }
        print("PASS: fast closing has a gentle onset and bounded visible speed")
    }
}
