import Foundation

@main struct ClosingResponseRegression {
    static func main() {
        var failures = 0
        func check(_ ok: Bool, _ message: String) {
            if !ok { print("FAIL: \(message)"); failures += 1 }
        }
        var uneven = AdaptiveLidPolicy()
        _ = uneven.update(angle: 100, at: 0)
        check(!uneven.update(angle: 99.6, at: 0.1), "first slow step stays clear")
        check(!uneven.update(angle: 98.8, at: 0.2),
              "6°/s average movement must not trigger on an uneven 8°/s sensor step")
        // Slow adjustments must stay clear even when their total travel is
        // large, including quantized 10 Hz readings at different poll rates.
        for fps in [30, 60, 120] {
            var jittered = AdaptiveLidPolicy()
            _ = jittered.update(angle: 100, at: 0)
            var jitterActivations = 0
            for frame in 1...(fps * 4) {
                let tick = max(0, frame * 10 / fps - 10)
                let travel = Double(tick / 2) * 1.2 + (tick % 2 == 1 ? 0.4 : 0)
                if jittered.update(angle: 100 - travel, at: Double(frame) / Double(fps)) {
                    jitterActivations += 1
                }
            }
            check(jitterActivations == 0, "uneven 6°/s sensor movement after a rest activated at \(fps) Hz")
            for speed in [2.0, 4, 6] {
                for start in [40.0, 90, 130] {
                    var slow = AdaptiveLidPolicy()
                    _ = slow.update(angle: start, at: 0)
                    var activations = 0
                    for frame in 1...(fps * 3) {
                        let angle = start - Double(frame * 10 / fps) * speed / 10
                        if slow.update(angle: angle, at: Double(frame) / Double(fps)) { activations += 1 }
                    }
                    check(activations == 0, "\(speed)°/s adjustment from \(start)° activated at \(fps) Hz")
                    let last = start - speed * 3
                    check(!slow.update(angle: last - 3, at: 3.1), "acceleration must still respect allowance")
                    if last > 21 {
                        check(slow.update(angle: last - 21, at: 3.2), "continued acceleration must start closing")
                        check(abs(slow.startAngle - (last - 20)) <= 1, "slow travel must not accumulate into the next gesture")
                    } else {
                        check(!slow.update(angle: 0, at: 3.2), "less than 20° of remaining travel stays clear")
                    }
                }
            }
        }
        for start in [40.0, 55, 90, 120] {
            var policy = AdaptiveLidPolicy()
            _ = policy.update(angle: start, at: 0)
            check(!policy.update(angle: start - 1, at: 1.0 / 30),
                  "first degree must stay clear from \(start)°")
            check(policy.update(angle: start - 21, at: 2.0 / 30), "continued closing must activate")
            check(policy.startAngle == start - 20, "visual origin must exclude the adjustment")
        }
        // Above-threshold quantized sensor: one degree every 100 ms. There must be no
        // release/restart between updates while the user is still closing.
        var policy = AdaptiveLidPolicy()
        _ = policy.update(angle: 90, at: 0)
        for frame in 1...90 {
            let angle = 89 - Double((frame - 1) / 3)
            check(policy.update(angle: angle, at: Double(frame) / 30) == (angle < 70),
                  "slow close released at frame \(frame)")
            if angle < 70 { check(policy.startAngle == 70, "close changed its origin") }
        }
        check(!policy.update(angle: 60, at: 3.18), "rest above closed zone clears within 180 ms")
        print(failures == 0 ? "PASS: slow adjustments stay clear; deliberate closing starts and stays continuous" : "FAIL: \(failures) closing checks")
        if failures > 0 { exit(1) }
    }
}
