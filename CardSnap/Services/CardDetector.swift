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

    func detect(in pixelBuffer: CVPixelBuffer) -> DetectionResult? {
        let request = VNDetectRectanglesRequest()
        request.minimumAspectRatio = 1.3
        request.maximumAspectRatio = 2.2
        request.minimumSize = 0.15
        request.maximumObservations = 1
        request.minimumConfidence = 0.5

        try? VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:]).perform([request])

        guard let obs = request.results?.first else {
            previous = nil
            greenFrames = 0
            return nil
        }

        let bufW = CVPixelBufferGetWidth(pixelBuffer)
        let bufH = CVPixelBufferGetHeight(pixelBuffer)
        let quality = score(obs, bufferSize: CGSize(width: bufW, height: bufH))

        let level: QualityLevel = quality >= 0.78 ? .green : quality >= 0.42 ? .yellow : .red
        greenFrames = level == .green ? greenFrames + 1 : 0
        previous = obs

        return DetectionResult(
            topLeft: obs.topLeft, topRight: obs.topRight,
            bottomLeft: obs.bottomLeft, bottomRight: obs.bottomRight,
            quality: quality, level: level
        )
    }

    var isReadyToCapture: Bool { greenFrames >= captureThreshold }

    func resetStability() { greenFrames = 0 }

    // MARK: - Quality Scoring

    private func score(_ obs: VNRectangleObservation, bufferSize: CGSize) -> Double {
        let confidence = Double(obs.confidence) * 0.25
        let size = min(area(obs) / 0.25, 1.0) * 0.25
        let rect = rectangularity(obs) * 0.25
        let stable = stability(obs) * 0.25
        return confidence + size + rect + stable
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
            let angle = acos(min(max(dot / mag, -1), 1))
            totalDev += abs(angle - .pi / 2) / (.pi / 2)
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
