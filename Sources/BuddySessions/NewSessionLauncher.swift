import Foundation

/// How to open a brand-new interactive Claude Code session with an initial prompt.
public enum NewSessionStrategy: Sendable, Equatable {
    /// Open the folder in VS Code, then `vscode://anthropic.claude-code/open?prompt=...`.
    /// The extension's URI handler pre-fills the new conversation's input box; the user presses Enter.
    case vscodeURI
}

/// One process invocation, optionally preceded by a pause (VS Code needs a moment to open the window).
public struct LaunchStep: Sendable, Equatable {
    public var executable: String
    public var arguments: [String]
    public var delay: TimeInterval
    public init(_ executable: String, _ arguments: [String], delay: TimeInterval = 0) {
        self.executable = executable; self.arguments = arguments; self.delay = delay
    }
}

public typealias LaunchRunner = @Sendable (LaunchStep) async throws -> Void

public enum NewSessionLauncher {
    static let vscodeScheme = "vscode://anthropic.claude-code/open"

    static func steps(for strategy: NewSessionStrategy, cwd: String, prompt: String) -> [LaunchStep] {
        switch strategy {
        case .vscodeURI:
            return [
                LaunchStep("/usr/bin/open", ["-a", "Visual Studio Code", "--", cwd]),
                LaunchStep("/usr/bin/open", [vscodeURL(prompt: prompt)], delay: 2),
            ]
        }
    }

    static func vscodeURL(prompt: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return vscodeScheme + "?prompt=" + (prompt.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")
    }

    public static let processRunner: LaunchRunner = { step in
        if step.delay > 0 { try await Task.sleep(nanoseconds: UInt64(step.delay * 1_000_000_000)) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: step.executable)
        process.arguments = step.arguments
        let err = Pipe()
        process.standardError = err
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw SessionDispatchError.launchFailed(msg.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
