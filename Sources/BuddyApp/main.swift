import AppKit
import AVFoundation
import BuddySessions
import EventKit
import Speech

// The AI tools run `Dumpcito --hook --tool <tool>` on session events; handle it before any UI starts.
if CommandLine.arguments.contains("--hook") {
    let args = CommandLine.arguments
    let tool = args.firstIndex(of: "--tool").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } ?? "claude"
    AttentionHook.runFromStdin(tool: tool)
    exit(0)
}

// `open -a Buddy --args --diagnose <file>`: write what macOS currently allows this exact build to do, then quit.
// Must run through `open` so the permissions checked are Buddy's own, not the launching shell's.
if let i = CommandLine.arguments.firstIndex(of: "--diagnose"), i + 1 < CommandLine.arguments.count {
    let exe = Bundle.main.executablePath ?? ""
    let report = """
    screenRecording: \(CGPreflightScreenCaptureAccess())
    microphone: \(AVCaptureDevice.authorizationStatus(for: .audio).rawValue) (3 = allowed)
    speech: \(SFSpeechRecognizer.authorizationStatus().rawValue) (3 = allowed)
    calendar: \(EKEventStore.authorizationStatus(for: .event).rawValue) (3 = full access)
    claudeHookInstalled: \(HookInstaller(tool: .claude, executable: exe).isInstalled())
    codexHookInstalled: \(HookInstaller(tool: .codex, executable: exe).isInstalled())
    cursorHookInstalled: \(HookInstaller(tool: .cursor, executable: exe).isInstalled())
    executable: \(Bundle.main.executablePath ?? "?")
    """
    try? report.write(toFile: CommandLine.arguments[i + 1], atomically: true, encoding: .utf8)
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
