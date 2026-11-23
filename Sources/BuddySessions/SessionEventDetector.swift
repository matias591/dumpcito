import Foundation

public enum DetectedKind: String, Sendable { case needsAttention, finished }

public struct DetectedEvent: Equatable, Sendable {
    public var kind: DetectedKind
    public var record: StateRecord
}

/// Spec section 4. Turns successive snapshots of the state directory into alerts. Alerts come only from
/// state changes the hook recorded; there is no guessing.
public struct SessionEventDetector {
    public static let staleAfter: TimeInterval = 15 * 60

    public var finishedThreshold: TimeInterval
    public var attentionCooldown: TimeInterval
    private var lastSeenAt: [String: Int64] = [:]
    private var lastAttentionAlert: [String: Int64] = [:]
    private var primed = false

    public init(finishedThreshold: TimeInterval = 20, attentionCooldown: TimeInterval = 30) {
        self.finishedThreshold = finishedThreshold; self.attentionCooldown = attentionCooldown
    }

    /// The state the UI shows: a record nobody touched for 15 minutes is idle.
    public static func isStale(_ r: StateRecord, nowMs: Int64) -> Bool {
        Double(nowMs - r.touched) / 1000 > staleAfter
    }

    public static func displayState(_ r: StateRecord, nowMs: Int64) -> HookState {
        isStale(r, nowMs: nowMs) && (r.state == .working || r.state == .waiting) ? .idle : r.state
    }

    public mutating func ingest(_ records: [StateRecord], nowMs: Int64) -> [DetectedEvent] {
        var events: [DetectedEvent] = []
        var seen: [String: Int64] = [:]
        for r in records {
            let key = r.key
            seen[key] = r.at
            guard primed, !Self.isStale(r, nowMs: nowMs) else { continue }
            let previous = lastSeenAt[key] ?? Int64.min
            guard r.at > previous else { continue }
            switch r.state {
            case .waiting:
                let last = lastAttentionAlert[key]
                if last == nil || Double(nowMs - last!) / 1000 > attentionCooldown {
                    lastAttentionAlert[key] = nowMs
                    events.append(DetectedEvent(kind: .needsAttention, record: r))
                }
            case .done:
                if let start = r.workingSince, Double(r.at - start) / 1000 >= finishedThreshold {
                    events.append(DetectedEvent(kind: .finished, record: r))
                }
            case .idle, .working: break
            }
        }
        lastSeenAt = seen
        lastAttentionAlert = lastAttentionAlert.filter { seen[$0.key] != nil }
        primed = true
        return events
    }
}
