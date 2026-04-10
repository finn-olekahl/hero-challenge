import Foundation

/// Lightweight OpenAI Chat Completions client with JSON mode support.
final class OpenAIClient: Sendable {
    private let apiKey: String
    private let session: URLSession
    private let baseURL = URL(string: "https://api.openai.com/v1/chat/completions")!

    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    // MARK: - Chat Completion

    func chatCompletion<T: Decodable>(
        model: String,
        systemPrompt: String,
        userPrompt: String,
        responseType: T.Type
    ) async throws -> T {
        let body = ChatCompletionRequest(
            model: model,
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: userPrompt)
            ],
            response_format: .init(type: "json_object"),
            temperature: 0.3
        )

        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        request.httpBody = try encoder.encode(body)

        // ── DEBUG REQUEST ──
        #if DEBUG
        let requestBody = String(data: request.httpBody!, encoding: .utf8) ?? "<binary>"
        print("\n┌──── OpenAI REQUEST ────")
        print("│ URL: \(baseURL.absoluteString)")
        print("│ Model: \(model)")
        print("│ System prompt (\(systemPrompt.count) chars): \(String(systemPrompt.prefix(200)))...")
        print("│ User prompt (\(userPrompt.count) chars): \(String(userPrompt.prefix(500)))...")
        print("│ Full body (\(request.httpBody!.count) bytes)")
        print("└────────────────────────\n")
        #endif

        let (data, response) = try await session.data(for: request)

        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1

        // ── DEBUG RESPONSE ──
        #if DEBUG
        let rawResponse = String(data: data, encoding: .utf8) ?? "<binary>"
        print("\n┌──── OpenAI RESPONSE ────")
        print("│ Status: \(statusCode)")
        print("│ Body (\(data.count) bytes):")
        if let json = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
           let prettyStr = String(data: pretty, encoding: .utf8) {
            for line in prettyStr.components(separatedBy: "\n") {
                print("│   \(line)")
            }
        } else {
            print("│   \(rawResponse.prefix(2000))")
        }
        print("└──────────────────────────\n")
        #endif

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let rawResponse = String(data: data, encoding: .utf8) ?? "<binary>"
            throw OpenAIError.httpError(statusCode: http.statusCode, body: rawResponse)
        }

        let completion = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)

        guard let content = completion.choices.first?.message.content else {
            throw OpenAIError.noContent
        }

        #if DEBUG
        print("\n┌──── OpenAI PARSED CONTENT ────")
        print("│ \(content)")
        print("└────────────────────────────────\n")
        #endif

        guard let jsonData = content.data(using: .utf8) else {
            throw OpenAIError.invalidJSON
        }

        do {
            return try JSONDecoder().decode(T.self, from: jsonData)
        } catch {
            #if DEBUG
            print("\n┌──── OpenAI DECODING ERROR ────")
            print("│ \(error)")
            print("│ Content was: \(content)")
            print("└────────────────────────────────\n")
            #endif
            throw OpenAIError.decodingFailed(content: content, error: error)
        }
    }
}

// MARK: - Request / Response Types

private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [Message]
    let response_format: ResponseFormat
    let temperature: Double

    struct Message: Encodable {
        let role: String
        let content: String
    }

    struct ResponseFormat: Encodable {
        let type: String
    }
}

private struct ChatCompletionResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String?
    }
}

// MARK: - Errors

enum OpenAIError: Error, LocalizedError {
    case httpError(statusCode: Int, body: String)
    case noContent
    case invalidJSON
    case decodingFailed(content: String, error: Error)
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .httpError(let code, let body):
            return "OpenAI API Fehler (HTTP \(code)): \(body.prefix(200))"
        case .noContent:
            return "Keine Antwort von OpenAI erhalten."
        case .invalidJSON:
            return "Ungültige JSON-Antwort von OpenAI."
        case .decodingFailed(let content, let error):
            return "JSON-Parsing fehlgeschlagen: \(error.localizedDescription)\nAntwort: \(content.prefix(300))"
        case .notConfigured:
            return "OpenAI API Key nicht konfiguriert. Bitte .env Datei prüfen."
        }
    }
}
