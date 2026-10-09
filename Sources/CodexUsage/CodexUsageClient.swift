import Foundation

struct UsageEndpoints {
    let usage: URL
    let rateLimitResetCredits: URL?
}

enum CodexEndpoints {
    static let defaultBaseURL = "https://chatgpt.com/backend-api"

    static func resolve() -> UsageEndpoints {
        var base = Self.defaultBaseURL
        if let config = try? String(contentsOf: CodexPaths.configFile, encoding: .utf8),
           let value = Self.baseURL(from: config), !value.isEmpty {
            base = value
        }
        var trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        if (trimmed.hasPrefix("https://chatgpt.com") || trimmed.hasPrefix("https://chat.openai.com"))
            && !trimmed.contains("/backend-api") {
            trimmed += "/backend-api"
        }
        let isBackendAPI = trimmed.contains("/backend-api")
        let usagePath = isBackendAPI ? "/wham/usage" : "/api/codex/usage"
        let usage = URL(string: trimmed + usagePath)
            ?? URL(string: Self.defaultBaseURL + "/wham/usage")!
        let resetCredits = isBackendAPI
            ? URL(string: trimmed + "/wham/rate-limit-reset-credits")
            : nil
        return UsageEndpoints(usage: usage, rateLimitResetCredits: resetCredits)
    }

    private static func baseURL(from config: String) -> String? {
        for rawLine in config.split(whereSeparator: \.isNewline) {
            let line = rawLine
                .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
                .first?
                .trimmingCharacters(in: .whitespaces) ?? ""
            guard !line.isEmpty else { continue }
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2,
                  parts[0].trimmingCharacters(in: .whitespaces) == "chatgpt_base_url"
            else { continue }
            var value = parts[1].trimmingCharacters(in: .whitespaces)
            if (value.hasPrefix("\"") && value.hasSuffix("\""))
                || (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            return value.trimmingCharacters(in: .whitespaces)
        }
        return nil
    }
}

final class CodexUsageClient: Sendable {
    enum FetchError: LocalizedError {
        case unauthorized
        case unsupportedEndpoint
        case server(Int, String)
        case invalidResponse
        case network(String)

        var errorDescription: String? {
            switch self {
            case .unauthorized:
                return "Codex rejected the token (401). Run `codex login` to re-authenticate."
            case .unsupportedEndpoint:
                return "This Codex base URL does not expose the rate limit reset endpoint."
            case let .server(code, body):
                return "Codex API error \(code)\(body.isEmpty ? "" : ": " + body)"
            case .invalidResponse:
                return "Codex returned an unexpected response."
            case let .network(detail):
                return "Network error: \(detail)"
            }
        }
    }

    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 30
        session = URLSession(configuration: configuration)
    }

    func fetchUsage(accessToken: String, accountID: String?) async throws -> UsageResponse {
        let request = Self.request(
            url: CodexEndpoints.resolve().usage,
            method: "GET",
            accessToken: accessToken,
            accountID: accountID,
            accountHeader: "ChatGPT-Account-Id",
            extraHeaders: [:]
        )
        let (data, response) = try await Self.perform(request, with: session)
        try Self.validate(data: data, response: response)
        return try Self.decode(UsageResponse.self, from: data)
    }

    func fetchRateLimitResetCredits(
        accessToken: String,
        accountID: String?
    ) async throws -> ResetCreditsResponse {
        guard let url = CodexEndpoints.resolve().rateLimitResetCredits else {
            throw FetchError.unsupportedEndpoint
        }
        let request = Self.request(
            url: url,
            method: "GET",
            accessToken: accessToken,
            accountID: accountID,
            accountHeader: "ChatGPT-Account-ID",
            extraHeaders: [
                "OpenAI-Beta": "codex-1",
                "originator": "Codex Desktop",
            ]
        )
        let (data, response) = try await Self.perform(request, with: session)
        try Self.validate(data: data, response: response)
        return try Self.decode(ResetCreditsResponse.self, from: data)
    }

    private static func perform(_ request: URLRequest, with session: URLSession) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw FetchError.network("Unexpected response type")
            }
            return (data, http)
        } catch let caught as FetchError {
            throw caught
        } catch {
            throw FetchError.network(error.localizedDescription)
        }
    }

    private static func validate(data: Data, response: HTTPURLResponse) throws {
        guard (200...299).contains(response.statusCode) else {
            if response.statusCode == 401 {
                throw FetchError.unauthorized
            }
            let body = (String(data: data, encoding: .utf8) ?? "")
                .prefix(200)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw FetchError.server(response.statusCode, body)
        }
    }

    private static func request(
        url: URL,
        method: String,
        accessToken: String,
        accountID: String?,
        accountHeader: String,
        extraHeaders: [String: String]
    ) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("CodexUsage", forHTTPHeaderField: "User-Agent")
        if let accountID, !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: accountHeader)
        }
        for (key, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        return request
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder.codex().decode(type, from: data)
        } catch {
            throw FetchError.invalidResponse
        }
    }
}

struct CodexUsageService {
    struct Result {
        let usage: UsageResponse
        let resetCredits: [ResetCredit]
    }

    let client: CodexUsageClient

    init(client: CodexUsageClient = CodexUsageClient()) {
        self.client = client
    }

    func fetch() async throws -> Result {
        var credentials = try CodexCredentialsStore.load()
        if credentials.needsRefresh {
            credentials = try await CodexTokenRefresher.refresh(credentials)
            try CodexCredentialsStore.persist(credentials)
        }

        let usage: UsageResponse
        do {
            usage = try await client.fetchUsage(
                accessToken: credentials.accessToken,
                accountID: credentials.accountId
            )
        } catch CodexUsageClient.FetchError.unauthorized where credentials.kind == .oauth {
            credentials = try await CodexTokenRefresher.refresh(credentials)
            try CodexCredentialsStore.persist(credentials)
            usage = try await client.fetchUsage(
                accessToken: credentials.accessToken,
                accountID: credentials.accountId
            )
        }

        var resetCredits: [ResetCredit] = []
        if let summary = usage.rateLimitResetCredits, (summary.availableCount ?? 0) > 0 {
            if let response = try? await client.fetchRateLimitResetCredits(
                accessToken: credentials.accessToken,
                accountID: credentials.accountId
            ) {
                resetCredits = response.credits
            }
        }
        return Result(usage: usage, resetCredits: resetCredits)
    }
}
