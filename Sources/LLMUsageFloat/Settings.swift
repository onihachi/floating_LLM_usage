import Foundation
import Combine

/// User-tunable settings persisted in UserDefaults.
@MainActor
final class Settings: ObservableObject {
    static let shared = Settings()

    static let opacityOptions: [Double] = [0.5, 0.65, 0.8, 0.9, 1.0]
    static let intervalOptions: [(label: String, seconds: TimeInterval)] = [
        ("1分", 60),
        ("3分", 180),
        ("5分", 300),
        ("10分", 600),
        ("30分", 1800),
    ]

    private enum Keys {
        static let opacity = "opacity"
        static let refreshInterval = "refreshInterval"
        static let showClaude = "showClaude"
        static let showCodex = "showCodex"
    }

    @Published var opacity: Double {
        didSet { defaults.set(opacity, forKey: Keys.opacity) }
    }
    @Published var refreshInterval: TimeInterval {
        didSet { defaults.set(refreshInterval, forKey: Keys.refreshInterval) }
    }
    @Published var showClaude: Bool {
        didSet { defaults.set(showClaude, forKey: Keys.showClaude) }
    }
    @Published var showCodex: Bool {
        didSet { defaults.set(showCodex, forKey: Keys.showCodex) }
    }

    private let defaults = UserDefaults.standard

    private init() {
        let d = UserDefaults.standard
        let storedOpacity = d.object(forKey: Keys.opacity) as? Double
        opacity = storedOpacity ?? 0.8
        let storedInterval = d.object(forKey: Keys.refreshInterval) as? Double
        refreshInterval = storedInterval ?? 300
        showClaude = (d.object(forKey: Keys.showClaude) as? Bool) ?? true
        showCodex = (d.object(forKey: Keys.showCodex) as? Bool) ?? true
    }
}
