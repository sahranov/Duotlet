import Foundation

/// One finite transition to the real desktop. Its last frame contributes
/// exactly zero opacity, even if blur or captured colour has a residual tail.
struct EffectRelease {
    static let returnDuration = 1.1
    static let fadeDuration = 0.3
    static let duration = returnDuration + fadeDuration
    let elapsed: Double
    let progress: Double

    init(elapsed: Double) {
        self.elapsed = max(elapsed, 0)
        progress = min(max(elapsed / Self.duration, 0), 1)
    }

    private func smooth(_ t: Double) -> Double {
        t * t * t * (t * (t * 6 - 15) + 10)
    }

    var returnProgress: Double { min(elapsed / Self.returnDuration, 1) }
    var strength: Double { 1 - smooth(returnProgress) }
    // The real desktop must not show through a still displaced copy. By the
    // time this fade starts, position, blur and dimming are exactly neutral.
    var opacity: Double {
        1 - smooth(min(max((elapsed - Self.returnDuration) / Self.fadeDuration, 0), 1))
    }
    var isFinished: Bool { progress >= 1 }
}
