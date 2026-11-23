import AppKit
import BuddyCalendar
import BuddyCapture
import BuddyCore
import BuddyProgress
import BuddySessions
import BuddyUI
import EventKit
import ServiceManagement
import SwiftUI

/// Owns the BuddyModel and the floating panel. The lead plugs providers in at the INTEGRATION markers.
@MainActor
final class BuddyController {
    static let pausedKey = "buddy.paused"

    let model = BuddyModel()
    private(set) var panel: BuddyPanel!

    var isPaused: Bool {
        get { UserDefaults.standard.bool(forKey: Self.pausedKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.pausedKey) }
    }

    private let sessions: SessionProviding = SessionStore(copyToClipboard: { text in
        DispatchQueue.main.async {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    })
    private let meetings: MeetingProviding = EventKitMeetingProvider()
    private let watcher: MeetingWatcher
    private let capture = HotkeyCaptureService()
    private let compose = BuddyComposeBridge()
    private var moodReset: Task<Void, Never>?
    private var isSending = false
    private let progressStore = ProgressStore()
    private var progressState = ProgressState()
    static let progressKey = "dumpcito.progress"
    /// A needs-you or meeting alert that arrived while the user was mid-capture; shown when they are done.
    private var deferred: (mood: BuddyMood, sound: BuddySound, after: TimeInterval)?
    private var alertShownAt = Date.distantPast
    let sounds = SoundPlayer()
    private(set) var follower: ScreenFollower!
    let settings = BuddySettings()
    private(set) var menu: MenuPanel!
    private var applyingSettings = false
    static let skinKey = "buddy.skin"

    init() {
        watcher = MeetingWatcher(provider: meetings)
        panel = BuddyPanel(rootView: BuddyRootView(model: model, composeBridge: compose))
        panel.onAnchorChange = { [model] top, leading in
            model.anchoredTop = top
            model.anchoredLeading = leading
        }
        follower = ScreenFollower(panel: panel, model: model)
        wireCallbacks()
        loadSettings()
        menu = MenuPanel(settings: settings)
        panel.onSecondaryClick = { [weak self] in self?.showMenu(near: self?.panel.frame ?? .zero) }
    }

    // MARK: Settings

    private func loadSettings() {
        let skin = UserDefaults.standard.string(forKey: Self.skinKey).flatMap(BuddySkin.init(rawValue:)) ?? .jelly
        settings.skin = skin
        model.skin = skin
        settings.soundsOn = sounds.isEnabled
        settings.followOn = follower.isEnabled
        settings.paused = isPaused
        settings.launchAtLogin = launchAtLogin
        syncKeepAwake()
        settings.progressOn = UserDefaults.standard.bool(forKey: Self.progressKey)
        if settings.progressOn { progressState = progressStore.load() }
        refreshProgress()
        settings.onChange = { [weak self] in self?.applySettings() }
        settings.onAction = { [weak self] in self?.perform($0) }
    }

    private func applySettings() {
        guard !applyingSettings else { return }
        applyingSettings = true
        defer { applyingSettings = false }
        UserDefaults.standard.set(settings.skin.rawValue, forKey: Self.skinKey)
        model.skin = settings.skin
        sounds.isEnabled = settings.soundsOn
        follower.isEnabled = settings.followOn
        isPaused = settings.paused
        if settings.progressOn != UserDefaults.standard.bool(forKey: Self.progressKey) {
            UserDefaults.standard.set(settings.progressOn, forKey: Self.progressKey)
            if settings.progressOn { progressState = progressStore.load() }
            refreshProgress()
        }
        if settings.launchAtLogin != launchAtLogin { setLaunchAtLogin(settings.launchAtLogin) }
        if settings.keepAwake != KeepAwake.isOn() { setKeepAwake(settings.keepAwake) }
    }

    /// Opens the buddy's menu next to `anchor` (the buddy, or the menu bar icon).
    func showMenu(near anchor: NSRect) {
        if menu.isShown { menu.close(); return }
        if menu.justClosed { return }
        let status = calendarStatus()
        settings.calendarStatus = status.title
        settings.calendarNeedsFix = status.fixURL != nil
        calendarFixURL = status.fixURL
        refreshTools()
        settings.launchAtLogin = launchAtLogin
        syncKeepAwake()
        refreshProgress()
        menu.show(near: anchor)
    }

    private var calendarFixURL: URL?

    // MARK: Progress

    private func refreshProgress() {
        if settings.progressOn {
            let summary = ProgressEngine.summary(progressState)
            settings.progress = summary
            model.stage = summary.stage
        } else {
            settings.progress = nil
            model.stage = 1
        }
    }

    /// Counts one event. A level-up shows a short toast, but only when nothing else is on screen.
    private func recordProgress(_ track: ProgressTrack, key: String) {
        guard settings.progressOn, !isPaused else { return }
        let before = ProgressEngine.summary(progressState).level
        guard ProgressEngine.record(track, key: key, state: &progressState) else { return }
        progressStore.save(progressState)
        refreshProgress()
        let after = settings.progress?.level ?? before
        if after > before, model.mood == .idle {
            settle(.sent("Level \(after)! \(model.stage > 1 ? "Dumpcito is growing" : "Nice pace")"), after: 6)
            playSound(.finished)
        }
    }

    private func hookInstaller(_ tool: AgentTool) -> HookInstaller {
        HookInstaller(tool: tool, executable: Bundle.main.executablePath ?? "/Applications/Dumpcito.app/Contents/MacOS/Dumpcito")
    }

    /// When each tool was connected in this launch; the live test counts only events after that.
    private var connectedAt: [AgentTool: Int64] = [:]

    /// Refreshes the connect checklist: which tools are installed, connected, and have been seen working.
    func refreshTools() {
        let records = StateStore().readAll()
        var connected: Set<AgentTool> = [], active: Set<AgentTool> = [], present: Set<AgentTool> = []
        for tool in AgentTool.allCases {
            if HookInstaller.isToolPresent(tool) { present.insert(tool) }
            guard hookInstaller(tool).isInstalled() else { continue }
            connected.insert(tool)
            let since = connectedAt[tool] ?? 0
            if records.contains(where: { $0.tool == tool.rawValue && $0.touched > since }) { active.insert(tool) }
        }
        if settings.connectedTools != connected { settings.connectedTools = connected }
        if settings.activeTools != active { settings.activeTools = active }
        if settings.presentTools != present { settings.presentTools = present }
    }

    private func perform(_ action: BuddyMenuAction) {
        switch action {
        case .summon: follower.summon()
        case .hide: panel.orderOut(nil)
        case .quit: NSApp.terminate(nil)
        case .fixCalendar: if let url = calendarFixURL { NSWorkspace.shared.open(url) }
        case .showTour: onShowTour()
        case .connect(let tool): connect(tool)
        case .disconnect(let tool): disconnect(tool)
        case .resetProgress:
            progressStore.delete()
            progressState = ProgressState()
            refreshProgress()
        }
    }

    /// Set by the app delegate: opens the walkthrough window.
    var onShowTour: () -> Void = {}

    @discardableResult
    func connect(_ tool: AgentTool) -> Bool {
        do {
            try hookInstaller(tool).install()
            connectedAt[tool] = Int64(Date().timeIntervalSince1970 * 1000)
            refreshTools()
            settle(.sent(tool.connectNote ?? "Connected to \(tool.displayName)"), after: tool.connectNote == nil ? 3 : 10)
            return true
        } catch {
            settle(.error(error.localizedDescription), after: 8)
            return false
        }
    }

    func disconnect(_ tool: AgentTool) {
        do {
            try hookInstaller(tool).uninstall()
            connectedAt[tool] = nil
            refreshTools()
            settle(.sent("Disconnected from \(tool.displayName)"), after: 3)
        } catch {
            settle(.error(error.localizedDescription), after: 8)
        }
    }

    func start() {
        panel.orderFrontRegardless()
        follower.start()
        CaptureCleanup.pruneOld()
        Task { await runSessions() }
        Task { await runSessionEvents() }
        // First run: the walkthrough explains each permission before macOS asks for it.
        if hasOnboarded { startPermissionServices(promptForPermissions: true) }
    }

    static let onboardedKey = "buddy.onboarded"
    var hasOnboarded: Bool {
        get { UserDefaults.standard.bool(forKey: Self.onboardedKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.onboardedKey) }
    }

    private var permissionServicesStarted = false

    /// Calendar nudges and the hold-to-talk hotkey. Started once; the walkthrough starts them without prompting,
    /// and each "Allow" button there asks for its own permission.
    func startPermissionServices(promptForPermissions: Bool) {
        guard !permissionServicesStarted else { return }
        permissionServicesStarted = true
        Task { await runMeetings(prompting: promptForPermissions) }
        Task { await runCapture(prompting: promptForPermissions) }
    }

    func allowCalendar() async -> Bool {
        let granted = await meetings.requestAccess()
        startPermissionServices(promptForPermissions: false)
        return granted
    }

    func allowVoice() async -> Bool {
        await capture.requestPermissions()
        startPermissionServices(promptForPermissions: false)
        return CGPreflightScreenCaptureAccess()
    }

    // MARK: Callbacks from the UI

    private func wireCallbacks() {
        model.onPick = { [weak self] target in
            guard let self, case let .choosingTarget(result) = self.model.mood else { return }
            self.send(prompt: result.transcript, screenshot: result.screenshotURL, to: target)
        }
        compose.onCompose = { [weak self] text, target in
            self?.send(prompt: text, screenshot: nil, to: target)
        }
        model.onJoinMeeting = { [weak self] meeting in
            if let url = meeting.joinURL { NSWorkspace.shared.open(url) }
            if meeting.end.timeIntervalSince(meeting.start) >= 15 * 60 { self?.recordProgress(.meetings, key: meeting.id) }
            self?.settle(.idle, after: 0)
        }
        model.onDismiss = { [weak self] in
            guard let self else { return }
            self.settle(.idle, after: 0)
        }
        model.onOpenSession = { _ in
            // VS Code exposes no way to focus a specific Claude Code panel, so bring the app forward.
            NSWorkspace.shared.launchApplication("Visual Studio Code")
        }
    }

    private func send(prompt: String, screenshot: URL?, to target: DispatchTarget) {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = text.isEmpty && screenshot != nil ? "Look at this screenshot." : text
        // Dispatch can wait seconds for the session to pick the prompt up; a second press must not send it twice.
        guard !isSending else { return }
        isSending = true
        settle(.sent("Sending..."), after: 0)
        Task {
            defer { isSending = false }
            do {
                try await sessions.dispatch(prompt: prompt, screenshot: screenshot, to: target)
                settle(.sent(Self.sentLabel(for: target)), after: 3)
            } catch {
                settle(.error(error.localizedDescription), after: 8)
            }
        }
    }

    private static func sentLabel(for target: DispatchTarget) -> String {
        switch target {
        case .session: "Copied. Paste it into your session"
        case .newSession: "Opened in VS Code, press Enter to send"
        }
    }

    /// Show a transient mood, then fall back to idle unless something newer replaced it.
    private func settle(_ mood: BuddyMood, after seconds: TimeInterval) {
        moodReset?.cancel()
        model.mood = mood
        if case .sessionNeedsYou = mood { alertShownAt = Date() }
        if seconds > 0 {
            moodReset = Task { [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled, self?.model.mood == mood else { return }
                self?.model.mood = .idle
                self?.replayDeferred()
            }
        }
        replayDeferred()
    }

    private func replayDeferred() {
        guard let d = deferred, !isBusyWithUser, !isPaused else { return }
        deferred = nil
        settle(d.mood, after: d.after)
        playSound(d.sound)
    }

    /// No sound for an alert nobody can see (Buddy hidden from the menu).
    private func playSound(_ sound: BuddySound) {
        if panel.isVisible { sounds.play(sound) }
    }

    // MARK: Providers -> model

    private func runSessions() async {
        while !Task.isCancelled {
            let live = await sessions.liveSessions()
            let recent = await sessions.recentSessions(limit: 5)
            // @Observable fires on every assignment, so only write when something changed.
            if live != model.liveSessions { model.liveSessions = live }
            if recent != model.recentSessions { model.recentSessions = recent }
            // The alert is over once the session stops asking (prompt answered, session moved on or ended).
            // A fresh alert is left alone for a few seconds: this snapshot may predate it.
            if case let .sessionNeedsYou(shown) = model.mood, Date().timeIntervalSince(alertShownAt) > 4,
               !live.contains(where: { $0.id == shown.id && $0.needsAttention }) {
                model.mood = .idle
                replayDeferred()
            }
            try? await Task.sleep(for: .seconds(3))
        }
    }

    private func runSessionEvents() async {
        for await event in sessions.events() {
            guard !isPaused else { continue }
            switch event {
            case let .finished(session):
                // One count per session per half hour: every turn ending is not a finished session.
                recordProgress(.claude, key: "\(session.id):\(Int(Date().timeIntervalSince1970 / 1800))")
                guard !isBusyWithUser else { continue }
                // A finished session must not bury a session that is waiting on the user.
                if case .sessionNeedsYou = model.mood { continue }
                settle(.sessionFinished(session), after: 10)
                playSound(.finished)
            case let .needsAttention(session):
                if isBusyWithUser {
                    deferred = (.sessionNeedsYou(session), .needsYou, 0)
                } else {
                    settle(.sessionNeedsYou(session), after: 0)
                    playSound(.needsYou)
                }
            }
        }
    }

    private func runMeetings(prompting: Bool) async {
        // Wait for access instead of giving up: the user may grant it later from System Settings or the tour.
        while !Task.isCancelled {
            switch EKEventStore.authorizationStatus(for: .event) {
            case .fullAccess: break
            case .notDetermined where prompting:
                _ = await meetings.requestAccess()
                continue
            default:
                try? await Task.sleep(for: .seconds(20))
                continue
            }
            break
        }
        guard !Task.isCancelled else { return }
        Task { model.nextMeeting = await watcher.nextMeeting() }
        Task {
            while !Task.isCancelled {
                model.nextMeeting = await watcher.nextMeeting()
                try? await Task.sleep(for: .seconds(60))
            }
        }
        for await meeting in await watcher.nudges() {
            guard !isPaused else { continue }
            if isBusyWithUser {
                deferred = (.meetingSoon(meeting), .meeting, 120)
            } else {
                settle(.meetingSoon(meeting), after: 120)
                playSound(.meeting)
            }
        }
    }

    private func runCapture(prompting: Bool) async {
        // Subscribe first so a denied permission is reported instead of emitted to nobody.
        let stream = capture.events()
        if prompting { await capture.requestPermissions() }
        for await event in stream {
            switch event {
            case .began: settle(.listening(partial: ""), after: 0)
            case let .partial(text): model.mood = .listening(partial: text)
            case let .finished(result): settle(.choosingTarget(result), after: 0)
            case let .failed(message): settle(.error(message), after: 8)
            }
        }
    }

    /// Don't replace a capture or target picker the user is in the middle of.
    private var isBusyWithUser: Bool {
        switch model.mood {
        case .listening, .choosingTarget: true
        default: false
        }
    }

    /// Menu line + whether it needs fixing. Reads EventKit directly: the buddy only sees calendars macOS has.
    func calendarStatus() -> (title: String, fixURL: URL?) {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            let cals = EKEventStore().calendars(for: .event)
            let google = cals.contains { $0.source.title.localizedCaseInsensitiveContains("google") || $0.source.title.contains("@") }
            if cals.isEmpty || !google {
                return ("Calendar: no Google account, click to add", URL(string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension"))
            }
            return ("Calendar: connected (\(cals.count) calendars)", nil)
        case .notDetermined:
            return ("Calendar: waiting for permission", nil)
        default:
            return ("Calendar: access denied, click to allow", URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"))
        }
    }

    var isVisible: Bool { panel.isVisible }

    func toggleVisible() {
        if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
    }

    var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Dumpcito: launch-at-login change failed: \(error.localizedDescription)")
            settle(.error("Could not change launch at login. Move Dumpcito to Applications and try again."), after: 8)
        }
        settings.launchAtLogin = launchAtLogin
    }

    private static let awakeMinutesKey = "keepAwakeMinutes"
    private static let awakeUntilKey = "keepAwakeUntil"

    /// Matches the real `pmset` state and the saved end time, so a timer that fired while Dumpcito was closed
    /// does not leave a stale "Turns off at" line.
    private func syncKeepAwake() {
        let defaults = UserDefaults.standard
        applyingSettings = true
        defer { applyingSettings = false }
        settings.keepAwake = KeepAwake.isOn()
        if defaults.object(forKey: Self.awakeMinutesKey) != nil { settings.keepAwakeMinutes = defaults.integer(forKey: Self.awakeMinutesKey) }
        let until = defaults.object(forKey: Self.awakeUntilKey) as? Date
        settings.keepAwakeUntil = settings.keepAwake ? until.flatMap { $0 > Date() ? $0 : nil } : nil
    }

    /// The admin prompt blocks until answered, so it runs off the main thread; the menu switch then
    /// settles on whatever macOS actually reports (cancelled prompt = switch snaps back).
    func setKeepAwake(_ on: Bool) {
        let minutes = settings.keepAwakeMinutes
        UserDefaults.standard.set(minutes, forKey: Self.awakeMinutesKey)
        Task {
            let ok = await Task.detached { KeepAwake.set(on, minutes: minutes) }.value
            let defaults = UserDefaults.standard
            if ok && on && minutes > 0 { defaults.set(Date().addingTimeInterval(Double(minutes) * 60), forKey: Self.awakeUntilKey) }
            else { defaults.removeObject(forKey: Self.awakeUntilKey) }
            syncKeepAwake()
            if !ok { settle(.error("Could not change stay awake. The password prompt was cancelled."), after: 6) }
        }
    }
}

/// Wraps `pmset disablesleep`, the same switch as `sudo pmset -a disablesleep 1`.
/// With a limit, the one admin prompt also starts a root `sleep` that switches it back off, so the end
/// needs no second prompt and still happens if Dumpcito is quit.
enum KeepAwake {
    private static let marker = "dumpcito-awake-timer"

    static func isOn() -> Bool {
        let out = run("/usr/bin/pmset", ["-g"])
        return out.contains { $0.contains("SleepDisabled") && $0.split(whereSeparator: \.isWhitespace).last == "1" }
    }

    static func set(_ on: Bool, minutes: Int) -> Bool {
        // `[d]` keeps pkill from matching this very command line.
        let stopTimer = "/usr/bin/pkill -f '[d]umpcito-awake-timer'; "
        var cmd = stopTimer + "/usr/bin/pmset -a disablesleep \(on ? 1 : 0)"
        if on && minutes > 0 {
            cmd += "; /bin/sh -c '/bin/sleep \(minutes * 60); /usr/bin/pmset -a disablesleep 0' \(marker) >/dev/null 2>&1 &"
        }
        let script = "do shell script \"\(cmd)\" with administrator privileges"
        _ = run("/usr/bin/osascript", ["-e", script])
        return isOn() == on
    }

    private static func run(_ path: String, _ args: [String]) -> [String] {
        let p = Process(), pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: path); p.arguments = args
        p.standardOutput = pipe; p.standardError = Pipe()
        guard (try? p.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
    }
}
