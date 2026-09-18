import Foundation

@main struct LidAdjustmentRegression {
    static func main() {
        var failures = 0
        func check(_ value: Bool, _ message: String) {
            if !value { print("FAIL: \(message)"); failures += 1 }
        }
        for fps in [30, 60, 120] {
            for start in [40.0, 60, 90, 110, 130] {
                for speed in [10.0, 30, 100] {
                    var policy = AdaptiveLidPolicy()
                    _ = policy.update(angle: start, at: 0)
                    let frames = Int(ceil(20 / speed * Double(fps)))
                    var activations = 0
                    for frame in 1...frames {
                        let travel = min(Double(frame) * speed / Double(fps), 20)
                        if policy.update(angle: start - travel, at: Double(frame) / Double(fps)) {
                            activations += 1
                        }
                    }
                    check(activations == 0, "20° adjustment from \(start)° at \(speed)°/s activated at \(fps) Hz")
                    check(policy.update(angle: start - 21, at: Double(frames) / Double(fps) + 0.01),
                          "continued close beyond 20° must activate")
                    check(policy.startAngle == start - 20,
                          "effect must exclude the ignored 20° from its visual origin")
                }
            }
        }
        var repeated = AdaptiveLidPolicy()
        _ = repeated.update(angle: 130, at: 0)
        for cycle in 0..<3 {
            let origin = 130 - Double(cycle) * 20
            let time = Double(cycle)
            check(!repeated.update(angle: origin - 20, at: time + 0.1), "short adjustment stays clear")
            check(!repeated.update(angle: origin - 20, at: time + 0.5), "rest stays clear")
        }
        check(!repeated.update(angle: 90, at: 3.1), "opening stays clear")
        check(!repeated.update(angle: 70, at: 3.2), "20° reversal stays clear")
        check(repeated.update(angle: 69, at: 3.3), "continued reversal activates")
        check(!repeated.update(angle: 69, at: 3.5), "rest releases above closed zone")
        check(!repeated.update(angle: 49, at: 3.6), "new rest becomes the adjustment origin")
        check(repeated.update(angle: 48, at: 3.7), "continued close from the new rest activates")
        if failures > 0 { print("FAIL: \(failures) adjustment checks"); exit(1) }
        print("PASS: 20° lid adjustments stay clear at 30/60/120 Hz")
    }
}
