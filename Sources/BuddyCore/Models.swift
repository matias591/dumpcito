import Foundation

public enum SessionState: String, Codable, Sendable {
    case working
    case idle
}

/// AI coding tools Dumpcito can listen to.
public enum AgentTool: String, Codable, Sendable, CaseIterable {
    case claude, codex, cursor

    public var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .cursor: "Cursor"
        }
    }

    /// What to tell the user after connecting; `nil` when there is nothing to add. Spec: spec/HOOK-SPEC.md section 5.
    public var connectNote: String? {
        switch self {
        case .claude: nil
        case .codex: "Open Codex and run /hooks once to trust Dumpcito. Codex skips new hooks until you do."
        case .cursor: "Cursor has no \"needs you\" event, so Dumpcito only tells you when a turn finishes."
        }
    }
}

/// A coding-agent session as seen by the buddy. Built from the state files the hook writes.
public struct AgentSession: Identifiable, Hashable, Sendable {
    /// `<tool>__<session>`, unique across tools.
    public let id: String
    public var tool: AgentTool
    public var title: String
    public var cwd: String
    public var state: SessionState
    /// Session is blocked on a permission prompt / question for the user.
    public var needsAttention: Bool
    public var lastActivity: Date

    public init(id: String, tool: AgentTool = .claude, title: String, cwd: String, state: SessionState,
                needsAttention: Bool, lastActivity: Date) {
        self.id = id; self.tool = tool; self.title = title; self.cwd = cwd; self.state = state
        self.needsAttention = needsAttention; self.lastActivity = lastActivity
    }
}

public struct MeetingEvent: Identifiable, Hashable, Sendable {
    public let id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var joinURL: URL?
    public var location: String?

    public init(id: String, title: String, start: Date, end: Date, joinURL: URL?, location: String?) {
        self.id = id; self.title = title; self.start = start; self.end = end
        self.joinURL = joinURL; self.location = location
    }
}

/// Output of one hotkey capture: where the screenshot was saved plus the on-device transcript.
public struct CaptureResult: Sendable {
    public var screenshotURL: URL?
    public var transcript: String
    public init(screenshotURL: URL?, transcript: String) {
        self.screenshotURL = screenshotURL; self.transcript = transcript
    }
}

public enum DispatchTarget: Sendable, Hashable {
    case session(id: String)
    case newSession(cwd: String)
}
