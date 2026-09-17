import Foundation

/// Closing starts a run; opening or a rest above the closed zone releases it.
struct AdaptiveLidPolicy {
    static let closedZone = 50.0
    static let settleDuration = 0.15
    private static let stillTolerance = 0.35
    private static let motionDistance = 0.6
    private static let adjustmentAllowance = 20.0

    private(set) var isActive = false
    private(set) var startAngle = 90.0
    private var reference: Double?
    private var movedAt = 0.0
    private var peak = 0.0
    private var low = 180.0

    mutating func reset() { self = Self() }

    mutating func update(angle: Double, at now: TimeInterval) -> Bool {
        guard let reference else {
            self.reference = angle
            movedAt = now
            peak = angle
            low = angle
            startAngle = max(angle, Self.closedZone + 20)
            // Launching or waking with a partly open lid is not a close.
            isActive = false
            return isActive
        }
        if abs(angle - reference) > Self.stillTolerance {
            self.reference = angle
            movedAt = now
        }
        let settled = now - movedAt >= Self.settleDuration
        peak = max(peak, angle)
        low = min(low, angle)

        // Opening always releases, including below the closed-zone boundary.
        if angle - low >= Self.motionDistance {
            isActive = false
            peak = angle
            low = angle
            return false
        }

        if isActive {
            if angle > Self.closedZone && settled {
                isActive = false
                peak = angle
                low = angle
            }
        } else if settled {
            // Discard the old peak, so another close can start from this rest.
            peak = angle
            low = angle
        } else if (angle <= Self.closedZone && peak - angle >= Self.motionDistance)
                    || peak - angle > Self.adjustmentAllowance {
            startAngle = max(angle <= Self.closedZone ? peak : peak - Self.adjustmentAllowance,
                             Self.closedZone + 1)
            low = angle
            isActive = true
        }
        return isActive
    }
}
