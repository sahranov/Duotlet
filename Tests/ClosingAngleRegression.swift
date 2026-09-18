import Foundation

@main struct ClosingAngleRegression {
    static func main() {
        var failures = 0
        func check(_ condition: Bool, _ message: String) {
            if !condition { print("FAIL: \(message)"); failures += 1 }
        }
        let gradient = BlurGradient()
        func radius(_ angle: Double, start: Double = 130) -> Double {
            69 * BlurGradient.radiusScale * gradient.blurStrength(
                progress: BlurGradient.closingProgress(angle: angle, startAngle: start))
        }
        for angle in [130.0, 110, 90, 80, 70, 60, 45, 30] {
            print("\(angle)°: radius \(radius(angle)) pt; dim \(ClosingDimming(angle: angle, startAngle: 130, maximum: 0.2).strength)")
        }
        check(abs(radius(90) - 8) < 1e-9, "130° → 90° must reach the requested 8 pt")
        check(abs(radius(30) - 24.15) < 1e-9, "preserve the established 30° blur ceiling")
        var previous = 0.0
        for degree in stride(from: 130.0, through: 0, by: -1) {
            let value = radius(degree)
            check(value >= previous - 1e-9, "blur must not decrease while closing at \(degree)°")
            check(value - previous <= 2, "one degree must not add more than 2 pt")
            previous = value
            if degree >= 90 {
                check(ClosingDimming(angle: degree, startAngle: 130, maximum: 0.2).strength == 0,
                      "dimming must wait until below 90°, now \(degree)°")
            }
        }
        for fps in [30, 60, 120] {
            for start in [100.0, 130, 150, 180] {
                var envelope = BlurEnvelope()
                var dimming = DimmingMotion()
                // A single abrupt sensor step, including capture arriving late.
                // Hold long enough to catch both the transient and final target.
                for _ in 0..<fps * 2 {
                    envelope.advance(target: BlurGradient.closingProgress(angle: 90, startAngle: start), dt: 1 / Double(fps))
                    let blur = 69 * BlurGradient.radiusScale * gradient.blurStrength(progress: envelope.value)
                    let dim = dimming.advance(to: ClosingDimming(angle: 90, startAngle: start, maximum: 0.2), dt: 1 / Double(fps))
                    check(blur <= 8 + 1e-9, "fast close from \(start)° overshoots 8 pt at \(fps) Hz")
                    check(dim.strength == 0, "fast close darkens at 90°")
                }
                if start >= 130 {
                    check(abs(69 * BlurGradient.radiusScale * gradient.blurStrength(progress: envelope.value) - 8) < 0.001,
                          "blur must settle at 8 pt at 90°")
                }
            }
        }
        for start in [90.0, 60, 31, 20] {
            check(radius(start, start: start) == 0, "a new gesture starts clear")
            check(radius(start - 1, start: start) <= 2, "first degree of a low-angle gesture stays gentle")
        }
        if failures > 0 { print("FAIL: \(failures) closing-angle checks"); exit(1) }
        print("PASS: angle-bounded blur, gradual growth and delayed dimming at 30/60/120 Hz")
    }
}
