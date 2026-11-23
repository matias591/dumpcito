import BuddyCore
import SwiftUI

/// What the walkthrough can ask the app to do. Each returns whether it worked, so the step can show a tick.
public struct OnboardingActions {
    public var connectTool: (AgentTool) -> Bool
    public var refreshTools: () -> Void
    public var allowCalendar: () async -> Bool
    public var allowVoice: () async -> Bool
    public var finish: () -> Void

    public init(connectTool: @escaping (AgentTool) -> Bool, refreshTools: @escaping () -> Void, allowCalendar: @escaping () async -> Bool,
                allowVoice: @escaping () async -> Bool, finish: @escaping () -> Void) {
        self.connectTool = connectTool; self.refreshTools = refreshTools; self.allowCalendar = allowCalendar
        self.allowVoice = allowVoice; self.finish = finish
    }
}

/// First-run walkthrough: what Buddy does, pick a skin, connect your coding agents, grant access.
/// Every step can be skipped; nothing is changed on the Mac until a button says so.
public struct OnboardingView: View {
    private enum Step: Int, CaseIterable { case welcome, how, skin, claude, access, done }

    private let settings: BuddySettings
    private let actions: OnboardingActions

    @State private var step = Step.welcome
    @State private var calendarDone = false
    @State private var voiceDone = false
    @State private var forward = true

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(settings: BuddySettings, actions: OnboardingActions) {
        self.settings = settings
        self.actions = actions
        #if DEBUG
        if let raw = UserDefaults.standard.object(forKey: "buddy.debugTourStep") as? Int, let s = Step(rawValue: raw) {
            _step = State(initialValue: s)
        }
        #endif
    }

    public static let size = CGSize(width: 520, height: 540)

    public var body: some View {
        let theme = Theme(isDark: colorScheme == .dark, highContrast: contrast == .increased)
        VStack(spacing: 0) {
            ZStack {
                content
                    .id(step)
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                        removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            footer
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(theme.solidSurface)
        .environment(\.buddyTheme, theme)
        .animation(reduceMotion ? Motion.reduced : Motion.surface, value: step)
    }

    // MARK: Steps

    @ViewBuilder private var content: some View {
        switch step {
        case .welcome:
            page(title: "Meet Dumpcito",
                 body: "A small companion on your desktop. It taps you when Claude Code needs an answer, or a meeting is about to start, and stays out of the way the rest of the time.", artFirst: true) {
                SkinPreview(skin: settings.skin, side: 120)
            }
        case .how:
            page(title: "How it works", body: nil) {
                VStack(alignment: .leading, spacing: 18) {
                    Fact(symbol: "bell", title: "It speaks up only when it matters",
                         text: "A permission prompt or question in a Claude Code session, a session finishing, or a meeting about to start.")
                    Fact(symbol: "cursorarrow.motionlines", title: "It finds you",
                         text: "It hops to the screen you are on and trails your cursor while it needs you. Move toward it and it holds still so you can click.")
                    Fact(symbol: "mic", title: "Hold Ctrl+Option+Space to talk",
                         text: "Say something while it grabs a screenshot, then send both to a Claude Code session. Speech is recognised on your Mac.")
                    Fact(symbol: "contextualmenu.and.cursorarrow", title: "Right-click it for everything else",
                         text: "Skins, sounds, pause, and this tour.")
                }
                .padding(.horizontal, 40)
            }
        case .skin:
            page(title: "Pick a look", body: "You can change it any time from the menu.") {
                HStack(spacing: 12) {
                    ForEach(BuddySkin.allCases) { skin in
                        SkinCard(skin: skin, selected: settings.skin == skin) { settings.skin = skin }
                    }
                }
                .padding(.horizontal, 28)
            }
        case .claude:
            page(title: "Know when your agents need you",
                 body: "Connecting adds a small hook to each tool's hook file (~/.claude/settings.json, ~/.codex/hooks.json, ~/.cursor/hooks.json). A backup is kept, nothing else in the file changes, and you can disconnect from the menu.") {
                VStack(spacing: 10) {
                    ForEach(AgentTool.allCases, id: \.self) { tool in
                        ToolRow(tool: tool,
                                present: settings.presentTools.contains(tool),
                                connected: settings.connectedTools.contains(tool),
                                active: settings.activeTools.contains(tool)) {
                            _ = actions.connectTool(tool)
                        }
                    }
                    Text("A tick next to a tool means Dumpcito saw it work. Start a session in that tool and it appears within a second or two.")
                        .font(BuddyFont.meta).foregroundStyle(theme.ink3).multilineTextAlignment(.center)
                        .padding(.horizontal, 48).padding(.top, 4)
                }
                .padding(.horizontal, 28)
                .task {
                    while !Task.isCancelled {
                        actions.refreshTools()
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                    }
                }
            }
        case .access:
            page(title: "Allow access", body: "Both are optional. Everything stays on your Mac.") {
                VStack(spacing: 14) {
                    AccessRow(title: "Calendar", text: "Meeting nudges. Reads the macOS Calendar app, so add your Google account in System Settings, Internet Accounts, first.",
                              done: calendarDone) { calendarDone = await actions.allowCalendar() }
                    AccessRow(title: "Voice and screenshots", text: "Microphone, speech recognition and screen recording for hold-to-talk. Screen recording needs a Dumpcito restart after you allow it.",
                              done: voiceDone) { voiceDone = await actions.allowVoice() }
                }
                .padding(.horizontal, 36)
            }
        case .done:
            page(title: "You're set", body: "Drag me anywhere. Right-click me for the menu, or use the icon in the menu bar. Replay this tour from there whenever you like.", artFirst: true) {
                SkinPreview(skin: settings.skin, side: 120)
            }
        }
    }

    /// `artFirst`: a big character above the title (welcome, done). Otherwise the title leads and the content follows.
    private func page<Art: View>(title: String, body: String?, artFirst: Bool = false, @ViewBuilder art: () -> Art) -> some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            if artFirst { art() }
            Text(title).font(.system(size: 26, weight: .semibold)).foregroundStyle(theme.ink)
            if let body {
                Text(body).font(.system(size: 14)).foregroundStyle(theme.ink2)
                    .multilineTextAlignment(.center).lineSpacing(2)
                    .padding(.horizontal, 56).fixedSize(horizontal: false, vertical: true)
            }
            if !artFirst { art().padding(.top, 8) }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            if step != .welcome && step != .done {
                PillButton(title: "Back") { go(-1) }
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.rawValue) { s in
                    Circle().fill(s == step ? theme.ink : theme.ink.opacity(0.2)).frame(width: 6, height: 6)
                }
            }
            Spacer()
            if step == .done {
                PillButton(title: "Start", prominent: true) { actions.finish() }
            } else {
                PillButton(title: nextTitle, prominent: true) { go(1) }
            }
        }
        .padding(.horizontal, 24)
        .frame(height: 64)
        .overlay(alignment: .top) { Rectangle().fill(theme.hairline).frame(height: 0.5) }
    }

    private var nextTitle: String {
        switch step {
        case .welcome: "Get started"
        case .claude: settings.connectedTools.isEmpty ? "Skip" : "Next"
        case .access: calendarDone || voiceDone ? "Next" : "Skip"
        default: "Next"
        }
    }

    private func go(_ delta: Int) {
        forward = delta > 0
        step = Step(rawValue: min(max(step.rawValue + delta, 0), Step.allCases.count - 1)) ?? step
    }

    private var theme: Theme { Theme(isDark: colorScheme == .dark, highContrast: contrast == .increased) }
}

