import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var panel: FloatingPanel?
    private var statusItem: NSStatusItem?
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private let store = UsageStore()
    private let settings = Settings.shared

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let rootView = UsageView(store: store, settings: settings, onQuit: {
            NSApp.terminate(nil)
        })
        let panel = FloatingPanel(rootView: rootView, mode: settings.windowMode)
        panel.alphaValue = settings.opacity
        panel.orderFrontRegardless()
        self.panel = panel

        setupStatusItem()
        bindSettings()

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        store.refreshAll()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @objc private func didWake() {
        // Give the network a moment to come back after sleep.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            Task { @MainActor in
                self?.store.refreshAll()
            }
        }
    }

    // MARK: Settings bindings

    private func bindSettings() {
        settings.$opacity
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                Task { @MainActor in
                    self?.panel?.alphaValue = value
                }
            }
            .store(in: &cancellables)

        settings.$refreshInterval
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] interval in
                Task { @MainActor in
                    self?.scheduleTimer(interval: interval)
                }
            }
            .store(in: &cancellables)

        settings.$windowMode
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] mode in
                Task { @MainActor in
                    guard let panel = self?.panel else { return }
                    panel.apply(mode: mode)
                    // Leaving desktop mode: surface the panel so the change is visible.
                    if mode != .desktop, panel.isVisible {
                        panel.orderFrontRegardless()
                    }
                }
            }
            .store(in: &cancellables)

        store.$claude
            .combineLatest(store.$codex)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.updateStatusTitle()
                }
            }
            .store(in: &cancellables)
    }

    private func scheduleTimer(interval: TimeInterval) {
        timer?.invalidate()
        let t = Timer.scheduledTimer(withTimeInterval: max(30, interval), repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.store.refreshAll()
            }
        }
        t.tolerance = min(15, interval / 10)
        timer = t
    }

    // MARK: Status bar item

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "gauge.with.dots.needle.33percent", accessibilityDescription: "LLM Usage")
                ?? NSImage(systemSymbolName: "gauge", accessibilityDescription: "LLM Usage")
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageLeading
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        updateStatusTitle()
    }

    /// Shows the shortest window of each provider in the menu bar, e.g. "C 42% · X 13%".
    private func updateStatusTitle() {
        var parts: [String] = []
        if settings.showClaude, let w = store.claude.windows.first {
            parts.append("C \(Int(w.clampedPercent.rounded()))%")
        }
        if settings.showCodex, let w = store.codex.windows.first {
            parts.append("X \(Int(w.clampedPercent.rounded()))%")
        }
        let title = parts.joined(separator: " · ")
        statusItem?.button?.title = title.isEmpty ? "" : " " + title
        statusItem?.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    }

    // Rebuild the menu on every open so check marks reflect current settings.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let visible = panel?.isVisible ?? false
        menu.addItem(makeItem(visible ? "ウィンドウを隠す" : "ウィンドウを表示", action: #selector(togglePanel)))
        menu.addItem(makeItem("今すぐ更新", action: #selector(refreshNow), key: "r"))
        menu.addItem(.separator())

        let opacityMenu = NSMenu()
        for value in Settings.opacityOptions {
            let item = makeItem("\(Int((value * 100).rounded()))%", action: #selector(setOpacity(_:)))
            item.representedObject = value
            item.state = abs(settings.opacity - value) < 0.001 ? .on : .off
            opacityMenu.addItem(item)
        }
        let opacityItem = NSMenuItem(title: "不透明度", action: nil, keyEquivalent: "")
        opacityItem.submenu = opacityMenu
        menu.addItem(opacityItem)

        let intervalMenu = NSMenu()
        for option in Settings.intervalOptions {
            let item = makeItem(option.label, action: #selector(setInterval(_:)))
            item.representedObject = option.seconds
            item.state = abs(settings.refreshInterval - option.seconds) < 0.5 ? .on : .off
            intervalMenu.addItem(item)
        }
        let intervalItem = NSMenuItem(title: "更新間隔", action: nil, keyEquivalent: "")
        intervalItem.submenu = intervalMenu
        menu.addItem(intervalItem)

        let modeMenu = NSMenu()
        for mode in WindowMode.allCases {
            let item = makeItem(mode.label, action: #selector(setWindowMode(_:)))
            item.representedObject = mode.rawValue
            item.state = settings.windowMode == mode ? .on : .off
            modeMenu.addItem(item)
        }
        let modeItem = NSMenuItem(title: "表示モード", action: nil, keyEquivalent: "")
        modeItem.submenu = modeMenu
        menu.addItem(modeItem)

        let cornerMenu = NSMenu()
        for corner in PanelCorner.allCases {
            let item = makeItem(corner.label, action: #selector(snapToCorner(_:)))
            item.representedObject = corner.rawValue
            cornerMenu.addItem(item)
        }
        let cornerItem = NSMenuItem(title: "位置", action: nil, keyEquivalent: "")
        cornerItem.submenu = cornerMenu
        menu.addItem(cornerItem)

        menu.addItem(.separator())

        let claudeItem = makeItem("Claude Code を表示", action: #selector(toggleClaude))
        claudeItem.state = settings.showClaude ? .on : .off
        menu.addItem(claudeItem)

        let codexItem = makeItem("Codex を表示", action: #selector(toggleCodex))
        codexItem.state = settings.showCodex ? .on : .off
        menu.addItem(codexItem)

        menu.addItem(.separator())
        menu.addItem(makeItem("終了", action: #selector(quit), key: "q"))
    }

    private func makeItem(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    // MARK: Menu actions

    @objc private func togglePanel() {
        guard let panel = panel else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    @objc private func refreshNow() {
        store.refreshAll(force: true)
    }

    @objc private func setOpacity(_ sender: NSMenuItem) {
        if let value = sender.representedObject as? Double {
            settings.opacity = value
        }
    }

    @objc private func setInterval(_ sender: NSMenuItem) {
        if let value = sender.representedObject as? Double {
            settings.refreshInterval = value
        }
    }

    @objc private func snapToCorner(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let corner = PanelCorner(rawValue: raw) {
            panel?.snap(to: corner)
            panel?.orderFrontRegardless()
        }
    }

    @objc private func setWindowMode(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let mode = WindowMode(rawValue: raw) {
            settings.windowMode = mode
        }
    }

    @objc private func toggleClaude() {
        settings.showClaude.toggle()
        updateStatusTitle()
    }

    @objc private func toggleCodex() {
        settings.showCodex.toggle()
        updateStatusTitle()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
