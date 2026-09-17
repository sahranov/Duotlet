import Foundation

/// Additional whole-screen darkness in the final twenty degrees of travel.
/// Kept separate from the user's fixed 20% decorative dimming.
struct ClosingDimming {
    static func blackout(angle: Double) -> Double {
        let t = min(max((20 - angle) / 20, 0), 1)
        return t * t * (3 - 2 * t)
    }

    let strength: Double
    let maximum: Double
    let hingeFloor: Double

    init(angle: Double, progress: Double, maximum: Double, releaseStrength: Double = 1) {
        let black = Self.blackout(angle: angle) * min(max(releaseStrength, 0), 1)
        let base = BlurGradient().dimStrength(progress: progress)
        strength = base + (1 - base) * black
        self.maximum = maximum + (1 - maximum) * black
        hingeFloor = 0.2 + 0.8 * black
    }
}
