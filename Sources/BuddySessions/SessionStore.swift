import Foundation
import BuddyCore

public enum SessionDispatchError: Error, LocalizedError, Equatable {
    case emptyPrompt
    case launchFailed(String)

    public var errorDescription: String? {
        switch self {
        case .emptyPrompt: "Nothing to send: the prompt is empty."
        case .launchFailed(let detail): "Could not open a new Claude Code session: \(detail)"
        }
    }
}

/// Sessions of every connected tool, read from the state files the hook writes (spec/HOOK-SPEC.md).
public final class SessionStore: SessionProviding {
    private let store: StateStore
    private let strategy: NewSessionStrategy
    private let launch: LaunchRunner
    private let copyToClipboard: @Sendable (String) -> Void
    private let eventInterval: TimeInterval
    private let finishedThreshold: TimeInterval
    private let now: @Sendable () -> Date

    /// - Parameters:
    ///   - copyToClipboard: how a prompt reaches an already open session. Dumpcito never types into other apps:
    ///     it copies the text and the user pastes it.
    public init(
        store: StateStore = StateStore(),
        newSessionStrategy: NewSessionStrategy = .vscodeURI,
        launch: @escaping LaunchRunner = NewSessionLauncher.processRunner,
        copyToClipboard: @escaping @Sendable (String) -> Void = { _ in },
        eventInterval: TimeInterval = 1,
        finishedThreshold: TimeInterval = 20,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.strategy = newSessionStrategy
        self.launch = launch
        self.copyToClipboard = copyToClipboard
        self.eventInterval = eventInterval
        self.finishedThreshold = finishedThreshold
        self.now = now
    }

    private func ms(_ d: Date) -> Int64 { Int64(d.timeIntervalSince1970 * 1000) }

    // MARK: SessionProviding

    public func liveSessions() async -> [AgentSession] {
        let t = ms(now())
        return store.readAll()
            .filter { !SessionEventDetector.isStale($0, nowMs: t) }
            .sorted { $0.touched > $1.touched }
            .map { Self.session(from: $0, nowMs: t) }
    }

    public func recentSessions(limit: Int) async -> [AgentSession] {
        guard limit > 0 else { return [] }
        let t = ms(now())
        return store.readAll()
            .filter { !$0.cwd.isEmpty }
            .sorted { $0.touched > $1.touched }
            .prefix(limit)
            .map { Self.session(from: $0, nowMs: t) }
    }

    public func events() -> AsyncStream<SessionEvent> {
        AsyncStream { continuation in
            let task = Task {
                var detector = SessionEventDetector(finishedThreshold: self.finishedThreshold)
                while !Task.isCancelled {
                    let t = self.ms(self.now())
                    for e in detector.ingest(self.store.readAll(), nowMs: t) {
                        let s = Self.session(from: e.record, nowMs: t)
                        continuation.yield(e.kind == .finished ? .finished(s) : .needsAttention(s))
                    }
                    try? await Task.sleep(nanoseconds: UInt64(self.eventInterval * 1_000_000_000))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func dispatch(prompt: String, screenshot: URL?, to target: DispatchTarget) async throws {
        var text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw SessionDispatchError.emptyPrompt }
        if let screenshot {
            text += "\n\n[Screenshot of my screen saved at \(screenshot.path). Read it before answering.]"
        }
        switch target {
        case .session:
            copyToClipboard(text)
        case .newSession(let cwd):
            for step in NewSessionLauncher.steps(for: strategy, cwd: cwd, prompt: text) { try await launch(step) }
        }
    }

    static func session(from r: StateRecord, nowMs: Int64) -> AgentSession {
        let display = SessionEventDetector.displayState(r, nowMs: nowMs)
        return AgentSession(
            id: r.key, tool: AgentTool(rawValue: r.tool) ?? .claude, title: r.title, cwd: r.cwd,
            state: display == .working || display == .waiting ? .working : .idle,
            needsAttention: display == .waiting,
            lastActivity: Date(timeIntervalSince1970: Double(r.touched) / 1000))
    }
}
