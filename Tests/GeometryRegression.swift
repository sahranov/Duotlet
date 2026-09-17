import AppKit

@main
struct GeometryRegression {
    static func main() {
        let size = CGSize(width: 1512, height: 982)
        var failures = 0
        var maximumHeight = 0.0
        var maximumMagnification = 0.0
        for start in [30.0, 81.0, 130.0] {
            for distance in [1.0, 2.7, 6.0] {
                for recession in [0.0, 0.5, 1.0, 3.0] {
                    var previous: [CGPoint]?
                    for step in 0...Int(start * 10) {
                        let points = DepthGeometry().corners(startAngle: start,
                            currentAngle: start - Double(step) / 10,
                            viewingDistanceRatio: distance, recession: recession, screenSize: size)
                        let h = points[2].y / size.height
                        let w = (points[2].x - points[3].x) / size.width
                        if abs(h - 1) > 1e-9 || w < 0.76 - 1e-9 { failures += 1 }
                        var previousInset = points[3].x
                        for frame in 0...10 {
                            let released = DepthGeometry().corners(startAngle: start,
                                currentAngle: start - Double(step) / 10,
                                viewingDistanceRatio: distance, recession: recession,
                                screenSize: size, strength: 1 - Double(frame) / 10)
                            if released[3].x > previousInset + 1e-9 { failures += 1 }
                            previousInset = released[3].x
                        }
                        maximumHeight = max(maximumHeight, h)
                        maximumMagnification = max(maximumMagnification, h / w)
                        if !h.isFinite || !w.isFinite || h <= 0 || h > 1.15000001 || w < 0.74999999 || w > 1.00000001 { failures += 1 }
                        if points[0] != .zero || points[1] != CGPoint(x: size.width, y: 0) { failures += 1 }
                        if step == 0 || recession == 0 {
                            if abs(h - 1) > 1e-9 || abs(w - 1) > 1e-9 { failures += 1 }
                        }
                        if let previous {
                            if abs(points[2].y - previous[2].y) > size.height * 0.01 || abs(points[2].x - previous[2].x) > size.width * 0.01 {
                                if failures < 3 { print("continuity: start=\(start) distance=\(distance) lean=\(recession) step=\(step) delta=\(points[2].y - previous[2].y)") }
                                failures += 1
                            }
                        }
                        previous = points
                    }
                }
            }
        }
        print("\(failures == 0 ? "PASS" : "FAIL"): \(failures) violations; max height \(maximumHeight)x, max hinge stretch \(maximumMagnification)x")
        if failures > 0 { exit(1) }
    }
}
