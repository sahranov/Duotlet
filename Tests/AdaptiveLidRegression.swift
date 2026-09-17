import Foundation

@main struct AdaptiveLidRegression {
    static func main() {
        var policy = AdaptiveLidPolicy()
        var time = 0.0
        var failures = 0
        func sample(_ angle: Double, _ delay: Double = 0.05) -> Bool {
            time += delay
            return policy.update(angle: angle, at: time)
        }
        func check(_ value: Bool, _ label: String) {
            if !value { print("FAIL: \(label)"); failures += 1 }
        }
        check(!sample(90), "initial rest")
        check(!sample(89), "small adjustment stays clear")
        check(!sample(70), "20 degree adjustment stays clear")
        check(sample(69), "closing beyond 20 degrees begins")
        check(policy.startAngle == 70, "effect begins at dead zone boundary")
        check(sample(69, 0.1), "brief pause")
        check(!sample(69, 0.06), "settles after 0.15 seconds")
        check(!sample(71), "opening stays clear")
        check(!sample(90), "opening continues clear")
        check(!sample(110), "wide opening stays clear")
        check(sample(85), "reversal does not interrupt run")
        check(!sample(85, 0.41), "opening settles")
        check(!sample(84), "adjustment from new rest")
        check(!sample(65), "new rest has its own 20 degree allowance")
        check(sample(64), "closing from new rest")
        check(policy.startAngle == 65, "new closing origin")
        check(sample(51), "close to 51")
        check(!sample(51, 0.41), "51 is a working position")
        check(sample(50), "50 activates persistent effect")
        check(sample(50, 3), "50 does not time out")
        check(sample(20), "below 50")
        check(!sample(49), "opening below 50 releases")
        check(!sample(65), "opening releases existing run")
        check(!sample(65, 0.41), "opening settles above 50")
        for i in 0..<60 { check(!sample(65 + (i % 2 == 0 ? 0.12 : -0.12)), "jitter stays clear") }
        policy.reset()
        check(!sample(90), "reset open")
        policy.reset()
        check(!sample(40), "startup below boundary stays clear")
        check(sample(39), "closing below boundary activates")
        print(failures == 0 ? "PASS: closing, no effect on opening to 110, settling, 50-degree boundary, jitter, reset" : "FAIL: \(failures)")
        if failures > 0 { exit(1) }
    }
}
