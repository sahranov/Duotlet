import Foundation

/// Opacity while the first captured picture becomes available.
struct PresentationReveal {
    var duration: Double = 0.07
    private var beganAt: Double?

    init(duration: Double = 0.07) { self.duration = duration }

    mutating func reveal(at time: Double) {
        if beganAt == nil { beganAt = time }
    }

    mutating func restoreForWake(at time: Double) {
        // The restored geometry is already displaced: fading it in would
        // expose two desktop positions. Start the return fully opaque.
        beganAt = time - max(duration, 0.001) - 1
    }

    func opacity(at time: Double) -> Double {
        guard let beganAt else { return 0 }
        let t = min(max((time - beganAt) / max(duration, 0.001), 0), 1)
        return t * t * (3 - 2 * t)
    }
}
