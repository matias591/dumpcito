import Foundation
import Observation

public enum BuddyMenuAction: Sendable {
    case summon, hide, quit, fixCalendar, showTour, connect(AgentTool), disconnect(AgentTool), resetProgress
}

/// Everything the menu shows and changes. The app owns persistence and applies each change
/// (`onChange`); the UI only reads and writes these values and fires actions.
@MainActor @Observable
public final class BuddySettings {
    public var skin: BuddySkin { didSet { if skin != oldValue { onChange() } } }
    public var soundsOn: Bool { didSet { if soundsOn != oldValue { onChange() } } }
    public var followOn: Bool { didSet { if followOn != oldValue { onChange() } } }
    public var paused: Bool { didSet { if paused != oldValue { onChange() } } }
    public var launchAtLogin: Bool { didSet { if launchAtLogin != oldValue { onChange() } } }
    /// Mac stays awake with the lid closed (`pmset disablesleep`). Needs an admin prompt to change.
    public var keepAwake = false { didSet { if keepAwake != oldValue { onChange() } } }
    /// Auto-off for stay awake in minutes; 0 = until switched off. Applies the next time it is switched on.
    public var keepAwakeMinutes = 240
    /// When the running stay-awake session ends by itself, if it has a limit.
    public var keepAwakeUntil: Date?
    /// Levels are opt-in: nothing is counted until this is on.
    public var progressOn: Bool { didSet { if progressOn != oldValue { onChange() } } }
    public var progress: ProgressSummary?

    /// One-line calendar state for the menu, and whether clicking it can fix something.
    public var calendarStatus = "Calendar"
    public var calendarNeedsFix = false
    /// Tools whose hook entries Dumpcito has installed.
    public var connectedTools: Set<AgentTool> = []
    /// Connected tools that have sent at least one event since they were connected (the live test tick).
    public var activeTools: Set<AgentTool> = []
    /// Tools that look installed on this Mac.
    public var presentTools: Set<AgentTool> = []

    public var onChange: () -> Void = {}
    public var onAction: (BuddyMenuAction) -> Void = { _ in }

    public init(skin: BuddySkin = .jelly, soundsOn: Bool = true, followOn: Bool = true,
                paused: Bool = false, launchAtLogin: Bool = false, progressOn: Bool = false) {
        self.skin = skin; self.soundsOn = soundsOn; self.followOn = followOn
        self.paused = paused; self.launchAtLogin = launchAtLogin; self.progressOn = progressOn
    }
}
