import Foundation

@main struct OpeningReleaseRegression {
    static func main() {
        var failures = 0
        func check(_ ok: Bool, _ label: String) {
            if !ok { print("FAIL: \(label)"); failures += 1 }
        }
        for fps in [30, 60, 120] {
            let dt = 1 / Double(fps)
            var motion = OpeningRelease(angle: 13.23, startAngle: 120)
            var release = EffectRelease(elapsed: 0)
            var previous = 1.0
            for frame in 1...(fps * 3) {
                let angle = 13.23 + floor(Double(frame) / Double(fps) * 10) * 1.5
                release = motion.advance(angle: angle, dt: dt)
                check(release.strength <= previous + 1e-10, "opening must not deepen the effect")
                previous = release.strength
            }
            check(release.strength > 0.3 && release.opacity == 1,
                  "slow opening loses animation before the lid reaches a usable position")
            // Stop anywhere, including only ten degrees above closed. Finishing
            // must start promptly, and complete without a residual overlay.
            motion = OpeningRelease(angle: 0, startAngle: 120)
            for frame in 1...fps {
                release = motion.advance(angle: Double(frame) * 10 / Double(fps), dt: dt)
            }
            let atStop = release.strength
            for _ in 0..<Int(Double(fps) * 0.4) { release = motion.advance(angle: 10, dt: dt) }
            check(release.strength < atStop - 0.1, "stopping adds a long pause before clearing")
            for _ in 0..<(fps * 2) { release = motion.advance(angle: 10, dt: dt) }
            check(release.isFinished && release.opacity == 0, "partial opening at rest never clears")

            motion = OpeningRelease(angle: 10, startAngle: 120)
            for _ in 0..<Int(Double(fps) * 0.1) { release = motion.advance(angle: 120, dt: dt) }
            check(release.strength > 0.9, "fast opening snaps to the clear desktop")
            for _ in 0..<(fps * 2) { release = motion.advance(angle: 120, dt: dt) }
            check(release.isFinished, "fast opening does not finish")
        }
        let size = CGSize(width: 1512, height: 982)
        let target = DepthGeometry().corners(startAngle: 120, currentAngle: 40,
            viewingDistanceRatio: 6, recession: 0.5, screenSize: size)
        var borders = PerspectiveMotion()
        var previousInset = 0.0
        for _ in 0..<30 {
            previousInset = borders.advance(to: target, screenSize: size, dt: 1 / 60)[3].x
        }
        let atOpening = previousInset
        borders.beginRelease()
        var opening = OpeningRelease(angle: 40, startAngle: 120)
        var maximumInset = atOpening
        for frame in 1...180 {
            let release = opening.advance(angle: 40 + Double(frame) / 6, dt: 1 / 60)
            let inset = borders.advance(to: target, screenSize: size, dt: 1 / 60, release: release)[3].x
            maximumInset = max(maximumInset, inset)
            check(abs(inset - previousInset) < 2, "opening geometry jumps between frames")
            previousInset = inset
        }
        check(maximumInset - atOpening < 3, "closing momentum persists into slow opening")
        print(failures == 0 ? "PASS: opening follows lid travel, stops clear promptly, fast movements stay smooth" : "FAIL: \(failures) opening checks")
        if failures > 0 { exit(1) }
    }
}
