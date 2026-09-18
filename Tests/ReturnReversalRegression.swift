import Foundation

@main struct ReturnReversalRegression {
    static func main() {
        var failures = 0
        func check(_ pass: Bool, _ label: String) {
            if !pass { failures += 1; print("FAIL: \(label)") }
        }
        for fps in [30, 60, 120] {
            let dt = 1 / Double(fps)
            // Reopen during the fade, close for only one sensor tick, then
            // reopen again: opacity must never restart from one.
            var opacity = PresentationOpacity()
            _ = opacity.advance(release: 0.2, dt: dt)
            let before = opacity.advance(release: nil, dt: dt)
            check(before == 1, "reclosing must not warp a translucent desktop")
            opacity.beginRelease()
            check(abs(opacity.advance(release: 1, dt: dt) - before) < 1e-12,
                  "opacity jumps on a second opening at \(fps) Hz")

            let size = CGSize(width: 1512, height: 982)
            for travel in [3.0, 8, 16, 40] {
                var motion = PerspectiveMotion()
                let target = DepthGeometry().corners(startAngle: 90, currentAngle: 90 - travel,
                    viewingDistanceRatio: 6, recession: 1, screenSize: size)
                var previous = 0.0
                var maximumStep = 0.0
                // Multiple direction changes before any return has finished.
                for cycle in 0..<4 {
                    for _ in 0..<Int(Double(fps) * 0.2) {
                        let points = motion.advance(to: target, screenSize: size, dt: dt)
                        previous = points[3].x
                    }
                    motion.beginRelease()
                    let duration = cycle == 3 ? EffectRelease.duration : 0.25
                    for frame in 0...Int(ceil(duration * Double(fps))) {
                        let release = EffectRelease(elapsed: Double(frame) * dt)
                        let points = motion.advance(to: target, screenSize: size, dt: dt, release: release)
                        maximumStep = max(maximumStep, abs(points[3].x - previous))
                        previous = points[3].x
                        if release.opacity < 1 { check(previous < 0.25, "fade exposes displaced desktop") }
                    }
                }
                check(previous == 0, "repeated movement must end exactly flat")
                print("\(fps) Hz, travel \(travel): maximum return movement \(maximumStep) pt/frame")
                check(maximumStep < 7 * 60 / Double(fps), "repeated movement jumps at \(fps) Hz")
            }
        }
        print(failures == 0 ? "PASS: small closes and repeated reversals preserve position and opacity" : "FAIL: \(failures) reversal checks")
        if failures > 0 { exit(1) }
    }
}
