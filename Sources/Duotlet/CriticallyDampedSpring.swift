import Foundation

/// Turns the sensor's 10 Hz steps into a value that changes smoothly at the
/// display refresh rate.
///
/// The exact critically damped solution keeps velocity continuous and gives
/// the same response at 60 Hz, 120 Hz, and after an occasional late frame.
struct CriticallyDampedSpring {
    var value: Double
    var velocity: Double = 0

    /// Radians per second. Higher follows the target faster and smooths less.
    var frequency: Double = 16

    init(value: Double = 0) {
        self.value = value
    }

    mutating func advance(to target: Double, dt: Double) {
        guard dt > 0, dt.isFinite, target.isFinite, frequency > 0 else { return }
        let displacement = value - target
        let impulse = velocity + frequency * displacement
        let decay = exp(-frequency * dt)
        value = target + (displacement + impulse * dt) * decay
        velocity = (velocity - frequency * impulse * dt) * decay
    }

    mutating func reset(to newValue: Double) {
        value = newValue
        velocity = 0
    }
}
