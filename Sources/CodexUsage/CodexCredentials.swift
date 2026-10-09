import Foundation

enum CodexPaths {
    static var codexHome: URL {
        let raw = ProcessInfo.processInfo.environment["CODEX_HOME"]
        let override = raw?.trimmingCharacters(in: .whitespaces)
        if let override, !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
    }

    static var authFile: URL {
        codexHome.appendingPathComponent("auth.json")
    }

    static var configFile: URL {
        codexHome.appendingPathComponent("config.toml")
    }
}

enum CredentialError: LocalizedError {
    case notFound
    case unreadable(String)
    case missingTokens

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "No Codex credentials found at \(CodexPaths.authFile.path). Run `codex login` in a terminal, then open this app again."
        case let .unreadable(detail):
            return "Could not read Codex credentials: \(detail)"
        case .missingTokens:
            return "Codex auth.json contains no usable tokens. Run `codex login` in a terminal."
        }
    }
}

struct CodexCredentials {
    enum Kind: Equatable {
        case oauth
        case apiKey
        case pat
    }

    var kind: Kind
    var accessToken: String
    var refreshToken: String?
    var idToken: String?
    var accountId: String?
    var lastRefresh: Date?
    var expiresAt: Date?

    var needsRefresh: Bool {
        guard kind == .oauth,
              let refreshToken = refreshToken?.trimmingCharacters(in: .whitespaces),
              !refreshToken.isEmpty
        else { return false }
        if let expiresAt {
            return expiresAt.timeIntervalSinceNow < 5 * 60
        }
        if let lastRefresh {
            return Date().timeIntervalSince(lastRefresh) > 8 * 24 * 60 * 60
        }
        return true
    }
}

enum JWT {
    static func payload(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var encoded = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let data = Data(base64Encoded: encoded) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func expiration(of token: String) -> Date? {
        guard let payload = payload(token),
              let exp = (payload["exp"] as? NSNumber)?.doubleValue
        else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    static func accountID(of token: String) -> String? {
        guard let payload = payload(token) else { return nil }
        if let accountID = payload["chatgpt_account_id"] as? String, !accountID.isEmpty {
            return accountID
        }
        if let auth = payload["https://api.openai.com/auth"] as? [String: Any],
           let accountID = auth["chatgpt_account_id"] as? String, !accountID.isEmpty {
            return accountID
        }
        if let organizations = payload["organizations"] as? [[String: Any]] {
            for organization in organizations {
                if let accountID = organization["id"] as? String, !accountID.isEmpty {
                    return accountID
                }
            }
        }
        return nil
    }
}

enum CodexCredentialsStore {
    static func load() throws -> CodexCredentials {
        let data: Data
        do {
            data = try Data(contentsOf: CodexPaths.authFile)
        } catch {
            let code = (error as NSError).code
            if code == CocoaError.fileReadNoSuchFile.rawValue {
                throw CredentialError.notFound
            }
            throw CredentialError.unreadable((error as NSError).localizedDescription)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CredentialError.unreadable("auth.json is not valid JSON")
        }
        return try makeCredentials(from: json)
    }

    static func makeCredentials(from json: [String: Any]) throws -> CodexCredentials {
        let authMode = (json["auth_mode"] as? String)?.lowercased()
        let tokens = (json["tokens"] as? [String: Any]) ?? [:]
        let access = string(tokens["access_token"]) ?? string(tokens["accessToken"])
        let refresh = string(tokens["refresh_token"]) ?? string(tokens["refreshToken"])
        let idToken = string(tokens["id_token"]) ?? string(tokens["idToken"])
        let account = string(tokens["account_id"]) ?? string(tokens["accountId"])
        let lastRefresh = parseDate(json["last_refresh"])
        let apiKey = string(json["OPENAI_API_KEY"])
        let pat = string(json["personal_access_token"]) ?? string(json["personalAccessToken"])

        if authMode == "apikey", let apiKey {
            return CodexCredentials(
                kind: .apiKey,
                accessToken: apiKey,
                refreshToken: nil,
                idToken: nil,
                accountId: nil,
                lastRefresh: lastRefresh,
                expiresAt: nil
            )
        }
        if let access, !access.isEmpty {
            let accountID = account
                ?? JWT.accountID(of: idToken ?? "")
                ?? JWT.accountID(of: access)
            return CodexCredentials(
                kind: .oauth,
                accessToken: access,
                refreshToken: refresh,
                idToken: idToken,
                accountId: accountID,
                lastRefresh: lastRefresh,
                expiresAt: JWT.expiration(of: access)
            )
        }
        if let pat {
            return CodexCredentials(
                kind: .pat,
                accessToken: pat,
                refreshToken: nil,
                idToken: nil,
                accountId: nil,
                lastRefresh: lastRefresh,
                expiresAt: nil
            )
        }
        if let apiKey {
            return CodexCredentials(
                kind: .apiKey,
                accessToken: apiKey,
                refreshToken: nil,
                idToken: nil,
                accountId: nil,
                lastRefresh: lastRefresh,
                expiresAt: nil
            )
        }
        throw CredentialError.missingTokens
    }

    static func persist(_ credentials: CodexCredentials) throws {
        var json: [String: Any] = [:]
        if let existing = try? Data(contentsOf: CodexPaths.authFile),
           let object = try? JSONSerialization.jsonObject(with: existing) as? [String: Any] {
            json = object
        }
        var tokens: [String: Any] = [
            "access_token": credentials.accessToken,
            "refresh_token": credentials.refreshToken ?? "",
        ]
        if let idToken = credentials.idToken {
            tokens["id_token"] = idToken
        }
        if let accountId = credentials.accountId {
            tokens["account_id"] = accountId
        }
        json["tokens"] = tokens
        json["last_refresh"] = ISO8601DateFormatter().string(from: Date())
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])

        let destination = CodexPaths.authFile
        try FileManager.default.createDirectory(at: CodexPaths.codexHome, withIntermediateDirectories: true)
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".auth.json.tmp-\(UUID().uuidString)")
        do {
            try data.write(to: temporary)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    private static func string(_ value: Any?) -> String? {
        guard let value = value as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return value
    }

    private static func parseDate(_ value: Any?) -> Date? {
        guard let value = value as? String, !value.isEmpty else { return nil }
        return CodexDateParser.parse(value)
    }
}

enum CodexTokenRefresher {
    enum RefreshError: LocalizedError {
        case noRefreshToken
        case failed(Int, String)

