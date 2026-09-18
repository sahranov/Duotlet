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
            // Release opacity falls only after geometry, blur and dimming are
            // neutral. Reclosing can make that identical picture opaque before
            // deforming it; fading it back in would expose two desktop positions.
            value = 1
        }
        return value
    }
}
