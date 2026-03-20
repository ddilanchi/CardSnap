import SwiftUI
import AVFoundation

class ScannerViewModel: ObservableObject {
    let camera = CameraManager()
    private let detector = CardDetector()
    private let gemini = GeminiService()

    @Published var overlayPoints: [CGPoint] = []
    @Published var overlayColor: Color = .clear
    @Published var scannedCards: [ScannedCard] = []
    @Published var isProcessing = false
    @Published var lastCard: ScannedCard?
    @Published var statusText = "Point camera at a business card"
    @Published var showDuplicateAlert = false
    @Published var duplicateOf: ScannedCard?
    @Published var errorMessage: String?
    @Published var showError = false

    private var isBusy = false
    private var pendingCard: ScannedCard?

    init() {
        camera.onFrame = { [weak self] pixelBuffer in
            self?.handleFrame(pixelBuffer)
        }
    }

    func start() { camera.requestPermission(); camera.start() }
    func stop()  { camera.stop() }

    private func handleFrame(_ pixelBuffer: CVPixelBuffer) {
        let result = detector.detect(in: pixelBuffer)
        let ready = detector.isReadyToCapture

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard let result else {
                overlayPoints = []
                overlayColor = .clear
                if !isProcessing { statusText = "Point camera at a business card" }
                return
            }

            overlayPoints = [result.topLeft, result.topRight, result.bottomRight, result.bottomLeft]
                .map { camera.convertPoint($0) }

            switch result.level {
            case .red:    overlayColor = .red;    if !isProcessing { statusText = "Move closer or adjust angle" }
            case .yellow: overlayColor = .yellow; if !isProcessing { statusText = "Hold steady…" }
            case .green:  overlayColor = .green;  if !isProcessing { statusText = "Capturing…" }
            }

            if ready && !isBusy { capture() }
        }
    }

    private func capture() {
        guard !isBusy else { return }
        isBusy = true
        isProcessing = true

        HapticManager.shared.cardCaptured()
        SoundManager.shared.playShutter()

        Task {
            do {
                let imageData = try await camera.capturePhoto()
                let card = try await gemini.extractCardInfo(from: imageData)

                await MainActor.run {
                    if let dup = findDuplicate(of: card) {
                        duplicateOf = dup
                        pendingCard = card
                        showDuplicateAlert = true
                        HapticManager.shared.duplicateWarning()
                    } else {
                        add(card)
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    HapticManager.shared.error()
                }
            }

            try? await Task.sleep(nanoseconds: 2_000_000_000)

            await MainActor.run {
                isProcessing = false
                isBusy = false
                detector.resetStability()
                statusText = "Ready for next card"
            }
        }
    }

    func add(_ card: ScannedCard) {
        scannedCards.append(card)
        lastCard = card
        statusText = "✓ Got \(card.displayName)"
    }

    func acceptDuplicate() {
        if let c = pendingCard { add(c) }
        pendingCard = nil; duplicateOf = nil
    }

    func rejectDuplicate() {
        pendingCard = nil; duplicateOf = nil
    }

    func appendNote(_ note: String, to cardId: UUID) {
        guard let i = scannedCards.firstIndex(where: { $0.id == cardId }) else { return }
        let existing = scannedCards[i].notes
        scannedCards[i].notes = existing.isEmpty ? note : existing + "\n" + note
        if lastCard?.id == cardId { lastCard = scannedCards[i] }
    }

    func finishSession() -> ScanBatch? {
        guard !scannedCards.isEmpty else { return nil }
        let batch = ScanBatch(cards: scannedCards)
        StorageService.shared.add(batch)
        scannedCards = []
        lastCard = nil
        statusText = "Point camera at a business card"
        return batch
    }

    private func findDuplicate(of card: ScannedCard) -> ScannedCard? {
        scannedCards.first { existing in
            (!card.email.isEmpty && card.email.lowercased() == existing.email.lowercased()) ||
            (similarity(card.principal, existing.principal) > 0.8 &&
             similarity(card.entity, existing.entity) > 0.7)
        }
    }

    private func similarity(_ a: String, _ b: String) -> Double {
        let a = a.lowercased(), b = b.lowercased()
        guard !a.isEmpty && !b.isEmpty else { return a == b ? 1 : 0 }
        let longer = a.count >= b.count ? a : b
        let shorter = a.count < b.count ? a : b
        let dist = levenshtein(longer, shorter)
        return 1.0 - Double(dist) / Double(longer.count)
    }

    private func levenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        var dp = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { dp[i][0] = i }
        for j in 0...b.count { dp[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                dp[i][j] = a[i-1] == b[j-1] ? dp[i-1][j-1] : 1 + min(dp[i-1][j], dp[i][j-1], dp[i-1][j-1])
            }
        }
        return dp[a.count][b.count]
    }
}
