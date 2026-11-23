import Foundation

/// Pure push-to-talk state machine. Guards key-repeat, double-press, and a hard max duration.
/// `keyHeld` stays true from the first down until a real up, so repeats (and repeats after an
/// auto-finish at max duration) can never start a second capture.
struct PushToTalkMachine {
    enum Phase: Equatable {
        case idle
        case recording(since: Date)
        case finishing
    }
    enum StopReason: Equatable { case released, maxDuration }
    enum Action: Equatable { case none, start, stop(StopReason) }

    let maxDuration: TimeInterval
    private(set) var phase: Phase = .idle
    private(set) var keyHeld = false

    init(maxDuration: TimeInterval = 120) { self.maxDuration = maxDuration }

    mutating func keyDown(at now: Date) -> Action {
        if keyHeld { return .none }            // key repeat / duplicate press
        keyHeld = true
        guard phase == .idle else { return .none } // previous capture still finishing
        phase = .recording(since: now)
        return .start
    }

    mutating func keyUp() -> Action {
        keyHeld = false
        guard case .recording = phase else { return .none }
        phase = .finishing
        return .stop(.released)
    }

    /// Call periodically / from a timer.
    mutating func tick(at now: Date) -> Action {
        guard case .recording(let since) = phase, now.timeIntervalSince(since) >= maxDuration else { return .none }
        phase = .finishing
        return .stop(.maxDuration)
    }

    /// Finish flow completed (result emitted).
    mutating func finished() { if phase == .finishing { phase = .idle } }

    /// Start failed; drop back to idle without emitting a result.
    mutating func abort() { phase = .idle }
}
