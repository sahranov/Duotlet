import Foundation

/// A lid-close effect survives sleep as a small description, not a running
/// capture or an old desktop image. Consume it only once the screen is back.
struct WakeEffectRestoration {
    struct Snapshot {
        let startAngle: Double
        let angle: Double
        let blur: Double
    }

    private(set) var pending: Snapshot?

    mutating func remember(angle: Double, startAngle: Double, blur: Double,
                           closing: Bool, enabled: Bool) {
        guard enabled else { clear(); return }
        guard pending == nil, closing || angle <= 15 else { return }
        let start = max(startAngle, 51)
        pending = Snapshot(startAngle: start, angle: min(angle, start),
            blur: min(max(blur, (start - angle) / max(start - 50, 1)), 1))
    }

    mutating func take(screenReady: Bool, enabled: Bool) -> Snapshot? {
        guard enabled else { clear(); return nil }
        guard screenReady else { return nil }
        defer { clear() }
        return pending
    }

    mutating func clear() { pending = nil }
}
