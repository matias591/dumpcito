import BuddyCore
import CoreGraphics

/// Payload-free mood, for change detection and lookups.
enum MoodKind: Hashable {
    case idle, meeting, listening, choosing, finished, needsYou, sent, error
}

/// What sits next to the character.
enum SurfaceKind: Hashable {
    case none
    case bubble(MoodKind)
    case picker
    case panel
}

extension BuddyMood {
    var kind: MoodKind {
        switch self {
        case .idle: .idle
        case .meetingSoon: .meeting
        case .listening: .listening
        case .choosingTarget: .choosing
        case .sessionFinished: .finished
        case .sessionNeedsYou: .needsYou
        case .sent: .sent
        case .error: .error
        }
    }

    /// Spoken by VoiceOver when the mood arrives.
    var announcement: String? {
        switch self {
        case .idle, .listening, .choosingTarget: nil
        case let .meetingSoon(m): "\(m.title), \(Fmt.countdown(to: m))"
        case let .sessionFinished(s): "Finished: \(s.title)"
        case let .sessionNeedsYou(s): "Needs you: \(s.title)"
        case let .sent(text): text
        case let .error(text): "Error: \(text)"
        }
    }

    var accessibilityValue: String {
        switch self {
        case .idle: "Idle"
        case let .meetingSoon(m): "Meeting soon: \(m.title)"
        case .listening: "Listening"
        case .choosingTarget: "Choosing where to send"
        case let .sessionFinished(s): "Finished: \(s.title)"
        case let .sessionNeedsYou(s): "Needs you: \(s.title)"
        case let .sent(text): text
        case let .error(text): "Error: \(text)"
        }
    }
}

enum DotStatus: Hashable {
    case working, idle, needsYou
    /// Recent, not live: a short grey dash.
    case dormant

    var label: String {
        switch self {
        case .working: "working"
        case .idle: "idle"
        case .needsYou: "needs you"
        case .dormant: "not running"
        }
    }
}

extension AgentSession {
    var dotStatus: DotStatus {
        if needsAttention { return .needsYou }
        return state == .working ? .working : .idle
    }
}
