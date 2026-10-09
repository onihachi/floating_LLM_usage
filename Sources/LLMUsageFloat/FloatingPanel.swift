import AppKit
import SwiftUI

/// Borderless, click-through-free translucent panel. Level and Spaces behavior follow `WindowMode`.
final class FloatingPanel: NSPanel {
    private static let autosaveName = "LLMUsageFloat.Panel"

    init<Content: View>(rootView: Content, mode: WindowMode) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 240),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        // Must run after `isFloatingPanel = true`, which sets the level to .floating.
        apply(mode: mode)
        isOpaque = false
        backgroundColor = .clear
        // Dragging is driven explicitly by the SwiftUI content (see below).
        isMovableByWindowBackground = false
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

    /// Applies the window level, Spaces behavior and shadow for the given display mode.
    func apply(mode: WindowMode) {
        switch mode {
        case .desktop:
            // Just above the Finder desktop icons, below every normal window.
            level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
            collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            hasShadow = false
        case .normal:
            level = .normal
            collectionBehavior = [.canJoinAllSpaces, .stationary]
            hasShadow = true
        case .floating:
            level = .floating
            collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            hasShadow = true
        }
        invalidateShadow()
    }

    private func placeInTopRightCorner() {
        snap(to: .topRight)
    }

    /// Moves the panel to a screen corner (used from the menus, handy when the
    /// panel sits on the desktop and cannot be reached with the mouse).
    func snap(to corner: PanelCorner) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let margin: CGFloat = 24
        let x = corner.isLeft ? visible.minX + margin : visible.maxX - frame.width - margin
        let y = corner.isTop ? visible.maxY - frame.height - margin : visible.minY + margin
        setFrameOrigin(NSPoint(x: x, y: y))
        saveFrame(usingName: Self.autosaveName)
    }

    // MARK: Manual dragging
    //
    // `isMovableByWindowBackground` does not work reliably once the content is a
    // SwiftUI hierarchy with buttons and a context menu, so the view drives the
    // move explicitly: `beginDrag()` at the first drag event, `continueDrag()`
    // on every change, `endDrag()` to persist the frame.

    private var dragStartMouse: NSPoint?
    private var dragStartOrigin: NSPoint?

    /// - Parameter translationSoFar: the gesture's translation at recognition
    ///   time (SwiftUI, y down). Subtracting it recovers the exact mouse-down
    ///   point, so the window tracks the cursor 1:1 instead of lagging by the
    ///   recognition threshold.
    func beginDrag(translationSoFar: CGSize = .zero) {
        let mouse = NSEvent.mouseLocation
        dragStartMouse = NSPoint(x: mouse.x - translationSoFar.width, y: mouse.y + translationSoFar.height)
        dragStartOrigin = frame.origin
    }

    func continueDrag() {
        guard let startMouse = dragStartMouse, let startOrigin = dragStartOrigin else {
            beginDrag()
            return
        }
        let now = NSEvent.mouseLocation
        setFrameOrigin(NSPoint(x: startOrigin.x + (now.x - startMouse.x), y: startOrigin.y + (now.y - startMouse.y)))
    }

    func endDrag() {
        dragStartMouse = nil
        dragStartOrigin = nil
        saveFrame(usingName: Self.autosaveName)
    }

    /// The panel instance owned by the app (there is only one).
    static var current: FloatingPanel? {
        NSApp.windows.lazy.compactMap { $0 as? FloatingPanel }.first
    }
}

enum PanelCorner: String, CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight

    var isLeft: Bool { self == .topLeft || self == .bottomLeft }
    var isTop: Bool { self == .topLeft || self == .topRight }

    var label: String {
        switch self {
        case .topLeft: return "左上"
        case .topRight: return "右上"
        case .bottomLeft: return "左下"
        case .bottomRight: return "右下"
        }
    }
}
