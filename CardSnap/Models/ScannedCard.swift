import Foundation

struct ScannedCard: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var entity: String = ""
    var principal: String = ""
    var role: String = ""
    var email: String = ""
    var phone: String = ""
    var linkedin: String = ""
    var instagram: String = ""
    var website: String = ""
    var notes: String = ""
    var confidence: String = "Scanned"
    var tags: [String] = []
    var createdAt: Date = Date()

    var displayName: String {
        principal.isEmpty ? (entity.isEmpty ? "Unknown" : entity) : principal
    }
}
