import Foundation

@main struct WakeEffectRegression {
    static func main() {
        var failures = 0
        func check(_ pass: Bool, _ message: String) {
            if !pass { failures += 1; print("FAIL: \(message)") }
        }
        // The production gesture/session boundary: old async work is invalid
        // after either sleep notification, irrespective of when it completes.
        for delay in [0.0, 0.13, 0.7, 1.6, 2.0, 6.873] {
            var session = EffectSession()
            var policy = AdaptiveLidPolicy()
            _ = policy.update(angle: 90, at: 0)
            check(policy.update(angle: 8, at: 0.1), "closing should activate normally")
            let beforeSleep = session.generation
            session.invalidate()
            policy.reset()
            session.invalidate() // duplicate display/system sleep notification
            check(!session.accepts(beforeSleep), "stale capture accepted after \(delay)s")
            // Resume is observation only, including a nearly closed lid and
            // an opening with backwards quantization noise.
            for (index, angle) in [8.0, 20, 19.2, 35, 55, 80, 90].enumerated() {
                check(!policy.update(angle: angle, at: 10 + delay + Double(index) / 30),
                      "wake opening replayed the old closing gesture")
            }
            check(!policy.update(angle: 85, at: 10 + delay + 7.0 / 30),
                  "a short post-wake adjustment must stay clear")
            check(policy.update(angle: 64, at: 10 + delay + 8.0 / 30),
                  "a genuinely new closing gesture must still work")
            check(session.accepts(session.generation), "fresh work was rejected")
        }
        check(!EffectSession.shouldAbandonFrame(after: 1.0 / 30), "ordinary missed refresh cancelled animation")
        for gap in [0.3, 1.6, 2, 10] {
            check(EffectSession.shouldAbandonFrame(after: gap), "stalled animation replayed after \(gap)s")
        }
        // A full lid sleep needs a continuous wake presentation. It uses a
        // retained image immediately, with geometry from the NEW sensor sample.
        for angle in [8.0, 20, 45, 75] {
            var wake = WakePresentation()
            wake.remember(startAngle: 100)
            wake.remember(startAngle: 20) // duplicate notification cannot replace it
            check(wake.take(angle: angle, at: 5, screenReady: true) == nil,
                  "sleep must not begin a wake presentation")
            wake.resume(at: 10)
            let state = wake.take(angle: angle, at: 10.03, screenReady: true)
            check(state?.angle == angle && state?.startAngle == 100,
                  "wake must present CURRENT geometry from a ready cached frame")
            check(wake.take(angle: angle, at: 10.04, screenReady: true) == nil,
                  "wake must not restart a second time")
        }
        for delay in [0.21, 0.7, 1.6, 6.873] {
            var wake = WakePresentation()
            wake.remember(startAngle: 100)
            wake.resume(at: 10)
            wake.resume(at: 10 + delay) // must not extend the first deadline
            check(wake.take(angle: 40, at: 10 + delay, screenReady: true) == nil,
                  "late wake must never introduce an overlay over the desktop")
            check(wake.startAngle == nil, "expired wake retained for replay")
        }
        var retained = WakePresentation()
        retained.remember(startAngle: 100)
        retained.resume(at: 10)
        check(retained.take(angle: 45, at: 11.5, screenReady: true, surfaceRetained: true)?.angle == 45,
              "retained window must bridge slow OS wake at the current pose")
        var alreadyOpen = WakePresentation()
        alreadyOpen.remember(startAngle: 100)
        alreadyOpen.resume(at: 10)
        check(alreadyOpen.take(angle: 100, at: 10.02, screenReady: true) == nil,
              "already-open lid should expose the normal desktop immediately")
        var waiting = WakePresentation()
        waiting.remember(startAngle: 100)
        waiting.resume(at: 10)
        check(waiting.take(angle: 20, at: 10.02, screenReady: false) == nil, "no display")
        check(waiting.take(angle: 30, at: 10.05, screenReady: true)?.angle == 30,
              "display readiness must use the latest angle")
        if failures > 0 { exit(1) }
        print("PASS: cached wake follows current angle immediately; old work and late replay are rejected")
    }
}
