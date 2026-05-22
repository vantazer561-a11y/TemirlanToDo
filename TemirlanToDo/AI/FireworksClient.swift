import Foundation

public final class FireworksClient {
    private let session: URLSession
    private let endpoint = URL(string: "https://api.fireworks.ai/inference/v1/chat/completions")!

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func sendAssistantRequest(apiKey: String, developerPrompt: String, userPrompt: String) async throws -> AssistantResponse {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody(
            developerPrompt: developerPrompt,
            userPrompt: userPrompt
        ))

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FireworksClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw FireworksClientError.apiError(
                statusCode: httpResponse.statusCode,
                message: FireworksErrorEnvelope.message(from: data)
            )
        }

        let envelope = try JSONDecoder().decode(FireworksChatCompletionEnvelope.self, from: data)
        guard let outputText = envelope.outputText, let outputData = outputText.data(using: .utf8) else {
            throw FireworksClientError.missingOutputText
        }
        return try JSONDecoder().decode(AssistantResponse.self, from: outputData)
    }

    private func requestBody(developerPrompt: String, userPrompt: String) -> [String: Any] {
        [
            "model": "accounts/fireworks/routers/kimi-k2p6-turbo",
            "temperature": 0.2,
            "response_format": [
                "type": "json_object"
            ],
            "messages": [
                [
                    "role": "system",
                    "content": """
                    \(developerPrompt)

                    Return a single valid JSON object with this exact shape:
                    {
                      "message": "short explanation",
                      "actions": [
                        {
                          "type": "create_task | update_task | delete_task | message_only",
                          "taskId": "existing UUID or null",
                          "title": "task title or null",
                          "notes": "task notes or null",
                          "isImportant": true,
                          "isInMyDay": false,
                          "isCompleted": false,
                          "dueDate": "yyyy-MM-dd or null"
                        }
                      ]
                    }
                    Use null for unknown optional fields. Do not include markdown.
                    """
                ],
                [
                    "role": "user",
                    "content": userPrompt
                ]
            ]
        ]
    }
}

private struct FireworksErrorEnvelope: Decodable {
    struct APIError: Decodable {
        var message: String?
        var type: String?
        var code: String?
    }

    var error: APIError?

    static func message(from data: Data) -> String? {
        if let envelope = try? JSONDecoder().decode(FireworksErrorEnvelope.self, from: data) {
            return envelope.error?.message ?? envelope.error?.code ?? envelope.error?.type
        }
        return String(data: data, encoding: .utf8)
    }
}

public enum FireworksClientError: LocalizedError {
    case invalidResponse
    case apiError(statusCode: Int, message: String?)
    case missingOutputText

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Fireworks returned an invalid response."
        case .apiError(let statusCode, _):
            if statusCode == 401 {
                return "Fireworks rejected the API key. Check and save the key again."
            }
            if statusCode == 429 {
                return "Fireworks returned 429. Check Fireworks billing, Fire Pass status, and rate limits. If access is active, wait a little and try again."
            }
            return "Fireworks request failed with status \(statusCode)."
        case .missingOutputText:
            return "Fireworks did not return assistant output."
        }
    }

    public var failureReason: String? {
        switch self {
        case .apiError(_, let message):
            return message
        default:
            return nil
        }
    }
}
