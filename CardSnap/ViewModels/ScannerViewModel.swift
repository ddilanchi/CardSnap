import SwiftUI

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

    // Two-sided: set when user requests back-side scan
    @Published var isScanningBackSide = false
    private var frontImageData: Data?
    private var frontCardId: UUID?

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
                if !isProcessing { statusText = isScanningBackSide ? "Show the back of the card" : "Point camera at a business card" }
                return
            }

            overlayPoints = [result.topLeft, result.topRight, result.bottomRight, result.bottomLeft]
                .map { self.camera.convertPoint($0) }

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

                if isScanningBackSide, let front = frontImageData, let cardId = frontCardId {
                    // Merge front + back
                    let merged = try await gemini.extractCardInfo(front: front, back: imageData)
                    await MainActor.run {
                        // Replace the existing front-only card with merged data
                        if let i = self.scannedCards.firstIndex(where: { $0.id == cardId }) {
                            var updated = merged
                            updated.id = cardId
                            self.scannedCards[i] = updated
                            self.lastCard = updated
                        }
                        self.reset(status: "✓ Both sides captured")
                    }
                } else {
                    // Single-sided (default)
                    let card = try await gemini.extractCardInfo(from: imageData)
                    await MainActor.run {
                        self.capturedFrontData[card.id] = imageData  // store for optional back-side scan
                        self.addOrFlagDuplicate(card)
                        self.reset(status: "✓ Got \(card.displayName)")
                    }
                }
            } catch {
                await MainActor.run {
                    self.reset(status: "Point camera at a business card")
                    self.errorMessage = error.localizedDescription
                    self.showError = true
                    HapticManager.shared.error()
                }
            }
        }
    }

    // Called when user taps "2-sided" on the last card banner
    func startBackSideScan(for card: ScannedCard) {
        guard let imageData = capturedFrontData[card.id] else { return }
        frontImageData = imageData
        frontCardId = card.id
        isScanningBackSide = true
        statusText = "Now show the back of the card"
    }

    // Store front image data keyed by card ID so we can retrieve it later
    private var capturedFrontData: [UUID: Data] = [:]

    private func reset(status: String) {
        isProcessing = false
        isBusy = false
        isScanningBackSide = false
        frontImageData = nil
        frontCardId = nil
        detector.resetStability()
        statusText = status
    }

    private func addOrFlagDuplicate(_ card: ScannedCard) {
        if let dup = findDuplicate(of: card) {
            duplicateOf = dup; pendingCard = card; showDuplicateAlert = true
            HapticManager.shared.duplicateWarning()
        } else {
            add(card)
        }
    }

    func add(_ card: ScannedCard) {
        scannedCards.append(card)
        lastCard = card
    }

    func acceptDuplicate() { if let c = pendingCard { add(c) }; pendingCard = nil; duplicateOf = nil }
    func rejectDuplicate() { pendingCard = nil; duplicateOf = nil }

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
        scannedCards = []; lastCard = nil; capturedFrontData = [:]
        isScanningBackSide = false; frontImageData = nil; frontCardId = nil
        statusText = "Point camera at a business card"
        return batch
    }

    private func findDuplicate(of card: ScannedCard) -> ScannedCard? {
        scannedCards.first {
            (!card.email.isEmpty && card.email.lowercased() == $0.email.lowercased()) ||
            (similarity(card.principal, $0.principal) > 0.8 && similarity(card.entity, $0.entity) > 0.7)
        }
    }

    private func similarity(_ a: String, _ b: String) -> Double {
        let a = a.lowercased(), b = b.lowercased()
        guard !a.isEmpty && !b.isEmpty else { return a == b ? 1 : 0 }
        let longer = a.count >= b.count ? a : b
        return 1.0 - Double(levenshtein(longer, a.count < b.count ? a : b)) / Double(longer.count)
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
