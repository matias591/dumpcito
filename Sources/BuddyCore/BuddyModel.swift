import Foundation
import Observation

/// What the buddy is currently doing. One value drives the whole UI.
public enum BuddyMood: Equatable, Sendable {
    case idle
    case meetingSoon(MeetingEvent)
    case listening(partial: String)
    /// Capture done; user is choosing where to send it.
    case choosingTarget(CaptureResult)
    case sessionFinished(AgentSession)
    case sessionNeedsYou(AgentSession)
    case sent(String)
    case error(String)

    public static func == (l: BuddyMood, r: BuddyMood) -> Bool {
        switch (l, r) {
        case (.idle, .idle): return true
        case let (.meetingSoon(a), .meetingSoon(b)): return a == b
        case let (.listening(a), .listening(b)): return a == b
        case let (.sessionFinished(a), .sessionFinished(b)): return a == b
        case let (.sessionNeedsYou(a), .sessionNeedsYou(b)): return a == b
        case let (.sent(a), .sent(b)): return a == b
        case let (.error(a), .error(b)): return a == b
        case (.choosingTarget, .choosingTarget): return true
        default: return false
        }
    }
}

/// Single observable the UI reads. The app wires providers into it; UI never talks to providers directly.
@MainActor @Observable
public final class BuddyModel {
    public var mood: BuddyMood = .idle
    /// Selected look. The app persists it; the UI redraws when it changes.
    public var skin: BuddySkin = .jelly
    /// 1...5, from the progress game. Grows the character slightly; 1 when levels are off.
    public var stage = 1
    /// Chat/pick panel expanded by click. Collapsed = only the character.
    public var expanded = false
    public var liveSessions: [AgentSession] = []
    public var recentSessions: [AgentSession] = []
    public var nextMeeting: MeetingEvent?
    /// Which screen quadrant the host window sits in, so surfaces open toward the screen centre.
    public var anchoredTop = false
    public var anchoredLeading = false

    // Callbacks the UI invokes; the app sets them.
    public var onPick: (DispatchTarget) -> Void = { _ in }
    public var onJoinMeeting: (MeetingEvent) -> Void = { _ in }
    public var onDismiss: () -> Void = {}
    public var onOpenSession: (AgentSession) -> Void = { _ in }

    public init() {}
}
