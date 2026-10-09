import AppKit

@main
struct LLMUsageFloatApp {
    // NSApplication.delegate is weak, so keep a strong reference here.
    @MainActor private static var delegate: AppDelegate?

    @MainActor
    static func main() {
        if CommandLine.arguments.contains("--dump") {
            let sem = DispatchSemaphore(value: 0)
            Task.detached {
                await Diagnostics.run()
                sem.signal()
            }
            sem.wait()
            exit(0)
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        Self.delegate = delegate
        app.delegate = delegate
        app.run()
    }
}
