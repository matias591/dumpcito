import AppKit
import BuddyCore
import QuartzCore

/// Keeps the buddy findable on a multi-display Mac.
/// - Idle: when the cursor has been on another display for a moment, the buddy glides to its home spot there.
/// - Needs you / meeting soon: it trails the cursor continuously until the user reacts, then glides home.
/// Motion is a critically damped spring stepped on the display refresh, so it is smooth and never snaps.
/// Moves never touch the saved home position (see `BuddyPanel.placeFree`).
@MainActor
final class ScreenFollower {
    static let enabledKey = "buddy.follow"

    private enum Mode { case rest, chase, glide(NSPoint) }

    private static let hopDelay: TimeInterval = 1.2
    /// Clear space kept between the cursor and the buddy.
    private static let gap: CGFloat = 36
    /// While the cursor is this close to the buddy it stops moving, so a click can land.
    private static let holdZone: CGFloat = 60
    /// Spring natural frequency (rad/s): higher is snappier. ~7 settles in about 0.7 s.
    private static let omega: CGFloat = 7

    private let panel: BuddyPanel
    private let model: BuddyModel
    private var poll: Timer?
    private var link: CADisplayLink?
    private var mode = Mode.rest
    private var velocity = CGVector.zero
    private var lastFrame: CFTimeInterval = 0
    private var elsewhereSince: Date?
    /// Side of the cursor the buddy trails on, kept for the whole chase so it doesn't flip back and forth.
    private var chaseRight = true
    private var chaseAbove = false

    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.enabledKey) }
    }

    init(panel: BuddyPanel, model: BuddyModel) {
        self.panel = panel
        self.model = model
    }

    func start() {
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.decide() }
        }
        RunLoop.main.add(t, forMode: .common)
        poll = t
    }

    /// Menu action: glide to the display the cursor is on right now.
    func summon() {
        guard let screen = cursorScreen() else { return }
        panel.orderFrontRegardless()
        glide(to: panel.homeOrigin(on: screen))
    }

    // MARK: Decisions (10 Hz)

    private var wantsAttention: Bool {
        switch model.mood {
        case .sessionNeedsYou, .meetingSoon: true
        default: false
        }
    }

    private var userIsBusy: Bool {
        if panel.isUserDragging || model.expanded { return true }
        switch model.mood {
        case .listening, .choosingTarget: return true
        default: return false
        }
    }

    private func cursorScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) }
    }

    private func decide() {
        if panel.isUserDragging {
            // The user took over: drop any chase or glide so nothing pulls the buddy back while they drag.
            elsewhereSince = nil
            stopMoving()
            return
        }
        guard isEnabled, panel.isVisible, !userIsBusy, let screen = cursorScreen() else {
            elsewhereSince = nil
            if case .chase = mode { glideHome() }
            return
        }
        if wantsAttention {
            elsewhereSince = nil
            if case .chase = mode {} else {
                chaseRight = panel.frame.midX >= NSEvent.mouseLocation.x
                chaseAbove = panel.frame.midY >= NSEvent.mouseLocation.y
                mode = .chase
            }
            resume()
            return
        }
        if case .chase = mode {
            glideHome()
            return
        }
        guard case .rest = mode else { return }
        if panel.screen == screen {
            elsewhereSince = nil
        } else if let since = elsewhereSince {
            if Date().timeIntervalSince(since) >= Self.hopDelay {
                elsewhereSince = nil
                glide(to: panel.homeOrigin(on: screen))
            }
        } else {
            elsewhereSince = Date()
        }
    }

    private func glideHome() {
        guard let screen = panel.screen ?? cursorScreen() else { return }
        glide(to: panel.homeOrigin(on: screen))
    }

    private func glide(to point: NSPoint) {
        mode = .glide(point)
        resume()
    }

    // MARK: Motion (display refresh)

    private func resume() {
        if link == nil, let view = panel.contentView {
            let l = view.displayLink(target: self, selector: #selector(frame(_:)))
            l.add(to: .main, forMode: .common)
            link = l
            lastFrame = 0
        }
        link?.isPaused = false
    }

    private func stopMoving() {
        mode = .rest
        velocity = .zero
        pause()
    }

    private func pause() {
        link?.isPaused = true
        lastFrame = 0
    }

    private func goal() -> NSPoint? {
        switch mode {
        case .rest: return nil
        case let .glide(point): return point
        case .chase:
            guard let screen = cursorScreen() else { return nil }
            // Never back away from a cursor that is closing in: hold still so the buddy can be clicked.
            if panel.frame.insetBy(dx: -Self.holdZone, dy: -Self.holdZone).contains(NSEvent.mouseLocation) {
                return panel.frame.origin
            }
            return Self.origin(besides: NSEvent.mouseLocation, size: panel.frame.size,
                               onRight: chaseRight, above: chaseAbove, in: screen)
        }
    }

    @objc private func frame(_ link: CADisplayLink) {
        if panel.isUserDragging { stopMoving(); return }
        guard let goal = goal() else { pause(); return }
        let dt = lastFrame == 0 ? 1.0 / 60 : min(link.timestamp - lastFrame, 1.0 / 30)
        lastFrame = link.timestamp
        let pos = panel.frame.origin
        // Critically damped spring, semi-implicit Euler.
        let w = Self.omega, k = CGFloat(dt)
        velocity.dx += (w * w * (goal.x - pos.x) - 2 * w * velocity.dx) * k
        velocity.dy += (w * w * (goal.y - pos.y) - 2 * w * velocity.dy) * k
        let next = NSPoint(x: pos.x + velocity.dx * k, y: pos.y + velocity.dy * k)
        let settled = hypot(goal.x - next.x, goal.y - next.y) < 0.5 && hypot(velocity.dx, velocity.dy) < 4
        if settled {
            velocity = .zero
            panel.placeFree(origin: goal)
            switch mode {
            case .glide:
                panel.place(origin: goal)   // final clamp onto the display
                panel.settleAtHome()
                mode = .rest
                pause()
            default:
                pause()   // chase: the 10 Hz poll resumes it when the cursor moves
            }
            return
        }
        panel.placeFree(origin: next)
    }

    /// Origin that puts a window of `size` `gap` points from `mouse`, flipping sides to stay on screen.
    private static func origin(besides mouse: NSPoint, size: NSSize, onRight: Bool, above: Bool, in screen: NSScreen) -> NSPoint {
        let vis = screen.visibleFrame
        var right = onRight, up = above
        if right, mouse.x + gap + size.width > vis.maxX { right = false }
        if !right, mouse.x - gap - size.width < vis.minX { right = true }
        if up, mouse.y + gap + size.height > vis.maxY { up = false }
        if !up, mouse.y - gap - size.height < vis.minY { up = true }
        return NSPoint(x: right ? mouse.x + gap : mouse.x - gap - size.width,
                       y: up ? mouse.y + gap : mouse.y - gap - size.height)
    }
}
