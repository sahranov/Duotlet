import Foundation

/// Gentle darkness below 90 degrees; whole-screen blackout
/// grows more strongly once the absolute lid angle falls below 30 degrees.
struct ClosingDimming {
    static func blackout(angle: Double) -> Double {
        let t = min(max((30 - angle) / 30, 0), 1)
        return t * t * (3 - 2 * t)
    }

    let strength: Double
    let maximum = 1.0
    let hingeFloor: Double

    init(angle: Double, startAngle: Double, maximum: Double) {
        let travel = max(startAngle - angle, 0)
        // Start later than blur, with no sudden slope at 90°. A new close
        // starting below that angle still grows from zero over its travel.
        let angleProgress = min(max((90 - angle) / 60, 0), 1)
        let progress = min(angleProgress, travel / 30)
        let base = min(max(maximum, 0), 1) * progress * progress * (3 - 2 * progress)
        let black = Self.blackout(angle: angle)
        strength = base + (1 - base) * black
        let hingeLoss = 0.2 * base + (1 - 0.2 * base) * black
        hingeFloor = strength > 0 ? hingeLoss / strength : 0.2
    }

    fileprivate init(farLoss: Double, hingeLoss: Double) {
        strength = min(max(farLoss, 0), 1)
        hingeFloor = strength > 0 ? min(max(hingeLoss / strength, 0), 1) : 0.2
    }
}

/// Smooth actual brightness loss, not a blur parameter with a different curve.
/// Keep the presented values across reversals and finish before opacity fades.
struct DimmingMotion {
    private var far = CriticallyDampedSpring()
    private var hinge = CriticallyDampedSpring()
    private var releaseOrigin: (far: Double, hinge: Double)?

    init() {
        far.frequency = 12
        hinge.frequency = 12
    }

    mutating func reset(to dim: ClosingDimming? = nil) {
        far.reset(to: dim?.strength ?? 0)
        hinge.reset(to: (dim?.strength ?? 0) * (dim?.hingeFloor ?? 0))
        releaseOrigin = nil
    }

    mutating func prepareForWake(target: ClosingDimming, preservingPresentation: Bool) {
        if preservingPresentation {
            far.velocity = 0
            hinge.velocity = 0
            releaseOrigin = nil
        } else {
            reset(to: target)
        }
    }

    mutating func beginRelease() { releaseOrigin = nil }

    mutating func advance(to target: ClosingDimming, dt: Double,
                          release: EffectRelease? = nil) -> ClosingDimming {
        if let release {
            if releaseOrigin == nil { releaseOrigin = (far.value, hinge.value) }
            far.reset(to: releaseOrigin!.far * release.strength)
            hinge.reset(to: releaseOrigin!.hinge * release.strength)
        } else {
            releaseOrigin = nil
            far.advance(to: target.strength, dt: dt)
            hinge.advance(to: target.strength * target.hingeFloor, dt: dt)
        }
        return ClosingDimming(farLoss: far.value, hingeLoss: hinge.value)
    }
}
