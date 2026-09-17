import Foundation

@main struct ClosingDimmingRegression {
    static func main() {
        var previous = 0.0
        for step in 0...900 {
            let angle = 90 - Double(step) / 10
            let dim = ClosingDimming(angle: angle, progress: 1, maximum: 0.2)
            let loss = dim.strength * dim.maximum * dim.hingeFloor
            precondition(loss >= previous, "whole screen must darken monotonically")
            precondition(loss <= 1 && loss >= 0)
            previous = loss
        }
        precondition(ClosingDimming.blackout(angle: 20) == 0)
        precondition(ClosingDimming.blackout(angle: 10) == 0.5)
        precondition(ClosingDimming.blackout(angle: 0) == 1)
        let closed = ClosingDimming(angle: 0, progress: 0.9, maximum: 0.2)
        precondition(closed.strength * closed.maximum * closed.hingeFloor == 1)
        let released = ClosingDimming(angle: 0, progress: 0, maximum: 0.2, releaseStrength: 0)
        precondition(released.strength == 0, "opening must release blackout before overlay fades")
        print("PASS: stronger dimming below 20°, full black at 0°, neutral after opening")
    }
}
