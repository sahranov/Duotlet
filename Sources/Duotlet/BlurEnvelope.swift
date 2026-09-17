import Foundation

/// Keep blur continuous when a lid gesture reverses or crosses the hold boundary.
struct BlurEnvelope {
    private(set) var value = 0.0

    mutating func reset() { value = 0 }

    mutating func restore(_ progress: Double) { value = min(max(progress, 0), 1) }

    mutating func advance(target: Double, dt: Double) {
        let target = min(max(target, 0), 1)
        let amount = 1 - exp(-min(max(dt, 0), 0.05) / 0.12)
        value += (target - value) * amount
    }
}
