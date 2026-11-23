import Foundation
import BuddyCore

/// Spec: spec/HOOK-SPEC.md. State the hook records for one session.
public enum HookState: String, Codable, Sendable { case idle, working, waiting, done }

/// One state file. Times are epoch milliseconds.
public struct StateRecord: Codable, Equatable, Sendable {
    public var v = 1
    public var tool: String
    public var session: String
    public var cwd: String
    public var title: String
    public var state: HookState
    /// When the record entered its current `state`. Only changes when `state` changes.
    public var at: Int64
    /// When the current turn began; kept on `done`, omitted on `idle`.
    public var workingSince: Int64?
    /// Last event of any kind.
    public var touched: Int64

    public var key: String { "\(tool)__\(session)" }
}

public enum HookAction: Equatable, Sendable {
    case ignore
    case remove(tool: String, session: String)
    case write(StateRecord)
}

public enum HookNormalizer {
    public static let knownTools: Set<String> = Set(AgentTool.allCases.map(\.rawValue))
    static let waitingNotifications: Set<String> = ["permission_prompt", "elicitation_dialog", "elicitation_url_dialog"]
    static let promptEvents: Set<String> = ["userpromptsubmit", "beforesubmitprompt", "userpromptsubmitted"]
    static let workingEvents: Set<String> = promptEvents.union(
        ["pretooluse", "posttooluse", "posttoolusefailure", "permissiondenied"])

    /// Session ids become part of a file name, so anything that could escape the directory is refused.
    public static func isSafe(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 64 && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    public static func normalize(tool: String, payload: [String: Any], existing: StateRecord?, now: Int64) -> HookAction {
        guard knownTools.contains(tool),
              let session = (payload["session_id"] ?? payload["sessionId"] ?? payload["conversation_id"]) as? String,
              isSafe(session),
              let rawEvent = (payload["hook_event_name"] ?? payload["hookEventName"]) as? String else { return .ignore }
        let event = rawEvent.lowercased()
        if event == "sessionend" { return .remove(tool: tool, session: session) }

        let current = existing?.state
        var target: HookState?
        if workingEvents.contains(event) {
            target = .working
        } else if event == "permissionrequest" {
            target = .waiting
        } else if event == "notification" {
            if isWaitingNotification(payload), current != .done, current != .idle { target = .waiting }
        } else if event == "stop" || event == "agentstop" || event == "stopfailure" {
            target = .done
            if tool == "cursor", (payload["status"] as? String) != "completed" { target = .idle }
        } else if event == "sessionstart" {
            if existing == nil { target = .idle }
        }

        // Touch-only events never create a file.
        guard target != nil || existing != nil else { return .ignore }

        var record = existing ?? StateRecord(tool: tool, session: session, cwd: "", title: "", state: target ?? .idle,
                                             at: now, workingSince: nil, touched: now)
        record.touched = now
        if let cwd = (payload["cwd"] as? String) ?? (payload["workspace_roots"] as? [String])?.first, !cwd.isEmpty {
            record.cwd = cwd
        }
        if promptEvents.contains(event), let prompt = payload["prompt"] as? String {
            let collapsed = prompt.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            if !collapsed.isEmpty { record.title = String(collapsed.prefix(80)) }
        }
        guard let target, target != existing?.state else { return .write(record) }

        record.state = target
        record.at = now
        switch target {
        case .working, .waiting:
            record.workingSince = (current == .working || current == .waiting) ? (existing?.workingSince ?? now) : now
        case .done:
            break // keep workingSince from the turn that just ended
        case .idle:
            record.workingSince = nil
        }
        return .write(record)
    }

    private static func isWaitingNotification(_ payload: [String: Any]) -> Bool {
        if let type = payload["notification_type"] as? String { return waitingNotifications.contains(type) }
        return (payload["message"] as? String)?.localizedCaseInsensitiveContains("permission") == true
    }
}

/// The state directory: one small JSON file per session, written atomically.
public struct StateStore: Sendable {
    public static let defaultDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".dumpcito/state")
    public let dir: URL
    public init(dir: URL = StateStore.defaultDir) { self.dir = dir }

    func url(tool: String, session: String) -> URL { dir.appendingPathComponent("\(tool)__\(session).json") }

    public func read(tool: String, session: String) -> StateRecord? { Self.decode(url(tool: tool, session: session)) }

    public func readAll() -> [StateRecord] {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" && !$0.lastPathComponent.hasPrefix(".") }
            .compactMap(Self.decode)
    }

    public func write(_ record: StateRecord) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        let tmp = dir.appendingPathComponent(".\(record.key).\(UUID().uuidString).tmp")
        try enc.encode(record).write(to: tmp)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tmp.path)
        guard rename(tmp.path, url(tool: record.tool, session: record.session).path) == 0 else {
            try? fm.removeItem(at: tmp)
            throw CocoaError(.fileWriteUnknown)
        }
    }

    public func remove(tool: String, session: String) {
        try? FileManager.default.removeItem(at: url(tool: tool, session: session))
    }

    /// Deletes files untouched for `days` days.
    public func prune(olderThanDays days: Int = 7, now: Date = Date()) {
        let cutoff = Int64(now.timeIntervalSince1970 * 1000) - Int64(days) * 86_400_000
        for r in readAll() where r.touched < cutoff { remove(tool: r.tool, session: r.session) }
    }

    /// Applies a normalised action. Never throws: a hook must not fail loudly.
    public func apply(_ action: HookAction) {
        switch action {
        case .ignore: break
        case let .remove(tool, session): remove(tool: tool, session: session)
        case let .write(record): try? write(record)
        }
    }

    private static func decode(_ url: URL) -> StateRecord? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 64 * 1024 + 1), data.count <= 64 * 1024,
              let r = try? JSONDecoder().decode(StateRecord.self, from: data), r.v == 1,
              HookNormalizer.isSafe(r.session), HookNormalizer.knownTools.contains(r.tool) else { return nil }
        return r
    }
}

/// `Dumpcito --hook --tool <tool>`: the command the AI tools run. Never fails loudly, never prints
/// anything except `{}` for Cursor (whose hooks expect JSON on stdout).
public enum AttentionHook {
    public static func handle(tool: String, input: Data, store: StateStore = StateStore(), now: Date = Date()) {
        guard input.count <= 1_000_000,
              let obj = try? JSONSerialization.jsonObject(with: input) as? [String: Any] else { return }
        let ms = Int64(now.timeIntervalSince1970 * 1000)
        let id = (obj["session_id"] ?? obj["sessionId"] ?? obj["conversation_id"]) as? String ?? ""
        let existing = HookNormalizer.isSafe(id) ? store.read(tool: tool, session: id) : nil
        store.apply(HookNormalizer.normalize(tool: tool, payload: obj, existing: existing, now: ms))
    }

    public static func runFromStdin(tool: String) {
        handle(tool: tool, input: FileHandle.standardInput.readDataToEndOfFile())
        if tool == "cursor" { print("{}") }
    }
}
