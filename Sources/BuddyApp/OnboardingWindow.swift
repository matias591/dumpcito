import AppKit
import BuddyCore
import BuddyUI
import SwiftUI

/// The first-run walkthrough, in a plain window. Closing it counts as finishing.
@MainActor
final class OnboardingWindow: NSWindow, NSWindowDelegate {
    /// Called once when the window goes away; `true` only if the user reached the end and pressed Start.
    private let onFinish: (Bool) -> Void
    private var finished = false

    init(settings: BuddySettings, actions: OnboardingActions, onFinish: @escaping (Bool) -> Void) {
        self.onFinish = onFinish
        super.init(contentRect: NSRect(origin: .zero, size: OnboardingView.size),
                   styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        var wrapped = actions
        let finish = actions.finish
        wrapped.finish = { [weak self] in finish(); self?.complete() }
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        contentViewController = NSHostingController(rootView: OnboardingView(settings: settings, actions: wrapped))
        delegate = self
        center()
    }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

    private func complete() {
        guard !finished else { return }
        finished = true
        onFinish(true)
        close()
    }

    func windowWillClose(_ notification: Notification) {
        guard !finished else { return }
        finished = true
        onFinish(false)
    }
}
