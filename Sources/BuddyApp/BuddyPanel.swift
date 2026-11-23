import AppKit
import SwiftUI

/// Borderless, non-activating floating panel. Never steals focus from the frontmost app
/// (VS Code) unless a text field inside it is clicked.
final class BuddyPanel: NSPanel {
    /// Windows no bigger than this are the collapsed character; only then is the screen quadrant re-evaluated.
    private static let collapsedLimit: CGFloat = 100
    private static let dragThreshold: CGFloat = 4

    private var hosting: NSHostingController<AnyView>?
    private var sizeObservation: NSKeyValueObservation?
    private var isRestoring = false
    /// The frame we last placed. AppKit resizes the window itself (top-left fixed) before our handlers run,
    /// so growth is always anchored against this, not against the current frame.
    private var anchorFrame: NSRect?

    private(set) var anchorTop = false
    private(set) var anchorLeading = false
    /// Called with (top, leading) whenever the panel settles in a different screen quadrant. Fires once on assignment.
    var onAnchorChange: ((Bool, Bool) -> Void)? {
        didSet { onAnchorChange?(anchorTop, anchorLeading) }
    }

    /// False while the follower moves the panel (hop/chase), so those positions never overwrite the saved home.
    private var persistsMoves = true
    /// Home position as a fraction of its display's visible frame, used to pick a home on displays never visited.
    private var homeFraction = CGPoint(x: 1, y: 0)

    // Manual drag: SwiftUI-drawn content does not take part in AppKit's drag-by-background.
    private var pendingDown: NSEvent?
    private var dragStartMouse: NSPoint?
    private var dragStartOrigin: NSPoint?
    private var isDragging = false

