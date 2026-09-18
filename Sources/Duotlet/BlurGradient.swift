import Foundation

/// How far out of focus the picture is at a given height, and how much light
/// it has lost. Height is 0 at the hinge edge and 1 at the far edge.
struct BlurGradient {

    static func closingProgress(angle: Double, startAngle: Double) -> Double {
        // Absolute angle limits the effect even after a fast close from a very
        // wide opening. The gesture gate keeps a new low-angle close gentle.
        let angleProgress = min(max((130 - angle) / 100, 0), 1)
        let gestureProgress = min(max((startAngle - angle) / 30, 0), 1)
        return min(angleProgress, gestureProgress)
    }

    // Preserve the existing deep-close radius. The former 70–80° multiplier
    // made a partial close blur more strongly than a nearly closed lid.
    static let radiusScale = 0.35

    /// Exponent on the closing travel for the dimming.
    var dimCurve: Double = 0.7

    /// Dimming at the hinge edge, as a fraction of the dimming at the far
    /// edge.
    var dimHingeFloor: Double = 0.2

    func blurStrength(progress: Double) -> Double {
        let p = min(max(progress, 0), 1)
        // A monotonic quadratic through clear at 130°, the requested 8 pt
        // at 90° (progress 0.4), and the unchanged 24.15 pt ceiling at 30°.
        // Its finite initial slope also keeps short low-angle gestures gentle.
        let anchor = 0.4
        let strengthAt90 = 8.0 / (69 * Self.radiusScale)
        let slope = (strengthAt90 - anchor * anchor) / (anchor - anchor * anchor)
        return p * (slope + (1 - slope) * p)
    }

    func dimStrength(progress: Double) -> Double {
        pow(min(max(progress, 0), 1), dimCurve)
    }
}
