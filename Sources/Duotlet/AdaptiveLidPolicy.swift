import Foundation

/// Closing beyond the adjustment allowance starts a run; opening or a rest releases it.
struct AdaptiveLidPolicy {
    static let closedZone = 50.0
    static let settleDuration = 0.15
    private static let stillTolerance = 0.35
    private static let motionDistance = 0.6
    static let adjustmentAllowance = 20.0

    private(set) var isActive = false
    private(set) var startAngle = 90.0
    private var reference: Double?
    private var movedAt = 0.0
    private var peak = 0.0
    private var low = 180.0
    private var isOpening = false
    private var speedSamples: [(time: TimeInterval, angle: Double)] = []
    private(set) var closingVelocity = 0.0

    mutating func reset() { self = Self() }

    mutating func update(angle: Double, at now: TimeInterval, closingSpeed: Double = 8) -> Bool {
        guard let reference else {
            self.reference = angle
            movedAt = now
            peak = angle
            low = angle
            startAngle = angle
            speedSamples = [(now, angle)]
            // Launching or waking with a partly open lid is not a close.
            isActive = false
            return isActive
        }
        // Average signed travel over two 100 ms hardware refresh intervals.
        // A single uneven hardware update
        // must not turn a very slow adjustment into an intentional close.
        speedSamples.append((now, angle))
        let cutoff = now - 0.2
        while speedSamples.count > 2 && speedSamples[1].time <= cutoff {
            speedSamples.removeFirst()
        }
        var baseline = speedSamples[0]
        if baseline.time < cutoff, speedSamples.count > 1 {
            let next = speedSamples[1]
            let span = next.time - baseline.time
            if span > 0 {
                let fraction = (cutoff - baseline.time) / span
                baseline.angle += (next.angle - baseline.angle) * fraction
                baseline.time = cutoff
            }
        }
        let interval = now - baseline.time
        closingVelocity = interval > 0 ? (baseline.angle - angle) / interval : 0
        let isFastClosing = closingVelocity + 1e-9 >= closingSpeed
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
            isOpening = true
            peak = angle
            low = angle
            // Opening travel must not cancel a subsequent deliberate close
            // in the averaging window.
            speedSamples = [(now, angle)]
            closingVelocity = 0
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
            isOpening = false
        } else if peak - angle >= (isOpening ? 2 : Self.motionDistance) {
            if isFastClosing {
                if peak - angle > Self.adjustmentAllowance {
                    // The ignored adjustment must not appear as a sudden jump
                    // in blur, dimming or perspective when the effect starts.
                    startAngle = peak - Self.adjustmentAllowance
                    low = angle
                    isOpening = false
                    isActive = true
                }
            } else {
                // A slow adjustment is a new neutral position, not travel
                // to replay if the user subsequently closes faster.
                peak = angle
                low = angle
            }
        }
        return isActive
    }
}
