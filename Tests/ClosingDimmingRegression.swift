import Foundation

@main struct ClosingDimmingRegression {
    static func main() {
        func dim(_ angle: Double, start: Double = 90) -> ClosingDimming {
            ClosingDimming(angle: angle, startAngle: start, maximum: 0.2)
        }
        for start in [55.0, 90, 120] {
            var previousTop = 0.0
            var previousHinge = 0.0
            for step in 0...Int(start * 10) {
                let value = dim(start - Double(step) / 10, start: start)
                let top = value.strength * value.maximum
                let hinge = top * value.hingeFloor
                precondition(top >= previousTop && hinge >= previousHinge,
                             "both screen edges must darken monotonically")
                precondition((0...1).contains(top) && (0...1).contains(hinge))
                previousTop = top
                previousHinge = hinge
            }
            let first = dim(start - 1, start: start).strength
            precondition(first >= 0 && first < 0.001,
                         "first degree must start gently, with no dimming above 90°")
        }
        precondition(ClosingDimming.blackout(angle: 30) == 0)
        precondition(ClosingDimming.blackout(angle: 29) > 0)
        precondition(ClosingDimming.blackout(angle: 15) == 0.5)
        precondition(ClosingDimming.blackout(angle: 0) == 1)
        precondition(dim(0).strength * dim(0).hingeFloor == 1)
        let earlyGain = dim(89).strength - dim(90).strength
        let lateGain = dim(19).strength - dim(20).strength
        precondition(lateGain > earlyGain * 5, "below 30 degrees the ramp must become stronger")

        for fps in [30, 60, 120] {
            let dt = 1 / Double(fps)
            var motion = DimmingMotion()
            var previous = 0.0
            // A 10 Hz sensor closing at 20 degrees/second, rendered at display rate.
            for frame in 0...(fps * 4) {
                let angle = 90 - Double(frame * 10 / fps) * 2
                let value = motion.advance(to: dim(angle), dt: dt)
                precondition(value.strength >= previous - 1e-12)
                precondition(value.strength - previous < 0.04 * 60 / Double(fps),
                             "sensor steps must not become brightness jumps")
                previous = value.strength
            }
            // Release is anchored to actual displayed brightness, even if the
            // next closing run uses a different start angle.
            for cycle in 0..<4 {
                motion.beginRelease()
                let duration = cycle == 3 ? EffectRelease.duration : 0.2
                for frame in 0...Int(ceil(duration * Double(fps))) {
                    let release = EffectRelease(elapsed: Double(frame) * dt)
                    let value = motion.advance(to: dim(65, start: 66), dt: dt, release: release)
                    if frame == 0 { precondition(abs(value.strength - previous) < 1e-12) }
                    precondition(value.strength <= previous + 1e-12)
                    if release.opacity < 1 { precondition(value.strength == 0) }
                    previous = value.strength
                }
                if cycle < 3 {
                    let value = motion.advance(to: dim(64, start: 66), dt: dt)
                    precondition(abs(value.strength - previous) < 0.03 * 60 / Double(fps),
                                 "reclosing with a new origin must preserve brightness")
                    previous = value.strength
                }
            }
            precondition(previous == 0)
        }
        print("PASS: delayed gentle dimming, stronger below 30°, continuous sensor steps and reversals")
    }
}
