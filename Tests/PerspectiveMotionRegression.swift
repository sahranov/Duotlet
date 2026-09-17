import Foundation
import CoreGraphics

@main struct PerspectiveMotionRegression {
    static func main() {
        let size = CGSize(width: 1512, height: 982)
        var failures = 0
        func check(_ pass: Bool, _ label: String) {
            if !pass { print("FAIL: \(label)"); failures += 1 }
        }
        // Replay 10 Hz lid samples through the same projection/presentation
        // boundary used by DepthOverlay, including opening and mode changes.
        for fps in [30, 60, 120] {
            var motion = PerspectiveMotion()
            var previous = 0.0
            var maximumStep = 0.0
            var maximumAcceleration = 0.0
            var previousStep = 0.0
            for frame in 0..<(fps * 4) {
                let time = Double(frame) / Double(fps)
                let sampleTime = floor(time * 10) / 10
                let opening = time >= 1.2
                let angle = opening ? min(48 + (sampleTime - 1.2) * 20, 80) : 90 - sampleTime * 35
                let target = DepthGeometry().corners(startAngle: 90,
                    currentAngle: angle, viewingDistanceRatio: 6, recession: 1,
                    screenSize: size, strength: opening ? EffectRelease(elapsed: time - 1.2).strength : 1)
                let points = motion.advance(to: target, screenSize: size, dt: 1 / Double(fps),
                    release: opening ? EffectRelease(elapsed: time - 1.2) : nil)
                let inset = points[3].x
                let step = inset - previous
                maximumStep = max(maximumStep, abs(step))
                maximumAcceleration = max(maximumAcceleration, abs(step - previousStep))
                check(points[0] == .zero && points[1] == CGPoint(x: size.width, y: 0), "hinge moved")
                check(points[2].y == size.height && points[3].y == size.height, "screen height changed")
                previous = inset
                previousStep = step
            }
            print("\(fps) Hz: max frame step \(maximumStep), max step change \(maximumAcceleration)")
            check(maximumStep < 7 * 60 / Double(fps), "perspective jumps between frames at \(fps) Hz")
            check(maximumAcceleration < 2 * pow(60 / Double(fps), 2), "perspective velocity jumps at \(fps) Hz")
            check(abs(previous) < 0.1, "opening did not return to flat")
        }
        let closing = DepthGeometry().corners(startAngle: 90, currentAngle: 30,
            viewingDistanceRatio: 6, recession: 1, screenSize: size)
        check(closing[3].x >= size.width * 0.08, "closing side inserts are narrower than 8% per side")
        // The native desktop underneath has a different position while the
        // captured desktop is tapered. Fading between those two positions
        // makes text double and appear to jump, even at a perfect 60 Hz.
        var returning = PerspectiveMotion()
        for _ in 0..<180 { _ = returning.advance(to: closing, screenSize: size, dt: 1 / 60) }
        var largestExposedOffset = 0.0
        for frame in 0...Int(ceil(EffectRelease.duration * 60)) {
            let release = EffectRelease(elapsed: Double(frame) / 60)
            let target = DepthGeometry().corners(startAngle: 90, currentAngle: 30,
                viewingDistanceRatio: 6, recession: 1, screenSize: size, strength: release.strength)
            let points = returning.advance(to: target, screenSize: size, dt: 1 / 60, release: release)
            if release.opacity < 0.99 && release.opacity > 0.01 {
                largestExposedOffset = max(largestExposedOffset, points[3].x)
            }
        }
        print("Return: desktop exposed while captured text is offset by \(largestExposedOffset) pt")
        check(largestExposedOffset < 0.25, "return crossfades two different desktop positions")
        // The spring's result must depend on elapsed time, not refresh rate.
        var reference = CriticallyDampedSpring()
        reference.advance(to: 1, dt: 0.3)
        for fps in [30, 60, 120] {
            var spring = CriticallyDampedSpring()
            for _ in 0..<Int(Double(fps) * 0.3) { spring.advance(to: 1, dt: 1 / Double(fps)) }
            check(abs(spring.value - reference.value) < 1e-10, "spring changes with refresh rate")
            for target in [0.0, 1, 0, 0.5, 0] {
                spring.advance(to: target, dt: 0.05)
                check((0...1).contains(spring.value), "spring overshoots after a late frame or reversal")
            }
        }
        print(failures == 0 ? "PASS: smooth sensor replay and stronger closing inserts" : "FAIL: \(failures) checks")
        if failures > 0 { exit(1) }
    }
}
