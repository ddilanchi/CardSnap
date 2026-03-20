import Foundation

class GeminiService {
    private let apiKey = Secrets.geminiAPIKey
    private let model = "gemini-2.0-flash"

    // MARK: - Single side

    func extractCardInfo(from imageData: Data) async throws -> ScannedCard {
        let parts: [[String: Any]] = [
            ["text": singleSidePrompt],
            ["inlineData": ["mimeType": "image/jpeg", "data": imageData.base64EncodedString()]]
        ]
        return try await call(parts: parts)
    }

    // MARK: - Two sides

    func extractCardInfo(front: Data, back: Data) async throws -> ScannedCard {
        let parts: [[String: Any]] = [
            ["text": twoSidePrompt],
            ["inlineData": ["mimeType": "image/jpeg", "data": front.base64EncodedString()]],
            ["text": "Back side of the same card:"],
            ["inlineData": ["mimeType": "image/jpeg", "data": back.base64EncodedString()]]
        ]
        return try await call(parts: parts)
    }

    // MARK: - Core API call

    private func call(parts: [[String: Any]]) async throws -> ScannedCard {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)") else {
            throw GeminiError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "contents": [["parts": parts]],
            "generationConfig": ["temperature": 0.1]
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw GeminiError.apiError("Status \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        return try parse(data)
    }

    // MARK: - Prompts

    private var singleSidePrompt: String {
        """
        Analyze this business card image. Return ONLY a JSON object with these exact fields:
        { "entity": "", "principal": "", "role": "", "email": "", "phone": "", "linkedin": "", "instagram": "", "website": "", "notes": "any handwritten text or annotations", "tags": [] }
        Empty string if not found. No markdown, no code blocks.
        """
    }

    private var twoSidePrompt: String {
        """
        Analyze these two images of the FRONT and BACK of the same business card. Combine all information from both sides. Return ONLY a JSON object with these exact fields:
        { "entity": "", "principal": "", "role": "", "email": "", "phone": "", "linkedin": "", "instagram": "", "website": "", "notes": "any handwritten text or annotations from either side", "tags": [] }
        Empty string if not found. No markdown, no code blocks.
        """
    }

    // MARK: - Parse

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
        case .parseError: return "Could not parse card data"
        }
    }
}
