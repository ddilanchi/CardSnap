import Vision
import CoreImage

enum QualityLevel { case red, yellow, green }

struct DetectionResult {
    let topLeft, topRight, bottomLeft, bottomRight: CGPoint
    let quality: Double
    let level: QualityLevel
}

// MARK: - One Euro Filter

private class OneEuroFilter {
    private let minCutoff: Double
    private let beta: Double
    private let dCutoff: Double
    private var xPrev: Double?
    private var dxPrev = 0.0

    init(minCutoff: Double = 0.8, beta: Double = 0.4, dCutoff: Double = 1.0) {
        self.minCutoff = minCutoff; self.beta = beta; self.dCutoff = dCutoff
    }

    func filter(_ x: Double, dt: Double) -> Double {
        let ad = alpha(dt: dt, cutoff: dCutoff)
        let dx = xPrev.map { (x - $0) / dt } ?? 0.0
        let dxHat = ad * dx + (1 - ad) * dxPrev
        let a = alpha(dt: dt, cutoff: minCutoff + beta * abs(dxHat))
        let xHat = xPrev.map { a * x + (1 - a) * $0 } ?? x
        xPrev = xHat; dxPrev = dxHat
        return xHat
    }

    func reset() { xPrev = nil; dxPrev = 0 }
    private func alpha(dt: Double, cutoff: Double) -> Double { 1.0 / (1.0 + 1.0 / (2.0 * .pi * cutoff * dt)) }
}

// MARK: - CardDetector

class CardDetector {
    private var previous: [CGPoint]?   // previous smoothed corners for stability score
    private var greenFrames = 0
    private let captureThreshold = 18

    // 8 filters: x+y per corner [tL, tR, bR, bL]
    private let filters: [[OneEuroFilter]] = (0..<4).map { _ in [OneEuroFilter(), OneEuroFilter()] }
    private let dt = 1.0 / 30.0

    func detect(in pixelBuffer: CVPixelBuffer) -> DetectionResult? {
        // VNDetectDocumentSegmentationRequest: ML-based, consistent corners, designed for this
        let request = VNDetectDocumentSegmentationRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
        try? handler.perform([request])

        guard let obs = request.results?.first else {
            previous = nil
            greenFrames = 0
            filters.forEach { $0.forEach { $0.reset() } }
            return nil
        }

        // Normalize corner order so they never swap between frames
        let corners = normalizeCorners([obs.topLeft, obs.topRight, obs.bottomRight, obs.bottomLeft])

        let quality = score(obs, corners: corners)
        let level: QualityLevel = quality >= 0.72 ? .green : quality >= 0.40 ? .yellow : .red
        greenFrames = level == .green ? greenFrames + 1 : 0

        // Apply One Euro Filter
        let smooth = corners.enumerated().map { i, pt in
            CGPoint(
                x: filters[i][0].filter(Double(pt.x), dt: dt),
                y: filters[i][1].filter(Double(pt.y), dt: dt)
            )
        }
        previous = smooth

        return DetectionResult(
            topLeft: smooth[0], topRight: smooth[1],
            bottomLeft: smooth[3], bottomRight: smooth[2],
            quality: quality, level: level
        )
    }

    var isReadyToCapture: Bool { greenFrames >= captureThreshold }

    func resetStability() {
        greenFrames = 0
        filters.forEach { $0.forEach { $0.reset() } }
        previous = nil
    }

    // MARK: - Corner normalization
    // Sort corners by angle from centroid → always [topLeft, topRight, bottomRight, bottomLeft]
    // This prevents Vision reassigning which corner is "topLeft" between frames.
    private func normalizeCorners(_ pts: [CGPoint]) -> [CGPoint] {
        let cx = pts.map(\.x).reduce(0, +) / CGFloat(pts.count)
        let cy = pts.map(\.y).reduce(0, +) / CGFloat(pts.count)
        let sorted = pts.sorted { a, b in
            atan2(Double(a.y - cy), Double(a.x - cx)) < atan2(Double(b.y - cy), Double(b.x - cx))
        }
        // In Vision space (y-up): atan2 ascending = [bL~-143°, bR~-37°, tR~37°, tL~143°]
        // Remap to stable order: [topLeft, topRight, bottomRight, bottomLeft]
        guard sorted.count == 4 else { return pts }
        return [sorted[3], sorted[2], sorted[1], sorted[0]]
    }

    // MARK: - Quality Scoring

    private func score(_ obs: VNRectangleObservation, corners: [CGPoint]) -> Double {
        Double(obs.confidence) * 0.4
        + min(area(corners) / 0.20, 1.0) * 0.35
        + stability(corners) * 0.25
    }

    private func area(_ pts: [CGPoint]) -> Double {
        var a = 0.0
        for i in 0..<pts.count {
            let j = (i + 1) % pts.count
            a += Double(pts[i].x * pts[j].y) - Double(pts[j].x * pts[i].y)
        }
        return abs(a) / 2.0
    }

    private func stability(_ corners: [CGPoint]) -> Double {
        guard let prev = previous, prev.count == corners.count else { return 0.5 }
        let d = zip(prev, corners).map { dist($0, $1) }.reduce(0, +) / Double(corners.count)
        return max(0, 1.0 - d / 0.05)
    }

    private func dist(_ a: CGPoint, _ b: CGPoint) -> Double {
        hypot(Double(a.x - b.x), Double(a.y - b.y))
    }
}
