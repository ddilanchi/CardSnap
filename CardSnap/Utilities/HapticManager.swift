import UIKit

class HapticManager {
    static let shared = HapticManager()

    private let success = UINotificationFeedbackGenerator()
    private let warning = UINotificationFeedbackGenerator()
    private let impact = UIImpactFeedbackGenerator(style: .medium)

    private init() {
        success.prepare()
        warning.prepare()
        impact.prepare()
    }

    func cardCaptured() { success.notificationOccurred(.success) }
    func duplicateWarning() { warning.notificationOccurred(.warning) }
    func error() { success.notificationOccurred(.error) }
}
