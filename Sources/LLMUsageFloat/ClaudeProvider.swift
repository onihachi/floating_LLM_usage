import CryptoKit
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

    /// Minimum spacing between Keychain reads after a failed credential lookup,
    /// so a logged-out CLI does not raise the keychain dialog on every refresh.
    static let keychainRetryInterval: TimeInterval = 30 * 60

    /// - Parameter force: read the Keychain again even inside the retry
    ///   backoff (used by "今すぐ更新", e.g. right after `claude auth login`).
    static func fetch(force: Bool = false) async throws -> ProviderResult {
        // Reuse the in-memory credentials while they are still valid: every
        // Keychain read can raise the macOS keychain dialog (ad-hoc signed app).
        let creds: Credentials
        if let cached = validCachedCredentials() {
            creds = cached
        } else {
            if !force, let pending = pendingLookupError() {
                throw pending
            }
            do {
                creds = try loadCredentials()
            } catch {
                recordLookupFailure(error)
                throw error
            }
            if let exp = creds.expiresAt, exp < Date() {
                // Stale token: treat like a failed lookup so the Keychain is not
                // re-read on every tick until Claude Code refreshes it.
                let error = UsageError.noCredentials("トークンの期限切れ。Claude Code を一度起動すると更新されます")
                recordLookupFailure(error)
                throw error
            }
            storeCachedCredentials(creds)
        }

        let (http, data) = try await request(creds)
        switch http.statusCode {
        case 200:
            break
        case 401, 403:
            // Rejected token: forget it so the next refresh re-reads the
            // Keychain and picks up a fresh login.
            clearCredentialCache()
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

    /// Raw HTTP round trip (shared by `fetch` and the `--dump` diagnostics).
    static func request(_ creds: Credentials) async throws -> (HTTPURLResponse, Data) {
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
        return (http, data)
    }

    // MARK: Credential cache

    /// Last credentials loaded successfully. Kept in memory so the Keychain is
    /// not queried on every refresh; all access goes through `cacheLock`.
    nonisolated(unsafe) private static var cachedCredentials: Credentials?
    private static let cacheLock = NSLock()

    /// Forgets the in-memory credentials so the next `fetch()` reads the
    /// Keychain again. Also meant for a future "reload after re-login" menu item.
    static func clearCredentialCache() {
        cacheLock.withLock {
            cachedCredentials = nil
            lastLookupError = nil
            nextKeychainRetry = .distantPast
        }
    }

    /// The cached credentials, unless there are none or they are past their expiry.
    private static func validCachedCredentials() -> Credentials? {
        cacheLock.withLock {
            guard let creds = cachedCredentials else { return nil }
            if let exp = creds.expiresAt, exp <= Date() { return nil }
            return creds
        }
    }

    private static func storeCachedCredentials(_ creds: Credentials) {
        cacheLock.withLock {
            cachedCredentials = creds
            lastLookupError = nil
            nextKeychainRetry = .distantPast
        }
    }

    nonisolated(unsafe) private static var lastLookupError: Error?
    nonisolated(unsafe) private static var nextKeychainRetry: Date = .distantPast

    /// The previous lookup error while the retry backoff is still running.
    private static func pendingLookupError() -> Error? {
        cacheLock.withLock {
            guard let error = lastLookupError, Date() < nextKeychainRetry else { return nil }
            return error
        }
    }

    private static func recordLookupFailure(_ error: Error) {
        cacheLock.withLock {
            lastLookupError = error
            nextKeychainRetry = Date().addingTimeInterval(keychainRetryInterval)
        }
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
        // Only the known windows are shown; unknown keys (internal code names
        // such as "iguana_necktie") are intentionally skipped.
        for item in knownOrder {
            guard let dict = json[item.key] as? [String: Any],
                  let util = JSON.number(dict["utilization"]) else { continue }
            let reset = JSON.date(dict["resets_at"]) ?? JSON.date(dict["reset_at"])
            result.append(UsageWindow(id: "claude." + item.key, label: item.label, usedPercent: util, resetsAt: reset))
        }
        return result
    }

    // MARK: Credentials

    static func loadCredentials() throws -> Credentials {
        // Return at the first source whose token is not expired (each Keychain
        // item can raise its own permission dialog, so stop as early as
        // possible); otherwise fall back to the first parseable one so the
        // caller can report the expiry.
        var stale: Credentials?
        func consider(_ data: Data?) -> Credentials? {
            guard let data, let c = parseCredentials(data) else { return nil }
            if c.expiresAt.map({ $0 > Date() }) ?? true { return c }
            if stale == nil { stale = c }
            return nil
        }
        for service in keychainServiceNames() {
            if let fresh = consider(readKeychain(service: service)) { return fresh }
        }
        if let fresh = consider(readCredentialsFile()) { return fresh }
        if let stale {
            return stale
        }
        throw UsageError.noCredentials("Claude Code CLI が未ログインです。ターミナルで claude auth login を実行してください（デスクトップアプリのログインとは別です）")
    }

    /// Claude Code ≥ 2.1 stores the login under a per-config-directory item,
    /// `Claude Code-credentials-<first 8 hex of sha256(configDir)>`; the legacy
    /// unsuffixed item may only hold MCP OAuth state. Try the hashed names first.
    static func keychainServiceNames() -> [String] {
        let dir = configDirectory()
        let trimmed = dir.hasSuffix("/") ? String(dir.dropLast()) : dir
        var names: [String] = []
        for candidate in [trimmed, trimmed + "/"] {
            let digest = SHA256.hash(data: Data(candidate.utf8))
            let hex = digest.map { String(format: "%02x", $0) }.joined()
            names.append("\(keychainService)-\(hex.prefix(8))")
        }
        names.append(keychainService)
        return names
    }

    static func configDirectory() -> String {
        let env = ProcessInfo.processInfo.environment
        if let dir = env["CLAUDE_CONFIG_DIR"], !dir.isEmpty {
            return (dir as NSString).expandingTildeInPath
        }
        return NSHomeDirectory() + "/.claude"
    }

    static func readKeychain(service: String) -> Data? {
        readKeychain(service: service, status: nil)
    }

    static func readKeychain(service: String, status out: UnsafeMutablePointer<OSStatus>?) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        out?.pointee = status
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return data
    }

    static func credentialsFileURL() -> URL {
        URL(fileURLWithPath: configDirectory()).appendingPathComponent(".credentials.json")
    }

    static func readCredentialsFile() -> Data? {
        try? Data(contentsOf: credentialsFileURL())
    }

    static func parseCredentials(_ data: Data) -> Credentials? {
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
