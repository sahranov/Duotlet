import Foundation

@main struct BlurEnvelopeRegression {
    static func main() {
        var envelope = BlurEnvelope()
        var policy = AdaptiveLidPolicy()
        var failures = 0
        var time = 0.0
        for angle in [90.0, 65, 49, 42, 55, 48, 58, 45, 60, 49, 40, 55] {
            time += 1.0 / 60
            let active = policy.update(angle: angle, at: time)
            let span = max(policy.startAngle - 50, 1)
            let target = active ? min(max((policy.startAngle - angle) / span, 0), 1) : 0
            let before = envelope.value
            envelope.advance(target: target, dt: 1.0 / 60)
            if abs(envelope.value - before) > 0.14 { failures += 1 }
            if !(0...1).contains(envelope.value) { failures += 1 }
        }
        for _ in 0..<120 { envelope.advance(target: 0, dt: 1.0 / 60) }
        if envelope.value > 0.0001 { failures += 1 }
        envelope.reset()
        if envelope.value != 0 { failures += 1 }
        for step in 0...60 {
            let target = Double(step) / 60
            envelope.advance(target: target, dt: 1.0 / 60)
            if envelope.value > target + 1e-9 { failures += 1 }
        }
        envelope.reset()
        envelope.advance(target: 1, dt: 1.0 / 60)
        if envelope.value > 0.14 { failures += 1 }
        print(failures == 0 ? "PASS: bounded blur changes across reversals and 50 degrees; returns clear" : "FAIL: \(failures)")
        if failures > 0 { exit(1) }
    }
}
