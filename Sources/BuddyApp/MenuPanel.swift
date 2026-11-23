import AppKit
import BuddyCore
import BuddyUI
import SwiftUI

/// Hosts BuddyMenuView in a borderless floating panel beside the buddy (or under the menu bar icon).
/// Closes on any click outside, Esc, or when the app loses focus.
@MainActor
final class MenuPanel: NSPanel {
    private var monitors: [Any] = []
    private let hosting: NSHostingController<AnyView>

    init(settings: BuddySettings) {
        let box = DismissBox()
        hosting = NSHostingController(rootView: AnyView(BuddyMenuView(settings: settings, dismiss: { box.dismiss() })))
        super.init(contentRect: NSRect(x: 0, y: 0, width: 320, height: 400),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        box.dismiss = { [weak self] in self?.close() }
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        contentViewController = hosting
    }

    override var canBecomeKey: Bool { true }

    var isShown: Bool { isVisible }

    /// Opens next to `anchor` (screen coordinates), on the side facing the middle of its display.
    func show(near anchor: NSRect) {
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
        guard let vis = screen?.visibleFrame else { return }
        hosting.view.layoutSubtreeIfNeeded()
        let size = hosting.view.fittingSize
        let pad: CGFloat = 4
        var x = anchor.midX < vis.midX ? anchor.maxX + pad : anchor.minX - size.width - pad
        var y = anchor.midY < vis.midY ? anchor.minY : anchor.maxY - size.height
        x = min(max(x, vis.minX), vis.maxX - size.width)
        y = min(max(y, vis.minY), vis.maxY - size.height)
        setFrame(NSRect(origin: NSPoint(x: x, y: y), size: size), display: true)
        orderFrontRegardless()
        makeKey()
        startMonitors()
    }

    private var closedAt = Date.distantPast
    /// True right after an outside click closed the menu, so the same click on the menu bar icon or the buddy
    /// does not immediately reopen it.
    var justClosed: Bool { Date().timeIntervalSince(closedAt) < 0.3 }

    override func close() {
        closedAt = Date()
        stopMonitors()
        super.close()
    }

    override func resignKey() {
        super.resignKey()
        close()
    }

    private func startMonitors() {
        stopMonitors()
        let outside = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, event.keyCode == 53 { self.close(); return nil }
            if event.type != .keyDown, event.window !== self { self.close() }
            return event
        }
        monitors = [outside, local].compactMap { $0 }
    }

    private func stopMonitors() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
    }
}

private final class DismissBox { var dismiss: () -> Void = {} }
