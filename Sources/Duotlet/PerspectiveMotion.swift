import Foundation

/// Smooth the final taper, including sensor steps, direction changes and
/// release. Keeping this state in the overlay avoids resetting the visible
/// shape when the controller switches between opening and closing policies.
struct PerspectiveMotion {
    private var inset = CriticallyDampedSpring()
    private var releaseOrigin: (value: Double, velocity: Double)?

    // The lid can reach its target before capture supplies the first picture.
    // Ease the visible borders in at their own pace even for a full-angle step;
    // the old 9 rad/s response moved them 15 pt in the first 100 ms.
    init() { inset.frequency = 2.5 }

    var isFlat: Bool { abs(inset.value) < 0.0001 && abs(inset.velocity) < 0.001 }

    mutating func beginRelease() { releaseOrigin = nil }

    mutating func prepareForWake(margin: Double, preservingPresentation: Bool) {
        if preservingPresentation {
            // The retained surface already displays this inset. Preserve its
            // position, but do not carry pre-sleep closing momentum into wake.
            inset.velocity = 0
            releaseOrigin = nil
        } else {
            reset(to: margin)
        }
    }

    mutating func reset(to margin: Double = 0) {
        inset.reset(to: margin)
        releaseOrigin = nil
    }

    mutating func advance(to corners: [CGPoint], screenSize: CGSize, dt: Double,
                          release: EffectRelease? = nil) -> [CGPoint] {
        guard screenSize.width > 0 else { return corners }
        if let release {
            if releaseOrigin == nil {
                // Reach the release instant from the previous display frame.
                // Freezing that frame used to insert a one-frame stop before
                // the return, which is visible when closing motion is slower.
                inset.advance(to: corners[3].x / screenSize.width,
                              dt: max(dt - release.motionElapsed, 0))
                releaseOrigin = (inset.value, inset.velocity)
            }
            let origin = releaseOrigin!
            // Brake closing momentum in real time. Using the lid-driven phase
            // here would stretch that momentum across a slow opening, making
            // the borders keep growing while the user opens the screen.
            let coast = 0.04 * (1 - exp(-release.motionElapsed / 0.04))
            let previous = inset.value
            inset.value = max(origin.value + origin.velocity * coast, 0) * release.strength
            if dt > 0 { inset.velocity = (inset.value - previous) / dt }
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