// MARK: - Pieces

private struct Fact: View {
    let symbol: String, title: String, text: String
    @Environment(\.buddyTheme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.system(size: 17, weight: .medium)).foregroundStyle(theme.ink)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(BuddyFont.title).foregroundStyle(theme.ink)
                Text(text).font(BuddyFont.body).foregroundStyle(theme.ink2).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct SkinCard: View {
    let skin: BuddySkin, selected: Bool
    let action: () -> Void
    @Environment(\.buddyTheme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                SkinPreview(skin: skin, side: 84)
                Text(skin.displayName).font(BuddyFont.title).foregroundStyle(theme.ink)
                Text(skin.tagline).font(BuddyFont.meta).foregroundStyle(theme.ink3)
                    .multilineTextAlignment(.center).lineLimit(3, reservesSpace: true)
            }
            .padding(.vertical, 14).padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(selected ? theme.fillSelected : (hovering ? theme.fillHover : .clear)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(selected ? theme.ink.opacity(0.5) : theme.hairline, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("\(skin.displayName) skin")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct ToolRow: View {
    let tool: AgentTool
    let present: Bool, connected: Bool, active: Bool
    let connect: () -> Void
    @Environment(\.buddyTheme) private var theme

    private var detail: String {
        if connected {
            if active { return "Working. Dumpcito saw it send an event." }
            return tool.connectNote ?? "Connected. Start a session to confirm."
        }
        return present ? "Found on this Mac" : "Not found on this Mac"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(tool.displayName).font(BuddyFont.title).foregroundStyle(theme.ink)
                Text(detail).font(BuddyFont.meta).foregroundStyle(theme.ink3).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if connected {
                Image(systemName: active ? "checkmark.circle.fill" : "clock").foregroundStyle(active ? theme.ink : theme.ink3)
            } else {
                PillButton(title: "Connect", prominent: present, action: connect)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.fillHover))
    }
}

private struct AccessRow: View {
    let title: String, text: String, done: Bool
    let allow: () async -> Void
    @Environment(\.buddyTheme) private var theme

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(BuddyFont.title).foregroundStyle(theme.ink)
                Text(text).font(BuddyFont.meta).foregroundStyle(theme.ink3).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if done {
                Image(systemName: "checkmark").foregroundStyle(theme.ink)
            } else {
                PillButton(title: "Allow") { Task { await allow() } }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.fillHover))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(theme.hairline, lineWidth: 0.5))
    }
}
