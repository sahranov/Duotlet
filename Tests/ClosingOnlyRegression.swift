import Foundation

@main struct ClosingOnlyRegression {
    static func main() {
        var failures = 0
        func check(_ pass: Bool, _ label: String) {
            if !pass { failures += 1; print("FAIL: \(label)") }
        }
        for initial in [20.0, 40, 55, 60, 65] {
            var policy = AdaptiveLidPolicy()
            var activations = 0
            for step in 0...300 {
                let angle = min(initial + Double(step) * 0.3, 130)
                if policy.update(angle: angle, at: Double(step) / 30) { activations += 1 }
            }
            check(activations == 0, "opening from \(initial) degrees activated \(activations) times")
        }
        var policy = AdaptiveLidPolicy()
        _ = policy.update(angle: 100, at: 0)
        check(policy.update(angle: 70, at: 0.1), "closing should activate")
        check(policy.update(angle: 35, at: 0.2), "closing below 50 should stay active")
        check(policy.update(angle: 35, at: 10), "holding a closed lid should preserve the effect")
        check(!policy.update(angle: 36, at: 10.03), "opening must release even below 50")
        for step in 1...120 {
            check(!policy.update(angle: 36 + Double(step) * 0.5, at: 10.03 + Double(step) / 30),
                  "continued opening must not reactivate")
        }
        check(policy.update(angle: 35, at: 15), "closing again must reactivate")
        print(failures == 0 ? "PASS: only closing activates; opening releases and never retriggers" : "FAIL: \(failures) checks")
        if failures > 0 { exit(1) }
    }
}
