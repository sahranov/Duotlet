import Foundation

/// Each new release starts at the last presented opacity, including a second
/// opening gesture that interrupts a partially recovered closing gesture.
struct PresentationOpacity {
    private(set) var value = 1.0
    private var releaseOrigin: Double?

    mutating func beginRelease() { releaseOrigin = nil }

    mutating func advance(release: Double?, dt: Double) -> Double {
        if let release {
            if releaseOrigin == nil { releaseOrigin = value }
            value = releaseOrigin! * release
        } else {
            releaseOrigin = nil
            value += (1 - value) * (1 - exp(-dt / 0.12))
        }
        return value
    }
}
