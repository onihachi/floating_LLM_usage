import Foundation
import Combine

/// How the floating panel sits in the window stack.
enum WindowMode: String, CaseIterable {
    /// Pinned to the desktop: above the Finder desktop icons, below every normal window.
    case desktop
    /// Behaves like an ordinary window.
    case normal
    /// Always on top of other windows.
    case floating

    var label: String {
        switch self {
        case .desktop: return "デスクトップに固定"
        case .normal: return "通常のウィンドウ"
        case .floating: return "常に最前面"
        }
    }
}

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
        static let windowMode = "windowMode"
        static let expandedWindows = "expandedWindows"
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
    @Published var windowMode: WindowMode {
        didSet { defaults.set(windowMode.rawValue, forKey: Keys.windowMode) }
    }
    /// IDs of usage windows shown expanded (full bar + reset time). Every
    /// window is a single compact line by default.
    @Published var expandedWindows: Set<String> {
        didSet { defaults.set(Array(expandedWindows).sorted(), forKey: Keys.expandedWindows) }
    }

    func toggleExpanded(_ id: String) {
        if expandedWindows.contains(id) {
            expandedWindows.remove(id)
        } else {
            expandedWindows.insert(id)
        }
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
        let storedMode = d.string(forKey: Keys.windowMode)
        windowMode = storedMode.flatMap(WindowMode.init(rawValue:)) ?? .desktop
        expandedWindows = Set((d.array(forKey: Keys.expandedWindows) as? [String]) ?? [])
    }
}
