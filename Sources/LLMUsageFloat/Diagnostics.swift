import Foundation
import Security

/// `LLMUsageFloat --dump`: prints which credential source worked and the raw
/// usage responses, so API changes can be diagnosed from a terminal.
/// Tokens and credential contents are never printed.
enum Diagnostics {
    static func run() async {
        let info = Bundle.main.infoDictionary ?? [:]
        print("LLMUsageFloat \(info["CFBundleShortVersionString"] ?? "?") (\(info["CFBundleVersion"] ?? "?"))")
        print("== Claude Code ==")
        print("config dir: \(ClaudeProvider.configDirectory())")
        print("claude CLI: \(ClaudeProvider.CLIRefresh.claudeExecutable() ?? "not found")")
        for service in ClaudeProvider.keychainServiceNames() {
            var status: OSStatus = errSecSuccess
            let kc = ClaudeProvider.readKeychain(service: service, status: &status)
            let kcMsg = (SecCopyErrorMessageString(status, nil) as String?) ?? ""
            let kcParsed = kc.map { ClaudeProvider.parseCredentials($0) != nil } ?? false
            print("keychain '\(service)': status \(status) (\(kcMsg)), readable: \(kc != nil), parsed: \(kcParsed)")
            if kc != nil { print("  attrs: " + keychainAttributes(service: service)) }
            if let kc, !kcParsed { print("  shape: " + shape(of: kc)) }
        }
        let fileURL = ClaudeProvider.credentialsFileURL()
        let file = ClaudeProvider.readCredentialsFile()
        let fileParsed = file.map { ClaudeProvider.parseCredentials($0) != nil } ?? false
        print("file \(fileURL.path): readable: \(file != nil), parsed: \(fileParsed)")
        if let file, !fileParsed { print("  shape: " + shape(of: file)) }
        do {
            let creds = try ClaudeProvider.loadCredentials()
            print("credentials: ok, expiresAt \(creds.expiresAt.map { "\($0)" } ?? "nil"), plan \(creds.subscriptionType ?? "nil")")
            let (http, data) = try await ClaudeProvider.request(creds)
            print("HTTP \(http.statusCode)")
            print(prettyJSON(data))
            if http.statusCode == 200, let json = try? JSON.object(from: data) {
                print("parsed windows:", describe(ClaudeProvider.parseWindows(json)))
            }
        } catch {
            print("error: \(error.localizedDescription)")
        }

        print("\n== Codex ==")
        print("home: \(CodexProvider.codexHome().path)")
        do {
            let creds = try CodexProvider.loadCredentials()
            print("credentials: ok, accountID \(creds.accountID == nil ? "nil" : "set")")
            let (http, data) = try await CodexProvider.request(creds)
            print("HTTP \(http.statusCode)")
            print(prettyJSON(data))
            if http.statusCode == 200, let json = try? JSON.object(from: data) {
                print("parsed windows:", describe(CodexProvider.parseWindows(json)))
            }
        } catch {
            print("error: \(error.localizedDescription)")
        }
        if let log = CodexProvider.SessionLog.latest() {
            print("session-log fallback:", describe(log.windows), log.note ?? "")
        } else {
            print("session-log fallback: none")
        }
    }

