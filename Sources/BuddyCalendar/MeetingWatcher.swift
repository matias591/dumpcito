import BuddyCore
import Foundation

/// Polls a MeetingProviding and emits each meeting once as it enters the lead window.
/// UI decides presentation; this only produces events.
public actor MeetingWatcher {
    private let provider: MeetingProviding
    private let leadTime: TimeInterval
    private let pollInterval: TimeInterval
    private let now: @Sendable () -> Date
    private let defaults: UserDefaults
    private let storeKey = "buddy.calendar.nudged"
    private var nudged: [String: Double]  // event id -> start (epoch seconds)
    private var continuations: [UUID: AsyncStream<MeetingEvent>.Continuation] = [:]
    private var pollTask: Task<Void, Never>?

    public init(provider: MeetingProviding,
                leadTime: TimeInterval = 5 * 60,
                pollInterval: TimeInterval = 30,
                defaults: UserDefaults = .standard,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.provider = provider
        self.leadTime = leadTime
        self.pollInterval = pollInterval
        self.defaults = defaults
        self.now = now
        self.nudged = (defaults.dictionary(forKey: "buddy.calendar.nudged") as? [String: Double]) ?? [:]
    }

    /// Stream of meetings to nudge about. Starts the 30s polling loop on first use.
    public func nudges() -> AsyncStream<MeetingEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<MeetingEvent>.makeStream(bufferingPolicy: .unbounded)
        continuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeContinuation(id) }
        }
        if pollTask == nil {
            pollTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self else { return }
                    await self.poll()
                    try? await Task.sleep(nanoseconds: UInt64(self.pollInterval * 1_000_000_000))
                }
            }
        }
        return stream
    }

    /// Next meeting that has not ended yet (for the expanded panel).
    public func nextMeeting() async -> MeetingEvent? {
        let t = now()
        return await provider.upcoming(within: 24 * 3600).first { $0.end > t }
    }

    /// One poll cycle (also called by the loop; exposed for tests).
    public func poll() async {
        let t = now()
        prune(at: t)
        let events = await provider.upcoming(within: leadTime)
        var changed = false
        for e in events.sorted(by: { $0.start < $1.start }) {
            let untilStart = e.start.timeIntervalSince(t)
            guard untilStart <= leadTime, untilStart >= -EventKitMeetingProvider.gracePeriod else { continue }
            if nudged[e.id] != nil { continue }
            nudged[e.id] = e.start.timeIntervalSince1970
            changed = true
            for c in continuations.values { c.yield(e) }
        }
        if changed { save() }
    }

    private func removeContinuation(_ id: UUID) {
        continuations[id] = nil
        if continuations.isEmpty { pollTask?.cancel(); pollTask = nil }
    }

    private func prune(at t: Date) {
        let cutoff = t.timeIntervalSince1970 - 24 * 3600
        let before = nudged.count
        nudged = nudged.filter { $0.value >= cutoff }
        if nudged.count != before { save() }
    }

    private func save() { defaults.set(nudged, forKey: storeKey) }
}
