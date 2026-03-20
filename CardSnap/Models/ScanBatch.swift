import Foundation

struct ScanBatch: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var cards: [ScannedCard] = []
    var createdAt: Date = Date()
    var name: String = ""

    init(id: UUID = UUID(), cards: [ScannedCard] = [], createdAt: Date = Date(), name: String? = nil) {
        self.id = id
        self.cards = cards
        self.createdAt = createdAt
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d · h:mm a"
        self.name = name ?? "Scan — \(formatter.string(from: createdAt))"
    }
}
