import Foundation

/// One rate-limit window (e.g. "5 hours", "7 days") for a provider.
struct UsageWindow: Identifiable, Equatable {
    let id: String
    let label: String
    /// 0...100
    let usedPercent: Double
    let resetsAt: Date?

    var clampedPercent: Double { min(100, max(0, usedPercent)) }
}

/// What a provider returns on a successful fetch.
struct ProviderResult {
    var windows: [UsageWindow]
    var plan: String?
    /// Short note shown under the section (e.g. "セッションログから取得").
    var note: String?
}

/// Display state for one provider section.
struct ProviderStatus: Equatable {
    var windows: [UsageWindow] = []
    var plan: String? = nil
    var note: String? = nil
    var errorMessage: String? = nil
    var updatedAt: Date? = nil
    var isLoading: Bool = false
}

enum UsageError: LocalizedError {
    case noCredentials(String)
    case http(Int, String)
    case parse(String)
    case other(String)

    var errorDescription: String? {
        switch self {
        case .noCredentials(let m): return m
        case .http(_, let m): return m
        case .parse(let m): return m
        case .other(let m): return m
        }
    }
}

// MARK: - JSON helpers (JSONSerialization based, schema-tolerant)

enum JSON {
    static func object(from data: Data) throws -> [String: Any] {
        let any = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dict = any as? [String: Any] else {
            throw UsageError.parse("JSON の形式が想定と異なります")
        }
        return dict
    }

    static func number(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let n = any as? NSNumber { return n.doubleValue }
        if let s = any as? String, let d = Double(s) { return d }
        return nil
    }

    static func string(_ any: Any?) -> String? {
        if let s = any as? String { return s }
        return nil
    }

    /// Accepts ISO-8601 strings (with or without fractional seconds) and
    /// Unix timestamps in seconds or milliseconds.
    static func date(_ any: Any?) -> Date? {
        if let s = any as? String {
            if let d = isoFractional.date(from: s) { return d }
            if let d = isoPlain.date(from: s) { return d }
            if let n = Double(s) { return date(n) }
            return nil
        }
        if let n = number(any) { return date(n) }
        return nil
    }

    private static func date(_ n: Double) -> Date? {
        guard n > 0 else { return nil }
        // Anything above ~year 2286 in seconds is almost certainly milliseconds.
        if n > 1_000_000_000_000 { return Date(timeIntervalSince1970: n / 1000) }
        return Date(timeIntervalSince1970: n)
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}

// MARK: - Shared formatting

enum Format {
    static let clock: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = "M/d HH:mm"
        return f
    }()

    static let timeOnly: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = "HH:mm"
        return f
    }()

    static func remaining(until date: Date, from now: Date = Date()) -> String {
        let secs = Int(date.timeIntervalSince(now))
        if secs <= 0 { return "まもなくリセット" }
        let days = secs / 86_400
        let hours = (secs % 86_400) / 3_600
        let mins = (secs % 3_600) / 60
        if days > 0 { return "あと\(days)日\(hours)時間" }
        if hours > 0 { return "あと\(hours)時間\(mins)分" }
        return "あと\(mins)分"
    }

    /// Human label for a window length given in seconds.
    static func windowLabel(seconds: Double?) -> String? {
        guard let s = seconds, s > 0 else { return nil }
        let hours = s / 3600
        if hours <= 6 { return "5時間" }
        if hours >= 6 * 24 && hours <= 8 * 24 { return "7日間" }
        if hours < 48 { return "\(Int(hours.rounded()))時間" }
        return "\(Int((hours / 24).rounded()))日間"
    }
}
