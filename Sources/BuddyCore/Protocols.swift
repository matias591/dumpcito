import Foundation

public protocol SessionProviding: Sendable {
    /// Sessions seen active within the last ~10 min (state working/idle), newest activity first.
    func liveSessions() async -> [AgentSession]
    /// Most recently opened sessions regardless of liveness, newest first.
    func recentSessions(limit: Int) async -> [AgentSession]
    /// Stream of changes worth surfacing: a session finished (working -> idle) or needs the user.
    func events() -> AsyncStream<SessionEvent>
    /// Send prompt (+ optional screenshot path appended to the prompt text) to a session.
    func dispatch(prompt: String, screenshot: URL?, to target: DispatchTarget) async throws
}

public enum SessionEvent: Sendable {
    case finished(AgentSession)
    case needsAttention(AgentSession)
}

public protocol MeetingProviding: Sendable {
    func requestAccess() async -> Bool
    /// Meetings starting within the window, soonest first. Skips all-day and declined events.
    func upcoming(within seconds: TimeInterval) async -> [MeetingEvent]
}

public enum CaptureEvent: Sendable {
    case began
    /// Live partial transcript while the hotkey is held.
    case partial(String)
    case finished(CaptureResult)
    case failed(String)
}

public protocol CaptureProviding: Sendable {
    /// Hold-to-talk: emits .began on key down, .finished on key up.
    func events() -> AsyncStream<CaptureEvent>
    /// Ask for Screen Recording, Microphone and Speech permissions up front.
    func requestPermissions() async
}
