import Foundation
import Security

/// Reads the Claude Code OAuth token (macOS Keychain, falling back to
/// ~/.claude/.credentials.json) and queries the undocumented usage endpoint
/// that Claude Code's own `/usage` command relies on.
enum ClaudeProvider {
    static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let keychainService = "Claude Code-credentials"

    struct Credentials {
        let accessToken: String
        let expiresAt: Date?
        let subscriptionType: String?
    }

    static func fetch() async throws -> ProviderResult {
        let creds = try loadCredentials()
        if let exp = creds.expiresAt, exp < Date() {
            throw UsageError.noCredentials("トークンの期限切れ。Claude Code を一度起動すると更新されます")
        }

        var req = URLRequest(url: usageURL)
        req.httpMethod = "GET"
        req.timeoutInterval = 20
        req.setValue("Bearer \(creds.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw UsageError.other("サーバーからの応答が不正です")
        }
        switch http.statusCode {
        case 200:
            break
        case 401, 403:
            throw UsageError.http(http.statusCode, "認証エラー。Claude Code で /login し直してください")
        case 429:
            throw UsageError.http(429, "レート制限中。次回の自動更新まで待ちます")
        default:
            throw UsageError.http(http.statusCode, "HTTP \(http.statusCode)")
        }

        let json = try JSON.object(from: data)
        let windows = parseWindows(json)
        if windows.isEmpty {
            throw UsageError.parse("使用量データが含まれていません")
        }
        return ProviderResult(windows: windows, plan: creds.subscriptionType?.capitalized, note: nil)
    }

    // MARK: Parsing

    private static let knownOrder: [(key: String, label: String)] = [
        ("five_hour", "5時間"),
        ("seven_day", "7日間"),
        ("seven_day_opus", "7日間 · Opus"),
        ("seven_day_sonnet", "7日間 · Sonnet"),
        ("seven_day_oauth_apps", "7日間 · アプリ"),
    ]

    static func parseWindows(_ json: [String: Any]) -> [UsageWindow] {
        var result: [UsageWindow] = []
        var seen = Set<String>()

        func append(key: String, label: String, dict: [String: Any]) {
            guard let util = JSON.number(dict["utilization"]) else { return }
            let reset = JSON.date(dict["resets_at"]) ?? JSON.date(dict["reset_at"])
            result.append(UsageWindow(id: "claude." + key, label: label, usedPercent: util, resetsAt: reset))
            seen.insert(key)
        }

        for item in knownOrder {
            if let dict = json[item.key] as? [String: Any] {
                append(key: item.key, label: item.label, dict: dict)
            }
        }
        // Any additional windows the API may add later.
        for key in json.keys.sorted() where !seen.contains(key) {
            if let dict = json[key] as? [String: Any], dict["utilization"] != nil {
                append(key: key, label: prettify(key), dict: dict)
            }
        }
        return result
    }

    private static func prettify(_ key: String) -> String {
        key.replacingOccurrences(of: "_", with: " ")
    }

    // MARK: Credentials

    static func loadCredentials() throws -> Credentials {
        if let data = readKeychain(), let c = parseCredentials(data) {
            return c
        }
        if let data = readCredentialsFile(), let c = parseCredentials(data) {
            return c
        }
        throw UsageError.noCredentials("Claude Code の認証情報が見つかりません。ターミナルで claude を起動し /login してください")
    }

    private static func readKeychain() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return data
    }

    private static func readCredentialsFile() -> Data? {
        let env = ProcessInfo.processInfo.environment
        let base: String
        if let dir = env["CLAUDE_CONFIG_DIR"], !dir.isEmpty {
            base = dir
        } else {
            base = NSHomeDirectory() + "/.claude"
        }
        let url = URL(fileURLWithPath: base).appendingPathComponent(".credentials.json")
        return try? Data(contentsOf: url)
    }

    private static func parseCredentials(_ data: Data) -> Credentials? {
        guard let root = try? JSON.object(from: data) else { return nil }
        let oauth = (root["claudeAiOauth"] as? [String: Any]) ?? root
        guard let token = JSON.string(oauth["accessToken"]), !token.isEmpty else { return nil }
        return Credentials(
            accessToken: token,
            expiresAt: JSON.date(oauth["expiresAt"]),
            subscriptionType: JSON.string(oauth["subscriptionType"])
        )
    }
}
