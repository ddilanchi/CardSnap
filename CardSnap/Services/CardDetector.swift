import Vision
import CoreImage

enum QualityLevel { case red, yellow, green }

struct DetectionResult {
    let topLeft, topRight, bottomLeft, bottomRight: CGPoint
    let quality: Double
    let level: QualityLevel
}

// MARK: - One Euro Filter

/// Adaptive low-pass filter: heavy smoothing when still, low lag when moving.
/// Reference: Géry Casiez et al., "1€ Filter", CHI 2012.
private class OneEuroFilter {
    private let minCutoff: Double
    private let beta: Double       // speed coefficient — higher = less lag on fast motion
    private let dCutoff: Double

    private var xPrev: Double?
    private var dxPrev = 0.0

    init(minCutoff: Double = 0.8, beta: Double = 0.4, dCutoff: Double = 1.0) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.dCutoff = dCutoff
    }

    func filter(_ x: Double, dt: Double) -> Double {
        let aDeriv = alpha(dt: dt, cutoff: dCutoff)
        let dx = xPrev.map { (x - $0) / dt } ?? 0.0
        let dxHat = aDeriv * dx + (1 - aDeriv) * dxPrev

        let cutoff = minCutoff + beta * abs(dxHat)
        let aX = alpha(dt: dt, cutoff: cutoff)
        let xHat = xPrev.map { aX * x + (1 - aX) * $0 } ?? x

        xPrev = xHat
        dxPrev = dxHat
        return xHat
    }

    func reset() { xPrev = nil; dxPrev = 0 }

    private func alpha(dt: Double, cutoff: Double) -> Double {
        let tau = 1.0 / (2.0 * .pi * cutoff)
        return 1.0 / (1.0 + tau / dt)
    }
}

// MARK: - CardDetector

class CardDetector {
    private var previous: VNRectangleObservation?
    private var greenFrames = 0
    private let captureThreshold = 18 // ~0.6s at 30fps

    // 8 filters: x + y for each of 4 corners [tL, tR, bL, bR]
    private let filters: [[OneEuroFilter]] = (0..<4).map { _ in
        [OneEuroFilter(), OneEuroFilter()]
    }
    private let dt = 1.0 / 30.0  // 30fps

    func detect(in pixelBuffer: CVPixelBuffer) -> DetectionResult? {
        let request = VNDetectRectanglesRequest()
        // Standard business card is 3.375" × 2.125" = 1.588:1
        request.minimumAspectRatio = 1.45
        request.maximumAspectRatio = 1.75
        request.minimumSize = 0.12
        request.maximumObservations = 1
        request.minimumConfidence = 0.4
        request.quadratureTolerance = 25

        // .right = portrait mode (sensor is landscape; portrait = 90° CW)
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
        try? handler.perform([request])

        guard let obs = request.results?.first else {
            previous = nil
            greenFrames = 0
            filters.forEach { $0.forEach { $0.reset() } }
            return nil
        }

        let quality = score(obs)
        let level: QualityLevel = quality >= 0.78 ? .green : quality >= 0.42 ? .yellow : .red
        greenFrames = level == .green ? greenFrames + 1 : 0
        previous = obs

        // Apply One Euro Filter to each corner
        let raw = [obs.topLeft, obs.topRight, obs.bottomLeft, obs.bottomRight]
        let smooth = raw.enumerated().map { i, pt in
            CGPoint(
                x: filters[i][0].filter(Double(pt.x), dt: dt),
                y: filters[i][1].filter(Double(pt.y), dt: dt)
            )
        }

        return DetectionResult(
            topLeft: smooth[0], topRight: smooth[1],
            bottomLeft: smooth[2], bottomRight: smooth[3],
            quality: quality, level: level
        )
    }

    var isReadyToCapture: Bool { greenFrames >= captureThreshold }

    func resetStability() {
        greenFrames = 0
        filters.forEach { $0.forEach { $0.reset() } }
    }

    // MARK: - Quality Scoring

    private func score(_ obs: VNRectangleObservation) -> Double {
        Double(obs.confidence) * 0.25
        + min(area(obs) / 0.25, 1.0) * 0.25
        + rectangularity(obs) * 0.25
        + stability(obs) * 0.25
    }

    private func area(_ obs: VNRectangleObservation) -> Double {
        let pts = [obs.topLeft, obs.topRight, obs.bottomRight, obs.bottomLeft]
        var a = 0.0
        for i in 0..<4 {
            let j = (i + 1) % 4
            a += Double(pts[i].x * pts[j].y) - Double(pts[j].x * pts[i].y)
        }
        return abs(a) / 2.0
    }

    private func rectangularity(_ obs: VNRectangleObservation) -> Double {
        let corners = [obs.topLeft, obs.topRight, obs.bottomRight, obs.bottomLeft]
        var totalDev = 0.0
        for i in 0..<4 {
            let prev = corners[(i + 3) % 4], curr = corners[i], next = corners[(i + 1) % 4]
            let v1 = CGPoint(x: prev.x - curr.x, y: prev.y - curr.y)
            let v2 = CGPoint(x: next.x - curr.x, y: next.y - curr.y)
            let dot = Double(v1.x * v2.x + v1.y * v2.y)
            let mag = sqrt(Double(v1.x*v1.x + v1.y*v1.y)) * sqrt(Double(v2.x*v2.x + v2.y*v2.y))
            guard mag > 0 else { return 0 }
            totalDev += abs(acos(min(max(dot / mag, -1), 1)) - .pi / 2) / (.pi / 2)
        }
        return max(0, 1.0 - totalDev / 4.0)
    }

    private func stability(_ obs: VNRectangleObservation) -> Double {
        guard let prev = previous else { return 0.5 }
        let d = (dist(obs.topLeft, prev.topLeft) + dist(obs.topRight, prev.topRight) +
                 dist(obs.bottomLeft, prev.bottomLeft) + dist(obs.bottomRight, prev.bottomRight)) / 4
        return max(0, 1.0 - d / 0.05)
    }

    private func dist(_ a: CGPoint, _ b: CGPoint) -> Double {
        hypot(Double(a.x - b.x), Double(a.y - b.y))
    }
}