    /// Non-secret metadata of a keychain item: account, label, dates.
    private static func keychainAttributes(service: String) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let items = item as? [[String: Any]] else { return "(no attributes)" }
        return items.map { a in
            "account=\(a[kSecAttrAccount as String] ?? "-") label=\(a[kSecAttrLabel as String] ?? "-") created=\(a[kSecAttrCreationDate as String] ?? "-") modified=\(a[kSecAttrModificationDate as String] ?? "-")"
        }.joined(separator: " || ")
    }

    /// Describes the structure of a credential blob without revealing any value:
    /// key names and value types/lengths only.
    private static func shape(of data: Data) -> String {
        if let obj = try? JSONSerialization.jsonObject(with: data) {
            func walk(_ any: Any) -> String {
                if let d = any as? [String: Any] {
                    return "{" + d.keys.sorted().map { "\($0): \(walk(d[$0]!))" }.joined(separator: ", ") + "}"
                }
                if let a = any as? [Any] { return "array(\(a.count))" }
                if let s = any as? String { return "string(\(s.count))" }
                if any is NSNull { return "null" }
                return "\(type(of: any))"
            }
            return walk(obj)
        }
        // Byte-class summary only (no content): helps identify an unknown encoding.
        let bytes = [UInt8](data)
        let control = bytes.filter { $0 < 0x20 && $0 != 0x0A && $0 != 0x0D && $0 != 0x09 }.count
        let high = bytes.filter { $0 > 0x7E }.count
        let printable = bytes.count - control - high
        // Only the first (format/version) byte, never a run of content bytes.
        let header = bytes.first.map { String(format: "0x%02x", $0) } ?? "-"
        let firstBrace = bytes.firstIndex(of: 0x7B)
        let lastBrace = bytes.lastIndex(of: 0x7D)
        var embedded = "none"
        if let a = firstBrace, let b = lastBrace, a < b {
            let slice = data.subdata(in: a..<(b + 1))
            if let obj = try? JSONSerialization.jsonObject(with: slice) as? [String: Any] {
                embedded = "JSON at \(a)..<\(b + 1) keys: \(obj.keys.sorted())"
            } else {
                embedded = "braces at \(a)/\(b) but not JSON"
            }
        }
        let base64Chars = bytes.filter { b in
            (0x30...0x39).contains(b) || (0x41...0x5A).contains(b) || (0x61...0x7A).contains(b) || b == 0x2B || b == 0x2F || b == 0x3D
        }.count
        // Marker positions and value lengths only.
        let text = String(decoding: data, as: UTF8.self)
        var markers: [String] = []
        for key in ["\"claudeAiOauth\"", "\"accessToken\"", "\"refreshToken\"", "\"expiresAt\"", "\"subscriptionType\"", "\"mcpOAuth\""] {
            let ranges = text.ranges(of: key)
            let positions = ranges.map { text.distance(from: text.startIndex, to: $0.lowerBound) }
            markers.append("\(key)@\(positions)")
        }
        var tokenLens: [Int] = []
        for r in text.ranges(of: "\"accessToken\":\"") {
            let rest = text[r.upperBound...]
            if let end = rest.firstIndex(of: "\"") { tokenLens.append(rest.distance(from: rest.startIndex, to: end)) }
        }
        var expires: [String] = []
        for r in text.ranges(of: "\"expiresAt\":") {
            let rest = text[r.upperBound...].prefix(16)
            let digits = rest.prefix { $0.isNumber }
            if let n = Double(digits) {
                let d = n > 1_000_000_000_000 ? Date(timeIntervalSince1970: n / 1000) : Date(timeIntervalSince1970: n)
                expires.append("\(d) (\(d > Date() ? "valid" : "expired"))")
            }
        }
        let tailStart = min(bytes.count, lastBrace.map { $0 + 1 } ?? bytes.count)
        let tail = bytes[tailStart...]
        let tailDesc = "tail \(tail.count) bytes, quotes \(tail.filter { $0 == 0x22 }.count), colons \(tail.filter { $0 == 0x3A }.count), commas \(tail.filter { $0 == 0x2C }.count)"
        return "not JSON: \(data.count) bytes, printable \(printable), control \(control), >0x7E \(high), base64-charset \(base64Chars), header: \(header), embedded: \(embedded); markers \(markers.joined(separator: " ")); accessToken value lengths \(tokenLens); expiresAt \(expires); \(tailDesc)"
    }

    private static func describe(_ windows: [UsageWindow]) -> String {
        windows.map { w in
            "\(w.label)=\(w.usedPercent)% reset \(w.resetsAt.map { "\($0)" } ?? "nil")"
        }.joined(separator: " | ")
    }

    private static func prettyJSON(_ data: Data) -> String {
        guard let obj = try? JSONSerialization.jsonObject(with: data),
              let out = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let s = String(data: out, encoding: .utf8) else {
            return String(decoding: data.prefix(2000), as: UTF8.self)
        }
        return s
    }
}
