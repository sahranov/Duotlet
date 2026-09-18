import Foundation

/// Opacity while the first captured picture becomes available.
struct PresentationReveal {
    var duration: Double = 0.07
    private var beganAt: Double?

    init(duration: Double = 0.07) { self.duration = duration }

    mutating func reveal(at time: Double) {
        if beganAt == nil { beganAt = time }
    }

    mutating func revealImmediately() { beganAt = -.greatestFiniteMagnitude }

    func opacity(at time: Double) -> Double {
        guard let beganAt else { return 0 }
        let t = min(max((time - beganAt) / max(duration, 0.001), 0), 1)
        return t * t * (3 - 2 * t)
    }
}
