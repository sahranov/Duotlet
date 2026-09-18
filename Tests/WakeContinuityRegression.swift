import Foundation
@main struct WakeContinuityRegression {
    static func main() {
        var failures = 0
        let size = CGSize(width: 1512, height: 982)
        let geometry = DepthGeometry()
        for duration in [0.3, 0.6, 1.0] {
            var motion = PerspectiveMotion()
            var dimming = DimmingMotion()
            var lastMargin = 0.0
            var lastDim = ClosingDimming(angle: 120, startAngle: 120, maximum: 0.2)
            for frame in 0...Int(duration * 60) {
                let angle = 120 - 112 * Double(frame) / (duration * 60)
                let corners = geometry.corners(startAngle: 120, currentAngle: angle, viewingDistanceRatio: 6, recession: 0.5, screenSize: size)
                lastMargin = motion.advance(to: corners, screenSize: size, dt: 1.0 / 60)[3].x
                lastDim = dimming.advance(to: ClosingDimming(angle: angle, startAngle: 120, maximum: 0.2), dt: 1.0 / 60)
            }
            let wakeTarget = geometry.corners(startAngle: 120, currentAngle: 13, viewingDistanceRatio: 6, recession: 0.5, screenSize: size)
            let dimTarget = ClosingDimming(angle: 13, startAngle: 120, maximum: 0.2)
            motion.prepareForWake(margin: wakeTarget[3].x / size.width, preservingPresentation: true)
            dimming.prepareForWake(target: dimTarget, preservingPresentation: true)
            motion.beginRelease()
            dimming.beginRelease()
            let release = EffectRelease(elapsed: 0, motionElapsed: 0)
            let firstMargin = motion.advance(to: wakeTarget, screenSize: size, dt: 0, release: release)[3].x
            let firstDim = dimming.advance(to: dimTarget, dt: 0, release: release)
            let jump = abs(firstMargin - lastMargin)
            let brightnessJump = abs(firstDim.strength - lastDim.strength)
            if jump > 0.001 || brightnessJump > 0.0001 {
                failures += 1
                print("FAIL: wake after \(duration)s close jumps \(jump) pt and \(brightnessJump * 100)% dimming on its first frame")
            }
        }
        if failures > 0 { exit(1) }
        print("PASS: first wake frame exactly matches the retained pre-sleep geometry and brightness")
    }
}
