import Foundation

/// Smooth the final taper, including sensor steps, direction changes and
/// release. Keeping this state in the overlay avoids resetting the visible
/// shape when the controller switches between opening and closing policies.
struct PerspectiveMotion {
    private var inset = CriticallyDampedSpring()
    private var releaseOrigin: (value: Double, velocity: Double)?

    init() { inset.frequency = 9 }

    var isFlat: Bool { abs(inset.value) < 0.0001 && abs(inset.velocity) < 0.001 }

    mutating func beginRelease() { releaseOrigin = nil }

    mutating func reset(to margin: Double = 0) {
        inset.reset(to: margin)
        releaseOrigin = nil
    }

    mutating func advance(to corners: [CGPoint], screenSize: CGSize, dt: Double,
                          release: EffectRelease? = nil) -> [CGPoint] {
        guard screenSize.width > 0 else { return corners }
        if let release {
            if releaseOrigin == nil { releaseOrigin = (inset.value, inset.velocity) }
            let origin = releaseOrigin!
            let t = release.returnProgress
            let t2 = t * t, t3 = t2 * t, t4 = t3 * t, t5 = t4 * t
            // Quintic Hermite return from the presented position and velocity.
            // Do not feed a second spring: its tail outlives the opacity fade.
            inset.value = origin.value * release.strength
                + origin.velocity * EffectRelease.returnDuration * (t - 6*t3 + 8*t4 - 3*t5)
            inset.velocity = origin.value * (-30*t2 + 60*t3 - 30*t4) / EffectRelease.returnDuration
                + origin.velocity * (1 - 18*t2 + 32*t3 - 15*t4)
        } else {
            releaseOrigin = nil
            inset.advance(to: corners[3].x / screenSize.width, dt: dt)
        }
        let margin = min(max(inset.value, 0), 0.125) * screenSize.width
        var presented = corners
        presented[2].x = screenSize.width - margin
        presented[3].x = margin
        return presented
    }
}
