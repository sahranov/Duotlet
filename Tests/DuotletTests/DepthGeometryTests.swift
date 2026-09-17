import AppKit
import Testing
@testable import Duotlet

struct DepthGeometryTests {
    private let size = CGSize(width: 1512, height: 982)

    @Test func closingKeepsProjectionBoundedAndContinuous() {
        for distance in [1.0, 2.7, 6.0] {
            for recession in [0.0, 0.5, 1.0, 3.0] {
                var previous: [CGPoint]?
                for step in 0...810 {
                    let points = DepthGeometry().corners(
                        startAngle: 81, currentAngle: 81 - Double(step) / 10,
                        viewingDistanceRatio: distance, recession: recession, screenSize: size
                    )
                    let topHeight = points[2].y / size.height
                    let topWidth = (points[2].x - points[3].x) / size.width
                    #expect(topHeight.isFinite && topWidth.isFinite)
                    #expect(topHeight > 0 && topHeight <= 1.15 + 1e-9)
                    #expect(topWidth >= 0.75 - 1e-9 && topWidth <= 1 + 1e-9)
                    // Bounds the vertical magnification at the hinge, where
                    // an almost collapsed trapezoid otherwise stretches text.
                    #expect(topHeight / topWidth <= 1.15 / 0.75 + 1e-9)
                    #expect(points[0] == CGPoint(x: 0, y: 0))
                    #expect(points[1] == CGPoint(x: size.width, y: 0))
                    if let previous {
                        #expect(abs(points[2].y - previous[2].y) < size.height * 0.01)
                        #expect(abs(points[2].x - previous[2].x) < size.width * 0.01)
                    }
                    previous = points
                }
            }
        }
    }

    @Test func zeroLeanAndStartAngleKeepOriginalRectangle() {
        let expected = [CGPoint(x: 0, y: 0), CGPoint(x: size.width, y: 0),
                        CGPoint(x: size.width, y: size.height), CGPoint(x: 0, y: size.height)]
        for angle in [0.0, 10, 45, 81] {
            let actual = DepthGeometry().corners(startAngle: 81, currentAngle: angle,
                viewingDistanceRatio: 6, recession: 0, screenSize: size)
            for (a, b) in zip(actual, expected) {
                #expect(abs(a.x - b.x) < 1e-9 && abs(a.y - b.y) < 1e-9)
            }
        }
        let actual = DepthGeometry().corners(startAngle: 81, currentAngle: 81,
            viewingDistanceRatio: 6, recession: 0.5, screenSize: size)
        for (a, b) in zip(actual, expected) {
            #expect(abs(a.x - b.x) < 1e-9 && abs(a.y - b.y) < 1e-9)
        }
    }
}
