import Foundation

/// Loads configuration from a .env file at the project root.
enum EnvConfig {
    private static let values: [String: String] = {
        var dict: [String: String] = [:]

        // 1. Check the app bundle (works on device + simulator)
        if let bundlePath = Bundle.main.path(forResource: ".env", ofType: nil) {
            if let contents = try? String(contentsOfFile: bundlePath, encoding: .utf8) {
                dict = parse(contents)
            }
        }

        // 2. Walk up from bundle to find .env at project root (simulator only)
        if dict.isEmpty {
            let candidates: [String?] = [
                ProcessInfo.processInfo.environment["SOURCE_ROOT"],
                Bundle.main.bundlePath.components(separatedBy: "/Build/").first,
                ProcessInfo.processInfo.environment["PROJECT_DIR"]
            ]
            for base in candidates.compactMap({ $0 }) {
                let path = (base as NSString).appendingPathComponent(".env")
                if let contents = try? String(contentsOfFile: path, encoding: .utf8) {
                    dict = parse(contents)
                    break
                }
            }
        }

        // 3. Fallback: process working directory
        if dict.isEmpty {
            let path = (FileManager.default.currentDirectoryPath as NSString).appendingPathComponent(".env")
            if let contents = try? String(contentsOfFile: path, encoding: .utf8) {
                dict = parse(contents)
            }
        }

        return dict
    }()

    private static func parse(_ contents: String) -> [String: String] {
        var dict: [String: String] = [:]
        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            var value = parts[1].trimmingCharacters(in: .whitespaces)
            // Strip surrounding quotes
            if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
               (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            dict[key] = value
        }
        return dict
    }

    // MARK: - Accessors

    static var openAIAPIKey: String {
        values["OPENAI_API_KEY"] ?? ""
    }

    static var mainModel: String {
        values["MAIN_MODEL"] ?? "gpt-4.1-mini"
    }

    static var heroAPIToken: String {
        values["HERO_API_TOKEN"] ?? ""
    }

    static var heroAPIURL: String {
        values["HERO_API_URL"] ?? "https://login.hero-software.de/api/external/v9/graphql"
    }

    static var isConfigured: Bool {
        !openAIAPIKey.isEmpty && openAIAPIKey != "sk-your-key-here"
    }

    static var isHeroConfigured: Bool {
        !heroAPIToken.isEmpty && heroAPIToken != "your-hero-token-here"
    }

    /// Shared OpenAI client, or nil when not configured.
    static var openAIClient: OpenAIClient? {
        isConfigured ? OpenAIClient(apiKey: openAIAPIKey) : nil
    }
}
