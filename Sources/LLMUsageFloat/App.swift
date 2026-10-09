import AppKit

@main
struct LLMUsageFloatApp {
    // NSApplication.delegate is weak, so keep a strong reference here.
    @MainActor private static var delegate: AppDelegate?

    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        Self.delegate = delegate
        app.delegate = delegate
        app.run()
    }
}
