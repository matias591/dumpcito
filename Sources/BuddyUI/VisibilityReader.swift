import AppKit
import SwiftUI

/// Reports whether the hosting window is actually visible on screen (not ordered out,
/// not fully covered, display not asleep). Looping animations stop when it is not.
struct WindowVisibilityReader: NSViewRepresentable {
    var onChange: (Bool) -> Void

    func makeNSView(context: Context) -> VisibilityProbeView {
        let view = VisibilityProbeView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: VisibilityProbeView, context: Context) {
        view.onChange = onChange
    }
}

final class VisibilityProbeView: NSView {
    var onChange: ((Bool) -> Void)?
    private weak var observedWindow: NSWindow?
    private var lastReported: Bool?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let center = NotificationCenter.default
        if let old = observedWindow {
            center.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: old)
        }
        observedWindow = window
        guard let window else { return }
        center.addObserver(self, selector: #selector(occlusionChanged(_:)),
                           name: NSWindow.didChangeOcclusionStateNotification, object: window)
        report()
    }

    @objc private func occlusionChanged(_ note: Notification) {
        report()
    }

    private func report() {
        guard let window else { return }
        let visible = window.occlusionState.contains(.visible)
        guard visible != lastReported else { return }
        lastReported = visible
        // Defer: never mutate SwiftUI state during a view update.
        DispatchQueue.main.async { [weak self] in self?.onChange?(visible) }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