    init<Content: View>(rootView: Content) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 120, height: 120),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        worksWhenModal = true

        let controller = NSHostingController(rootView: AnyView(rootView))
        controller.sizingOptions = [.preferredContentSize]
        controller.view.wantsLayer = true
        controller.view.layer?.backgroundColor = NSColor.clear.cgColor
        contentViewController = controller
        hosting = controller

        // Resize the window whenever SwiftUI's preferred size changes.
        sizeObservation = controller.observe(\.preferredContentSize, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.applyPreferredSize() }
        }

        NotificationCenter.default.addObserver(self, selector: #selector(didResizeNotification),
                                               name: NSWindow.didResizeNotification, object: self)
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        applyPreferredSize(initial: true)
    }

    // Can become key only when a control (the compose field) needs it.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // MARK: Dragging

    /// Right-click / ctrl-click on the buddy: opens the buddy's menu, reachable even if the menu bar icon is hidden.
    var onSecondaryClick: (() -> Void)?

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .rightMouseDown:
            if let open = onSecondaryClick { open() } else { super.sendEvent(event) }
        case .leftMouseDown where event.modifierFlags.contains(.control):
            if let open = onSecondaryClick { open() } else { super.sendEvent(event) }
        case .leftMouseDown:
            // Real AppKit controls (the compose field, the target pop-up) get their events untouched.
            if startsOnNativeControl(event) { super.sendEvent(event); return }
            // Hold the press until we know whether it is a click or a drag.
            pendingDown = event
            dragStartMouse = NSEvent.mouseLocation
            dragStartOrigin = frame.origin
            isDragging = false
        case .leftMouseDragged:
            guard pendingDown != nil || isDragging, let start = dragStartMouse, let origin = dragStartOrigin else {
                super.sendEvent(event)
                return
            }
            let now = NSEvent.mouseLocation
            let dx = now.x - start.x, dy = now.y - start.y
            if !isDragging {
                guard hypot(dx, dy) > Self.dragThreshold else { return }
                isDragging = true
                pendingDown = nil
            }
            // Free movement while dragging, limited to the desktop as a whole, so the buddy can straddle the seam
            // between displays. It is clamped onto one display when released.
            setFrameOrigin(withinDesktop(NSRect(origin: NSPoint(x: origin.x + dx, y: origin.y + dy), size: frame.size)).origin)
        case .leftMouseUp:
            if isDragging {
                isDragging = false
                dragStartMouse = nil
                dragStartOrigin = nil
                setFrameOrigin(clamped(frame).origin)
                anchorFrame = frame
                savePosition()
                updateAnchorFromPosition()
            } else if let down = pendingDown {
                pendingDown = nil
                super.sendEvent(down)
                super.sendEvent(event)
            } else {
                super.sendEvent(event)
            }
        default:
            super.sendEvent(event)
        }
    }

    private func startsOnNativeControl(_ event: NSEvent) -> Bool {
        guard let content = contentView, let parent = content.superview,
              var view = content.hitTest(parent.convert(event.locationInWindow, from: nil)) else { return false }
        while view !== content {
            if view is NSControl || view is NSText { return true }
            guard let next = view.superview else { break }
            view = next
        }
        return false
    }

    // MARK: Sizing

    private func applyPreferredSize(initial: Bool = false) {
        guard let hosting else { return }
        var size = hosting.preferredContentSize
        if size.width < 1 || size.height < 1 { size = hosting.view.fittingSize }
        guard size.width >= 1, size.height >= 1 else { return }
        if initial {
            let origin = savedOrigin() ?? defaultOrigin(for: size)
            let rect = clamped(NSRect(origin: origin, size: size))
            setFrame(rect, display: true)
            anchorFrame = rect
            updateHomeFraction()
            updateAnchorFromPosition()
            return
        }
        reanchor(to: size)
    }

    /// Grow or shrink toward the screen centre: the corner nearest the screen edge stays put.
    private func reanchor(to size: NSSize) {
        let old = anchorFrame ?? frame
        var origin = old.origin
        if !anchorLeading { origin.x = old.maxX - size.width }
        if anchorTop { origin.y = old.maxY - size.height }
        let target = clamped(NSRect(origin: origin, size: size))
        anchorFrame = target
        if target != frame {
            isRestoring = true
            setFrame(target, display: true, animate: false)
            isRestoring = false
            if persistsMoves { savePosition() }
        }
        updateAnchorFromPosition()
    }

    @objc private func didResizeNotification() {
        guard !isRestoring, !isDragging, let anchor = anchorFrame, frame.size != anchor.size else { return }
        reanchor(to: frame.size)
    }

    /// Which quadrant the collapsed character sits in decides which way surfaces open.
    private func updateAnchorFromPosition() {
        guard frame.width <= Self.collapsedLimit, frame.height <= Self.collapsedLimit else { return }
        let vis = (screen ?? NSScreen.main)?.visibleFrame ?? frame
        let top = frame.midY > vis.midY
        let leading = frame.midX < vis.midX
        guard top != anchorTop || leading != anchorLeading else { return }
        anchorTop = top
        anchorLeading = leading
        onAnchorChange?(top, leading)
    }

    // MARK: Position persistence (per display)

    private var displayKey: String {
        let id = (screen ?? NSScreen.main)?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        return "buddy.origin.\(id?.stringValue ?? "main")"
    }

    private func savedOrigin() -> NSPoint? {
        guard let s = UserDefaults.standard.string(forKey: displayKey) else { return nil }
        return NSPointFromString(s)
    }

    private func savePosition() {
        UserDefaults.standard.set(NSStringFromPoint(frame.origin), forKey: displayKey)
        updateHomeFraction()
    }

    private func updateHomeFraction() {
        guard let vis = (screen ?? NSScreen.main)?.visibleFrame, vis.width > 0, vis.height > 0 else { return }
        homeFraction = CGPoint(x: (frame.minX - vis.minX) / vis.width, y: (frame.minY - vis.minY) / vis.height)
    }

    // MARK: Programmatic moves (ScreenFollower)

    /// True while the user is dragging or has a press pending; the follower must not fight them.
    var isUserDragging: Bool { isDragging || pendingDown != nil }

    /// Where the buddy lives on `target`: its saved spot there, else the same relative spot as on its home display.
    func homeOrigin(on target: NSScreen) -> NSPoint {
        let id = target.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        if let s = UserDefaults.standard.string(forKey: "buddy.origin.\(id?.stringValue ?? "main")") {
            // A stale entry can point at another display; only trust one that is actually on this display.
            let saved = NSPointFromString(s)
            if target.visibleFrame.contains(NSPoint(x: saved.x + frame.width / 2, y: saved.y + frame.height / 2)) { return saved }
        }
        let vis = target.visibleFrame
        return NSPoint(x: vis.minX + homeFraction.x * vis.width, y: vis.minY + homeFraction.y * vis.height)
    }

    /// Moves the window without saving the position. Keeps the growth anchor in sync.
    func place(origin: NSPoint) {
        let rect = clamped(NSRect(origin: origin, size: frame.size))
        guard rect.origin != frame.origin else { return }
        persistsMoves = false
        isRestoring = true
        setFrameOrigin(rect.origin)
        isRestoring = false
        anchorFrame = rect
        updateAnchorFromPosition()
    }

    /// Per-frame move for the follower: no clamping, so the buddy can glide across the seam between displays.
    func placeFree(origin: NSPoint) {
        persistsMoves = false
        isRestoring = true
        setFrameOrigin(origin)
        isRestoring = false
        anchorFrame = NSRect(origin: origin, size: frame.size)
        updateAnchorFromPosition()
    }

    /// Call when a programmatic move is done at the home spot, so later resizes persist again.
    func settleAtHome() { persistsMoves = true }

    private func defaultOrigin(for size: NSSize) -> NSPoint {
        let vis = NSScreen.screens.first?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(x: vis.maxX - size.width - 24, y: vis.minY + 24)
    }

    private func clamped(_ rect: NSRect) -> NSRect {
        let screens = NSScreen.screens
        // The display holding most of the window decides where it is clamped.
        let target = screens.max(by: { overlap($0.frame, rect) < overlap($1.frame, rect) }).flatMap { overlap($0.frame, rect) > 0 ? $0 : nil }
            ?? NSScreen.main ?? screens.first
        guard let vis = target?.visibleFrame else { return rect }
        var r = rect
        r.origin.x = min(max(r.origin.x, vis.minX), max(vis.minX, vis.maxX - r.width))
        r.origin.y = min(max(r.origin.y, vis.minY), max(vis.minY, vis.maxY - r.height))
        return r
    }

    private func overlap(_ a: NSRect, _ b: NSRect) -> CGFloat {
        let i = a.intersection(b)
        return i.isNull ? 0 : i.width * i.height
    }

    /// Keeps `rect` inside the union of all displays' visible areas (no per-display clamping).
    private func withinDesktop(_ rect: NSRect) -> NSRect {
        let union = NSScreen.screens.map(\.visibleFrame).reduce(NSRect.null) { $0.union($1) }
        guard !union.isNull else { return rect }
        var r = rect
        r.origin.x = min(max(r.origin.x, union.minX), max(union.minX, union.maxX - r.width))
        r.origin.y = min(max(r.origin.y, union.minY), max(union.minY, union.maxY - r.height))
        return r
    }

    @objc private func screensChanged() {
        let fixed = clamped(frame)
        if fixed != frame { setFrame(fixed, display: true) }
        anchorFrame = frame
        updateAnchorFromPosition()
    }
}
