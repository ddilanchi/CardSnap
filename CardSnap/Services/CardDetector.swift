import Vision
import CoreImage

enum QualityLevel { case red, yellow, green }

struct DetectionResult {
    let topLeft, topRight, bottomLeft, bottomRight: CGPoint
    let quality: Double
    let level: QualityLevel
}

class CardDetector {
    private var previous: VNRectangleObservation?
    private var greenFrames = 0
    private let captureThreshold = 18 // ~0.6s at 30fps

    // Smoothing: rolling average of last N corner positions
    private var cornerHistory: [[CGPoint]] = []
    private let historySize = 6

    // Tracking state
    private var trackedObservation: VNRectangleObservation?
    private var framesSinceDetect = 0
    private let redetectInterval = 45  // full re-detect every ~1.5s to avoid drift

    func detect(in pixelBuffer: CVPixelBuffer) -> DetectionResult? {
        let obs: VNRectangleObservation?

        if let tracked = trackedObservation, framesSinceDetect < redetectInterval {
            obs = track(tracked, in: pixelBuffer)
            framesSinceDetect += 1
            if obs == nil {
                // tracking lost — fall back to full detection immediately
                trackedObservation = nil
                framesSinceDetect = 0
            }
        } else {
            obs = detectRectangle(in: pixelBuffer)
            trackedObservation = obs
            framesSinceDetect = 0
        }

        guard let obs else {
            previous = nil
            greenFrames = 0
            cornerHistory.removeAll()
            trackedObservation = nil
            return nil
        }

        let quality = score(obs)
        let level: QualityLevel = quality >= 0.78 ? .green : quality >= 0.42 ? .yellow : .red
        greenFrames = level == .green ? greenFrames + 1 : 0
        previous = obs

        let raw = [obs.topLeft, obs.topRight, obs.bottomLeft, obs.bottomRight]
        cornerHistory.append(raw)
        if cornerHistory.count > historySize { cornerHistory.removeFirst() }
        let smooth = smoothedCorners()

        return DetectionResult(
            topLeft: smooth[0], topRight: smooth[1],
            bottomLeft: smooth[2], bottomRight: smooth[3],
            quality: quality, level: level
        )
    }

    var isReadyToCapture: Bool { greenFrames >= captureThreshold }

    func resetStability() {
        greenFrames = 0
        cornerHistory.removeAll()
        trackedObservation = nil
        framesSinceDetect = 0
    }

    // MARK: - Detection

    private func detectRectangle(in pixelBuffer: CVPixelBuffer) -> VNRectangleObservation? {
        let request = VNDetectRectanglesRequest()
        // Standard business card is 3.375" × 2.125" = 1.588:1
        // Tightened from 1.3–2.2 to cut false positives (phones, wallets, notebooks)
        request.minimumAspectRatio = 1.45
        request.maximumAspectRatio = 1.75
        request.minimumSize = 0.12
        request.maximumObservations = 1
        request.minimumConfidence = 0.4
        request.quadratureTolerance = 25

        // .right = portrait mode (sensor is landscape, portrait = 90° CW)
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
        try? handler.perform([request])
        return request.results?.first
    }

    // MARK: - Tracking

    private func track(_ observation: VNRectangleObservation, in pixelBuffer: CVPixelBuffer) -> VNRectangleObservation? {
        let request = VNTrackRectangleRequest(rectangleObservation: observation)
        request.trackingLevel = .accurate

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
        try? handler.perform([request])

        guard let result = request.results?.first as? VNRectangleObservation,
              result.confidence > 0.3 else { return nil }

        // Feed result back so next track call uses latest corners
        trackedObservation = result
        return result
    }

    // MARK: - Smoothing

    private func smoothedCorners() -> [CGPoint] {
        guard !cornerHistory.isEmpty else { return Array(repeating: .zero, count: 4) }
        return (0..<4).map { i in
            let xs = cornerHistory.map { $0[i].x }
            let ys = cornerHistory.map { $0[i].y }
            return CGPoint(x: xs.reduce(0, +) / CGFloat(xs.count),
                           y: ys.reduce(0, +) / CGFloat(ys.count))
        }
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
