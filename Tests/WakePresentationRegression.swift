import Foundation

@main struct WakePresentationRegression {
    static func main() {
        var failures = 0
        // Both cold capture and warm capture must start the return with one
        // opaque desktop, never a warped copy over the real desktop.
        for delay in [0.0, 0.13, 0.7, 3.0] {
            var reveal = PresentationReveal()
            let ready = 10 + delay
            reveal.reveal(at: ready)
            reveal.restoreForWake(at: ready)
            for frame in 0...4 {
                let t = Double(frame) / 60
                let opacity = reveal.opacity(at: ready + t) * EffectRelease(elapsed: t).opacity
                if opacity != 1 {
                    failures += 1
                    print("FAIL: wake after \(delay)s: warped desktop opacity \(opacity) on frame \(frame)")
                }
            }
        }
        if failures > 0 { exit(1) }
        print("PASS: first wake frame is opaque for cold, warm and delayed captures")
    }
}
