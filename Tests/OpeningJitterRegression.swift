import Foundation
@main struct OpeningJitterRegression {
 static func main() {
    var policy = AdaptiveLidPolicy()
    var time = 0.0
    func sample(_ angle: Double, delay: Double = 1 / 30) -> Bool {
        time += delay
        return policy.update(angle: angle, at: time)
    }
    _ = sample(90)
    precondition(sample(40))
    precondition(!sample(41))
    for angle in [42.0, 41.2, 43, 42.2, 44, 43.2, 45] {
        if sample(angle) { print("FAIL: opening sensor bounce restarts the closing effect at \(angle)°"); exit(1) }
    }
    precondition(!sample(42), "a short closing reversal stays clear")
    precondition(sample(19), "closing beyond the allowance still activates")
    print("PASS: opening jitter cannot interrupt the return; deliberate reversal still works")
 }
}
