import Foundation

/// Reads the Codex CLI login (~/.codex/auth.json) and queries the usage
/// endpoint that `codex` itself uses for `/status`. If that fails, falls back
/// to the most recent `rate_limits` event in ~/.codex/sessions/*.jsonl.
enum CodexProvider {
    static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    struct Credentials {
        let accessToken: String
        let accountID: String?
    }

    static func fetch() async throws -> ProviderResult {
        do {
            return try await fetchFromAPI()
        } catch {
            // Session logs are always local; use them when the API is unavailable.
            if let fallback = SessionLog.latest() {
                var r = fallback
                r.note = "セッションログから取得（\(error.localizedDescription)）"
                return r
            }
            throw error
        }
    }

    // MARK: API

    static func fetchFromAPI() async throws -> ProviderResult {
        let creds = try loadCredentials()

        var req = URLRequest(url: usageURL)
        req.httpMethod = "GET"
        req.timeoutInterval = 20
        req.setValue("Bearer \(creds.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("codex-cli", forHTTPHeaderField: "User-Agent")
        if let account = creds.accountID {
            req.setValue(account, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw UsageError.other("サーバーからの応答が不正です")
        }
        switch http.statusCode {
        case 200:
            break
        case 401, 403:
            throw UsageError.http(http.statusCode, "認証エラー。codex を起動するか codex login してください")
        case 429:
            throw UsageError.http(429, "レート制限中")
        default:
            throw UsageError.http(http.statusCode, "HTTP \(http.statusCode)")
        }

        let json = try JSON.object(from: data)
        let windows = parseWindows(json)
        if windows.isEmpty {
            throw UsageError.parse("使用量データが含まれていません")
        }
        let plan = JSON.string(json["plan_type"])?.capitalized
        return ProviderResult(windows: windows, plan: plan, note: nil)
    }

    // MARK: Parsing

    static func parseWindows(_ json: [String: Any]) -> [UsageWindow] {
        var result: [UsageWindow] = []

        let main = (json["rate_limit"] as? [String: Any]) ?? json
        result.append(contentsOf: windows(from: main, idPrefix: "codex.main", labelPrefix: nil))

        // Per-model limits (e.g. GPT-5.x-Codex-Spark) live in additional_rate_limits[].
        if let extras = json["additional_rate_limits"] as? [[String: Any]] {
            for (i, extra) in extras.enumerated() {
                let name = JSON.string(extra["limit_name"])
                    ?? JSON.string(extra["name"])
                    ?? JSON.string(extra["model"])
                    ?? "追加制限 \(i + 1)"
                let container = (extra["rate_limit"] as? [String: Any]) ?? extra
                result.append(contentsOf: windows(from: container, idPrefix: "codex.extra\(i)", labelPrefix: name))
            }
        }
        return result
    }

    private static func windows(from dict: [String: Any], idPrefix: String, labelPrefix: String?) -> [UsageWindow] {
        var out: [UsageWindow] = []
        let slots: [(String, String)] = [("primary_window", "制限 1"), ("secondary_window", "制限 2")]
        for (key, fallbackLabel) in slots {
            guard let w = dict[key] as? [String: Any] else { continue }
            guard let used = JSON.number(w["used_percent"]) else { continue }
            let seconds = JSON.number(w["limit_window_seconds"])
                ?? JSON.number(w["window_minutes"]).map { $0 * 60 }
            var label = Format.windowLabel(seconds: seconds) ?? fallbackLabel
            if let p = labelPrefix { label = "\(label) · \(p)" }

            var reset = JSON.date(w["reset_at"]) ?? JSON.date(w["resets_at"])
            if reset == nil, let after = JSON.number(w["reset_after_seconds"]) ?? JSON.number(w["resets_in_seconds"]) {
                reset = Date().addingTimeInterval(after)
            }
            out.append(UsageWindow(id: "\(idPrefix).\(key)", label: label, usedPercent: used, resetsAt: reset))
        }
        return out
    }

    // MARK: Credentials

    static func codexHome() -> URL {
        let env = ProcessInfo.processInfo.environment
        if let dir = env["CODEX_HOME"], !dir.isEmpty {
            return URL(fileURLWithPath: dir)
        }
        return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex")
    }

    static func loadCredentials() throws -> Credentials {
        let url = codexHome().appendingPathComponent("auth.json")
        guard let data = try? Data(contentsOf: url), let root = try? JSON.object(from: data) else {
            throw UsageError.noCredentials("Codex の認証情報が見つかりません。ターミナルで codex login してください")
        }
        let tokens = (root["tokens"] as? [String: Any]) ?? [:]
        guard let token = JSON.string(tokens["access_token"]), !token.isEmpty else {
            throw UsageError.noCredentials("Codex は ChatGPT アカウントでのログインが必要です（codex login）")
        }
        return Credentials(accessToken: token, accountID: JSON.string(tokens["account_id"]))
    }

    // MARK: Session-log fallback

    enum SessionLog {
        /// Scans the newest session files for the last `rate_limits` event.
        static func latest() -> ProviderResult? {
            let root = codexHome().appendingPathComponent("sessions")
            let fm = FileManager.default
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { return nil }

            var files: [(URL, Date)] = []
            for case let url as URL in enumerator {
                guard url.pathExtension == "jsonl" else { continue }
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
                guard values?.isRegularFile == true else { continue }
                files.append((url, values?.contentModificationDate ?? .distantPast))
            }
            files.sort { $0.1 > $1.1 }

            for (url, _) in files.prefix(5) {
                if let r = parseFile(url) { return r }
            }
            return nil
        }

        private static func parseFile(_ url: URL) -> ProviderResult? {
            guard let text = tail(of: url, bytes: 2_000_000) else { return nil }
            let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
            for line in lines.reversed() {
                guard line.contains("rate_limits") else { continue }
                guard let data = line.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                let payload = (obj["payload"] as? [String: Any]) ?? obj
                guard let limits = payload["rate_limits"] as? [String: Any] else { continue }
                let stamp = JSON.date(obj["timestamp"]) ?? Date()
                let windows = parseLimits(limits, at: stamp)
                if !windows.isEmpty {
                    return ProviderResult(windows: windows, plan: nil, note: "記録時刻 \(Format.clock.string(from: stamp))")
                }
            }
            return nil
        }

        private static func parseLimits(_ limits: [String: Any], at stamp: Date) -> [UsageWindow] {
            var out: [UsageWindow] = []
            let slots: [(String, String)] = [("primary", "制限 1"), ("secondary", "制限 2")]
            for (key, fallbackLabel) in slots {
                guard let w = limits[key] as? [String: Any],
                      let used = JSON.number(w["used_percent"]) else { continue }
                let seconds = JSON.number(w["window_minutes"]).map { $0 * 60 }
                    ?? JSON.number(w["limit_window_seconds"])
                let label = Format.windowLabel(seconds: seconds) ?? fallbackLabel
                var reset = JSON.date(w["resets_at"]) ?? JSON.date(w["reset_at"])
                if reset == nil, let after = JSON.number(w["resets_in_seconds"]) {
                    reset = stamp.addingTimeInterval(after)
                }
                out.append(UsageWindow(id: "codex.log.\(key)", label: label, usedPercent: used, resetsAt: reset))
            }
            return out
        }

        /// Reads at most `bytes` from the end of the file.
        private static func tail(of url: URL, bytes: UInt64) -> String? {
            guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
            defer { try? handle.close() }
            guard let size = try? handle.seekToEnd() else { return nil }
            let start = size > bytes ? size - bytes : 0
            guard (try? handle.seek(toOffset: start)) != nil,
                  let data = try? handle.readToEnd() else { return nil }
            return String(decoding: data, as: UTF8.self)
        }
    }
}
