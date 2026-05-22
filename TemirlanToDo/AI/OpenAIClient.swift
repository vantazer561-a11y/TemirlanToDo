import Foundation

public final class OpenAIClient {
    private let session: URLSession
    private let endpoint = URL(string: "https://api.openai.com/v1/responses")!

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
            throw OpenAIClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw OpenAIClientError.apiError(
                statusCode: httpResponse.statusCode,
                message: OpenAIErrorEnvelope.message(from: data)
            )
        }

        let envelope = try JSONDecoder().decode(OpenAIResponseEnvelope.self, from: data)
        guard let outputText = envelope.outputText, let outputData = outputText.data(using: .utf8) else {
            throw OpenAIClientError.missingOutputText
        }
        return try JSONDecoder().decode(AssistantResponse.self, from: outputData)
    }

    private func requestBody(developerPrompt: String, userPrompt: String) -> [String: Any] {
        [
            "model": "gpt-5.5",
            "reasoning": [
                "effort": "low"
            ],
            "text": [
                "verbosity": "low",
                "format": [
                    "type": "json_schema",
                    "name": "temirlan_todo_assistant_response",
                    "strict": true,
                    "schema": AssistantSchema.json
                ]
            ],
            "input": [
                [
                    "role": "developer",
                    "content": developerPrompt
                ],
                [
                    "role": "user",
                    "content": userPrompt
                ]
            ]
        ]
    }
}

private struct OpenAIErrorEnvelope: Decodable {
    struct APIError: Decodable {
        var message: String?
        var type: String?
        var code: String?
    }

    var error: APIError?

    static func message(from data: Data) -> String? {
        if let envelope = try? JSONDecoder().decode(OpenAIErrorEnvelope.self, from: data) {
            return envelope.error?.message ?? envelope.error?.code ?? envelope.error?.type
        }
        return String(data: data, encoding: .utf8)
    }
}

public enum OpenAIClientError: LocalizedError {
    case invalidResponse
    case apiError(statusCode: Int, message: String?)
    case missingOutputText

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "OpenAI returned an invalid response."
        case .apiError(let statusCode, _):
            if statusCode == 401 {
                return "OpenAI rejected the API key. Check and save the key again."
            }
            if statusCode == 429 {
                return "OpenAI returned 429. Check your OpenAI Platform billing, credits, monthly usage limit, and model rate limits. If billing is active, wait a little and try again."
            }
            return "OpenAI request failed with status \(statusCode)."
        case .missingOutputText:
            return "OpenAI did not return assistant output."
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
