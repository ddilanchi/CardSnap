import Foundation

class ExportService {
    static func jsonURL(from cards: [ScannedCard]) throws -> URL {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(cards)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("business_cards_\(timestamp()).json")
        try data.write(to: url)
        return url
    }

    static func csvURL(from cards: [ScannedCard]) throws -> URL {
        var csv = "Entity,Principal,Role,Email,Phone,LinkedIn,Instagram,Website,Notes,Tags,Confidence,Created\n"
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm"
        for c in cards {
            let row = [c.entity, c.principal, c.role, c.email, c.phone,
                       c.linkedin, c.instagram, c.website, c.notes,
                       c.tags.joined(separator: "; "), c.confidence, df.string(from: c.createdAt)]
                .map { escape($0) }.joined(separator: ",")
            csv += row + "\n"
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("business_cards_\(timestamp()).csv")
        try csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func exportItems(from cards: [ScannedCard]) -> [Any] {
        var items: [Any] = []
        if let j = try? jsonURL(from: cards) { items.append(j) }
        if let c = try? csvURL(from: cards) { items.append(c) }
        return items
    }

    private static func escape(_ s: String) -> String {
        s.contains(",") || s.contains("\"") || s.contains("\n")
            ? "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\"" : s
    }

    private static func timestamp() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd_HHmm"
        return df.string(from: Date())
    }
}
