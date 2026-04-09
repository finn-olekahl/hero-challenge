import Foundation

enum GraphQLError: Error, LocalizedError {
    case invalidURL
    case httpError(statusCode: Int, body: String)
    case decodingError(Error)
    case noData

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid API URL."
        case .httpError(let code, let body): return "HTTP \(code): \(body)"
        case .decodingError(let err): return "Decoding failed: \(err.localizedDescription)"
        case .noData: return "No data in response."
        }
    }
}

struct GraphQLRequest: Encodable {
    let query: String
    let variables: [String: AnyCodable]?
}

struct GraphQLResponse<T: Decodable>: Decodable {
    let data: T?
    let errors: [GraphQLResponseError]?
}

struct GraphQLResponseError: Decodable {
    let message: String
}

final class GraphQLClient: Sendable {
    let baseURL: URL
    private let session: URLSession
    private let token: String

    init(baseURL: URL, token: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.token = token
        self.session = session
    }

    func perform<T: Decodable>(
        query: String,
        variables: [String: AnyCodable]? = nil,
        responseType: T.Type
    ) async throws -> T {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let body = GraphQLRequest(query: query, variables: variables)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw GraphQLError.httpError(statusCode: httpResponse.statusCode, body: body)
        }

        let decoded = try JSONDecoder().decode(GraphQLResponse<T>.self, from: data)

        if let errors = decoded.errors, !errors.isEmpty {
            throw GraphQLError.httpError(statusCode: 200, body: errors.map(\.message).joined(separator: ", "))
        }

        guard let result = decoded.data else {
            throw GraphQLError.noData
        }

        return result
    }
}
