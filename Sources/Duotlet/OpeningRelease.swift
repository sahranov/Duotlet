import Foundation

/// The lid controls how far the return has progressed, not a wall-clock timer
/// started while the screen is still nearly shut. A stop completes the return.
struct OpeningRelease {
    private let origin: Double
    private let span: Double
    private var reference: Double
    private var stationaryTime = 0.0
    private var finishing = false
    private var phase = CriticallyDampedSpring()
    private var fadeElapsed = 0.0
    private var motionElapsed = 0.0

    init(angle: Double, startAngle: Double) {
        origin = angle
        span = max(startAngle - angle, 30)
        reference = angle
        phase.frequency = 8
    }

    mutating func advance(angle: Double, dt: Double) -> EffectRelease {
        let dt = min(max(dt, 0), 0.05)
        motionElapsed += dt
        if abs(angle - reference) > 0.35 {
            reference = angle
            stationaryTime = 0
        } else {
            stationaryTime += dt
        }
        if stationaryTime >= AdaptiveLidPolicy.settleDuration { finishing = true }
        let travel = min(max((angle - origin) / span, 0), 1)
        if travel >= 1 { finishing = true }
        let target = finishing ? 1 : max(travel, phase.value)
        let previous = phase.value
        phase.advance(to: target, dt: dt)
        phase.value = min(max(phase.value, previous), 1)
        if finishing && phase.value > 0.999 { phase.reset(to: 1) }
        if phase.value == 1 { fadeElapsed += dt }
        return EffectRelease(elapsed: phase.value * EffectRelease.returnDuration + fadeElapsed,
                             motionElapsed: motionElapsed)
    }
}
