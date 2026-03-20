import Foundation

class GeminiService {
    private let apiKey = Secrets.geminiAPIKey
    private let model = "gemini-2.0-flash"

    func extractCardInfo(from imageData: Data) async throws -> ScannedCard {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)") else {
            throw GeminiError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "contents": [[
                "parts": [
                    ["text": prompt],
                    ["inlineData": ["mimeType": "image/jpeg", "data": imageData.base64EncodedString()]]
                ]
            ]],
            "generationConfig": ["temperature": 0.1]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw GeminiError.apiError("Status \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }

        return try parse(data)
    }

    private var prompt: String {
        """
        Analyze this business card image. Extract all visible information and return ONLY a JSON object with these exact fields:
        {
          "entity": "company or organization name",
          "principal": "person full name",
          "role": "job title or position",
          "email": "email address",
          "phone": "phone number",
          "linkedin": "linkedin url or handle",
          "instagram": "instagram handle",
          "website": "website url",
          "notes": "any handwritten text or annotations visible on the card",
          "tags": ["relevant", "category", "tags"]
        }
        Rules: empty string if not found, empty array for tags if none. Return ONLY the JSON, no markdown, no code blocks.
        """
    }

    private func parse(_ data: Data) throws -> ScannedCard {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let candidates = json["candidates"] as? [[String: Any]],
            let content = candidates.first?["content"] as? [String: Any],
            let parts = content["parts"] as? [[String: Any]],
            let text = parts.first?["text"] as? String
        else { throw GeminiError.parseError }

        let cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard
            let cardData = cleaned.data(using: .utf8),
            let card = try? JSONSerialization.jsonObject(with: cardData) as? [String: Any]
        else { throw GeminiError.parseError }

        return ScannedCard(
            entity: card["entity"] as? String ?? "",
            principal: card["principal"] as? String ?? "",
            role: card["role"] as? String ?? "",
            email: card["email"] as? String ?? "",
            phone: card["phone"] as? String ?? "",
            linkedin: card["linkedin"] as? String ?? "",
            instagram: card["instagram"] as? String ?? "",
            website: card["website"] as? String ?? "",
            notes: card["notes"] as? String ?? "",
            confidence: "Scanned",
            tags: card["tags"] as? [String] ?? []
        )
    }
}

enum GeminiError: LocalizedError {
    case invalidURL, apiError(String), parseError

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid API URL"
        case .apiError(let m): return "API error: \(m)"
        case .parseError: return "Could not parse card data from Gemini"
        }
    }
}
