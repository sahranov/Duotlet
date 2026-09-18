import Foundation

/// Async work belongs to one visible gesture. Sleep, display changes and
/// finishing a gesture invalidate it. A wake starts a separate presentation.
struct EffectSession {
    private(set) var generation: UInt64 = 0

    mutating func invalidate() { generation &+= 1 }

    func accepts(_ generation: UInt64) -> Bool { self.generation == generation }

    static func shouldAbandonFrame(after interval: TimeInterval) -> Bool {
        // A stalled display callback must not replay the rest of its animation
        // after the desktop is already visible again.
        interval > 0.25
    }
}

/// A cached frame can bridge wake only immediately, at the current lid angle.
/// No elapsed animation or pre-sleep angle is retained for later playback.
struct WakePresentation {
    struct State {
        let startAngle: Double
        let angle: Double
    }

    private(set) var startAngle: Double?
    private var resumedAt: TimeInterval?
    static let deadline: TimeInterval = 0.2

    mutating func remember(startAngle: Double) {
        guard self.startAngle == nil else { return }
        self.startAngle = startAngle
    }

    mutating func resume(at time: TimeInterval) {
        guard startAngle != nil, resumedAt == nil else { return }
        resumedAt = time
    }

    mutating func take(angle: Double, at time: TimeInterval, screenReady: Bool,
                       surfaceRetained: Bool = false) -> State? {
        guard let startAngle, let resumedAt else { return nil }
        guard (surfaceRetained || time - resumedAt <= Self.deadline), angle < startAngle - 0.6 else {
            clear()
            return nil
        }
        guard screenReady else { return nil }
        clear()
        return State(startAngle: startAngle, angle: angle)
    }

    mutating func clear() { self = Self() }
}
