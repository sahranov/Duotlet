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
        check(!sample(89), "first degree is an adjustment")
        check(!sample(70), "20 degrees stays clear")
        check(sample(69), "closing beyond 20 degrees activates")
        check(policy.startAngle == 70, "effect begins after the adjustment allowance")
        check(sample(69, 0.1), "brief pause")
        check(!sample(69, 0.06), "settles after a real pause")
        check(!sample(71), "opening stays clear")
        check(!sample(90), "opening continues clear")
        check(!sample(110), "wide opening stays clear")
        check(!sample(90), "20-degree reversal stays clear")
        check(!sample(90, 0.7), "opening settles")
        check(!sample(89), "first change after a long rest must establish fresh speed")
        check(!sample(88), "confirmed speed still needs 20 degrees")
        check(!sample(70), "new adjustment stays clear")
        check(!sample(69), "new adjustment reaches 20 degrees")
        check(sample(68), "closing beyond new allowance starts")
        check(policy.startAngle == 69, "new closing origin excludes unconfirmed travel")
        check(sample(51), "close to 51")
        check(!sample(51, 0.7), "51 is a working position")
        check(!sample(50), "first movement after a long rest remains unconfirmed")
        check(!sample(49), "allowance also applies below 50")
        check(sample(24), "continued close beyond allowance activates below 50")
        check(sample(24, 3), "below 50 does not time out")
        check(sample(20), "below 50")
        check(!sample(49), "opening below 50 releases")
        check(!sample(65), "opening releases existing run")
        check(!sample(65, 0.7), "opening settles above 50")
        for i in 0..<60 { check(!sample(65 + (i % 2 == 0 ? 0.12 : -0.12)), "jitter stays clear") }
        policy.reset()
        check(!sample(90), "reset open")
        policy.reset()
        check(!sample(40), "startup below boundary stays clear")
        check(!sample(39), "adjustment below boundary stays clear")
        check(sample(14), "closing below boundary activates after allowance")
        print(failures == 0 ? "PASS: closing, no effect on opening to 110, settling, 50-degree boundary, jitter, reset" : "FAIL: \(failures)")
        if failures > 0 { exit(1) }
    }
}
