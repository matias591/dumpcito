import Foundation
import BuddyCore

public enum HookInstallError: Error, LocalizedError, Equatable {
    case settingsUnreadable(String)
    case settingsNotAnObject(String)

    public var errorDescription: String? {
        switch self {
        case .settingsUnreadable(let name): "\(name) could not be read as JSON, so Dumpcito left it untouched."
        case .settingsNotAnObject(let name): "\(name) is not a JSON object, so Dumpcito left it untouched."
        }
    }
}

/// Adds or removes Dumpcito's hook entries in one tool's hook config (Claude Code, Codex or Cursor).
/// Spec: spec/HOOK-SPEC.md section 5. Consent-based: the app only calls this when the user presses
/// Connect / Disconnect. Never touches entries it did not add, keeps a timestamped backup before the
/// first change, and writes atomically.
public struct HookInstaller {
    /// Present in every command Dumpcito writes; how entries are recognised later.
    static let marker = "dumpcito-hook"
    /// Entries written by earlier versions carry these markers; they are still recognised so they can be replaced or removed.
    static let legacyMarkers = ["dumpcito-attention-hook", "buddy-attention-hook"]

    public static func events(for tool: AgentTool) -> [String] {
        switch tool {
        case .claude: ["UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure",
                       "PermissionRequest", "PermissionDenied", "Notification", "Stop", "StopFailure",
                       "SessionStart", "SessionEnd"]
        case .codex: ["UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Stop",
                      "SessionStart", "SessionEnd"]
        // Never add Cursor's permission-style hooks: invalid output from them blocks the user's action.
        case .cursor: ["beforeSubmitPrompt", "postToolUse", "stop", "sessionEnd"]
        }
    }

    public static func defaultConfigURL(for tool: AgentTool, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        switch tool {
        case .claude: home.appendingPathComponent(".claude/settings.json")
        case .codex: home.appendingPathComponent(".codex/hooks.json")
        case .cursor: home.appendingPathComponent(".cursor/hooks.json")
        }
    }

    /// True if the tool looks installed on this Mac, used to pre-tick the connect list.
    public static func isToolPresent(_ tool: AgentTool, home: URL = FileManager.default.homeDirectoryForCurrentUser,
                                     searchPath: [String] = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init) + ["/opt/homebrew/bin", "/usr/local/bin"]) -> Bool {
        let fm = FileManager.default
        let dirs: [AgentTool: String] = [.claude: ".claude", .codex: ".codex", .cursor: ".cursor"]
        if fm.fileExists(atPath: home.appendingPathComponent(dirs[tool]!).path) { return true }
        if tool == .cursor, fm.fileExists(atPath: "/Applications/Cursor.app") { return true }
        let bin = tool == .cursor ? "cursor" : tool.rawValue
        return searchPath.contains { fm.isExecutableFile(atPath: "\($0)/\(bin)") }
    }

    public let tool: AgentTool
    public let configURL: URL
    public let executable: String

    public init(tool: AgentTool = .claude, configURL: URL? = nil, executable: String) {
        self.tool = tool
        self.configURL = configURL ?? Self.defaultConfigURL(for: tool)
        self.executable = executable
    }

    private var fileName: String { configURL.lastPathComponent }

    /// Quiet no-op if Dumpcito has moved or was deleted, so the tool never shows a hook error.
    var command: String {
        let q = "'" + executable.replacingOccurrences(of: "'", with: "'\\''") + "'"
        return "[ -x \(q) ] && \(q) --hook --tool \(tool.rawValue) >/dev/null 2>&1; exit 0 # \(Self.marker)"
    }

    private var events: [String] { Self.events(for: tool) }

    /// Cursor entries are flat `{command, timeout}`; Claude and Codex nest them under a matcher group.
    private func entry() -> [String: Any] {
        tool == .cursor
            ? ["command": command, "timeout": 5]
            : ["matcher": "", "hooks": [["type": "command", "command": command, "timeout": 5]]]
    }

    private func isOurs(_ item: [String: Any]) -> Bool {
        func matches(_ s: String?) -> Bool { s.map { $0.contains(Self.marker) || Self.legacyMarkers.contains(where: $0.contains) } == true }
        if matches(item["command"] as? String) { return true }
        return (item["hooks"] as? [[String: Any]] ?? []).contains { matches($0["command"] as? String) }
    }

    public func isInstalled() -> Bool {
        guard let root = try? load() else { return false }
        let hooks = root["hooks"] as? [String: Any] ?? [:]
        return events.allSatisfy { (hooks[$0] as? [[String: Any]] ?? []).contains(where: isOurs) }
    }

    public func install() throws {
        var root = try load()
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        // Drop our entries from events we no longer register, then refresh the ones we do.
        for (event, value) in hooks where !events.contains(event) {
            guard let items = value as? [[String: Any]], items.contains(where: isOurs) else { continue }
            let kept = items.filter { !isOurs($0) }
            hooks[event] = kept.isEmpty ? nil : kept
        }
        for event in events {
            var items = (hooks[event] as? [[String: Any]] ?? []).filter { !isOurs($0) }
            items.append(entry())
            hooks[event] = items
        }
        root["hooks"] = hooks
        if tool == .cursor, root["version"] == nil { root["version"] = 1 }
        try save(root)
    }

    public func uninstall() throws {
        var root = try load()
        guard var hooks = root["hooks"] as? [String: Any] else { return }
        for (event, value) in hooks {
            guard let items = value as? [[String: Any]] else { continue }
            let kept = items.filter { !isOurs($0) }
            hooks[event] = kept.isEmpty ? nil : kept
        }
        root["hooks"] = hooks.isEmpty ? nil : hooks
        try save(root)
    }

    // MARK: Files

    private func load() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: configURL.path) else { return [:] }
        guard let data = try? Data(contentsOf: configURL) else { throw HookInstallError.settingsUnreadable(fileName) }
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) { return [:] }
        guard let any = try? JSONSerialization.jsonObject(with: data) else { throw HookInstallError.settingsUnreadable(fileName) }
        guard let obj = any as? [String: Any] else { throw HookInstallError.settingsNotAnObject(fileName) }
        return obj
    }

    private func save(_ root: [String: Any]) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: configURL.path) {
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "")
            let backup = configURL.deletingLastPathComponent().appendingPathComponent("\(fileName).dumpcito-backup-\(stamp)")
            if !fm.fileExists(atPath: backup.path) { try fm.copyItem(at: configURL, to: backup) }
        }
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: configURL, options: .atomic)
    }
}