        var errorDescription: String? {
            switch self {
            case .noRefreshToken:
                return "No refresh token available. Run `codex login` to re-authenticate."
            case let .failed(code, body):
                return "Token refresh failed (HTTP \(code))\(body.isEmpty ? "" : ": " + body). Run `codex login` to re-authenticate."
            }
        }
    }

    private static let endpoint = URL(string: "https://auth.openai.com/oauth/token")!
    private static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"

    static func refresh(_ credentials: CodexCredentials) async throws -> CodexCredentials {
        guard let refreshToken = credentials.refreshToken?.trimmingCharacters(in: .whitespaces),
              !refreshToken.isEmpty
        else {
            throw RefreshError.noRefreshToken
        }

        var request = URLRequest(url: endpoint, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = [
            "client_id": clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "scope": "openid profile email",
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            let snippet = (String(data: data, encoding: .utf8) ?? "")
                .prefix(160)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw RefreshError.failed(status, snippet.isEmpty ? "unexpected response" : snippet)
        }

        var updated = credentials
        updated.accessToken = string(json["access_token"]) ?? updated.accessToken
        updated.refreshToken = string(json["refresh_token"]) ?? updated.refreshToken
        updated.idToken = string(json["id_token"]) ?? updated.idToken
        updated.lastRefresh = Date()
        updated.expiresAt = JWT.expiration(of: updated.accessToken)
        return updated
    }

    private static func string(_ value: Any?) -> String? {
        guard let value = value as? String, !value.isEmpty else { return nil }
        return value
    }
}

enum CodexDateParser {
    static func parse(_ raw: String) -> Date? {
        if let date = standard.date(from: raw) {
            return date
        }
        guard let dotIndex = raw.firstIndex(of: ".") else { return nil }
        var end = raw.index(after: dotIndex)
        while end < raw.endIndex, raw[end].isNumber {
            end = raw.index(after: end)
        }
        guard end != raw.endIndex else { return nil }
        let stripped = String(raw[..<dotIndex]) + String(raw[end...])
        return standard.date(from: stripped)
    }

    private static let standard = ISO8601DateFormatter()
}

extension JSONDecoder {
    static func codex() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { container in
            let single = try container.singleValueContainer()
            if let epoch = try? single.decode(Double.self) {
                return Date(timeIntervalSince1970: epoch)
            }
            let raw = try single.decode(String.self)
            if let date = CodexDateParser.parse(raw) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: single,
                debugDescription: "Unrecognized date: \(raw)"
            )
        }
        return decoder
    }
}
