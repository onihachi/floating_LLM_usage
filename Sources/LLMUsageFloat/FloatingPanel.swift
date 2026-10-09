import AppKit
import SwiftUI

/// Borderless, always-on-top, click-through-free translucent panel.
final class FloatingPanel: NSPanel {
    private static let autosaveName = "LLMUsageFloat.Panel"

    init<Content: View>(rootView: Content) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 240),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .utilityWindow
        isReleasedWhenClosed = false

        // NSHostingController resizes the window to the SwiftUI content's ideal size.
        let controller = NSHostingController(rootView: rootView)
        contentViewController = controller

        setFrameAutosaveName(Self.autosaveName)
        if !setFrameUsingName(Self.autosaveName) {
            placeInTopRightCorner()
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    private func placeInTopRightCorner() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.maxX - frame.width - 24,
            y: visible.maxY - frame.height - 24
        )
        setFrameOrigin(origin)
    }
}
