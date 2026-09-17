import Foundation

@main struct EffectReleaseRegression {
    static func main() {
        var failures = 0
        for fps in [30, 60, 120] {
            var blur = BlurEnvelope()
            let gradient = BlurGradient()
            let dt = 1 / Double(fps)
            for _ in 0..<fps * 3 { blur.advance(target: 1, dt: dt) }
            var previousLoss = 1.0
            var lastVisibleLoss = 0.0
            var residualWithoutFade = 0.0
            var previousOpacity = 1.0
            var maximumOpacityStep = 0.0
            let frames = Int(ceil(EffectRelease.duration * Double(fps)))
            for frame in 0...frames {
                let release = EffectRelease(elapsed: Double(frame) * dt)
                maximumOpacityStep = max(maximumOpacityStep, previousOpacity - release.opacity)
                previousOpacity = release.opacity
                blur.restore(release.strength)
                let residual = 1 - pow(1 - gradient.dimStrength(progress: blur.value), 2.2)
                let loss = release.opacity * residual
                if loss > previousLoss + 1e-9 || !(0...1).contains(loss) { failures += 1 }
                if !release.isFinished { lastVisibleLoss = loss }
                if release.isFinished {
                    residualWithoutFade = residual
                    if release.opacity != 0 || loss != 0 { failures += 1 }
                    // At maximum dim, removing the window must change the
                    // visible brightness by much less than one 8-bit level.
                    if lastVisibleLoss >= 0.5 / 255 { failures += 1 }
                }
                previousLoss = loss
            }
            // Opacity changes only after the image is sharp, undimmed and
            // aligned. Changing it then contributes no sharp-detail jump.
            for frame in 0...frames {
                let release = EffectRelease(elapsed: Double(frame) * dt)
                if release.opacity < 1 && release.strength != 0 { failures += 1 }
            }
            print("\(fps) Hz: opacity step after full alignment \(maximumOpacityStep)")
            print("\(fps) Hz: last visible brightness loss \(lastVisibleLoss); unfaded blur tail \(residualWithoutFade)")
        }
        print(failures == 0 ? "PASS: release is monotonic and ends fully transparent without a final brightness step" : "FAIL: \(failures) release checks")
        if failures > 0 { exit(1) }
    }
}
