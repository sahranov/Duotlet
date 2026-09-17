import Foundation

/// A shallow taper, without rotating or stretching the desktop.
struct DepthGeometry {
    func corners(
        startAngle: Double,
        currentAngle: Double,
        viewingDistanceRatio: Double,
        recession: Double,
        screenSize: CGSize,
        strength: Double = 1
    ) -> [CGPoint] {
        func smooth(_ value: Double) -> Double {
            let t = min(max(value, 0), 1)
            return t * t * (3 - 2 * t)
        }
        let width = Double(screenSize.width)
        let height = Double(screenSize.height)
        let travel = max(startAngle - currentAngle, 0)
        // Build the closing wedges over a real sweep of the lid. Reaching
        // full taper in five degrees made it look like a single kick.
        let onset = smooth(travel / 24)
        let perspective = min(max((6 - viewingDistanceRatio) / 5, 0), 1)
        let lean = min(max(recession, 0), 1)
        let maximumInset = 0.09 + 0.03 * perspective
        let inset = width * maximumInset * lean
            * onset * min(max(strength, 0), 1)
        return [CGPoint(x: 0, y: 0), CGPoint(x: width, y: 0),
                CGPoint(x: width - inset, y: height), CGPoint(x: inset, y: height)]
    }
}
