import BuddyCore
import SwiftUI

/// The buddy's own menu: same glass, type and spacing as its bubbles, shown beside the character.
public struct BuddyMenuView: View {
    private let settings: BuddySettings
    private let dismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    public init(settings: BuddySettings, dismiss: @escaping () -> Void) {
        self.settings = settings
        self.dismiss = dismiss
    }

    public static let width: CGFloat = 272

    public var body: some View {
        let theme = Theme(isDark: colorScheme == .dark, highContrast: contrast == .increased)
        VStack(alignment: .leading, spacing: 2) {
            if settings.progressOn, let p = settings.progress { ProgressCard(summary: p) }
            skins
            Divider().overlay(theme.hairline).padding(.vertical, 6)
            SwitchRow(title: "Sounds", isOn: Binding(get: { settings.soundsOn }, set: { settings.soundsOn = $0 }))
            SwitchRow(title: "Follow me across screens", isOn: Binding(get: { settings.followOn }, set: { settings.followOn = $0 }))
            SwitchRow(title: "Pause nudges", detail: "No alerts or sounds", isOn: Binding(get: { settings.paused }, set: { settings.paused = $0 }))
            SwitchRow(title: "Levels", detail: "Experimental. Counts only, on this Mac", isOn: Binding(get: { settings.progressOn }, set: { settings.progressOn = $0 }))
            SwitchRow(title: "Stay awake, lid closed", detail: awakeDetail, isOn: Binding(get: { settings.keepAwake }, set: { settings.keepAwake = $0 }))
            if !settings.keepAwake {
                DurationChips(minutes: Binding(get: { settings.keepAwakeMinutes }, set: { settings.keepAwakeMinutes = $0 }))
            }
            SwitchRow(title: "Launch at login", isOn: Binding(get: { settings.launchAtLogin }, set: { settings.launchAtLogin = $0 }))
            Divider().overlay(theme.hairline).padding(.vertical, 6)
            ActionRow(title: "Bring Dumpcito here") { fire(.summon) }
            ForEach(AgentTool.allCases, id: \.self) { tool in
                let connected = settings.connectedTools.contains(tool)
                ActionRow(title: connected ? "\(tool.displayName): connected" : "Connect \(tool.displayName)",
                          detail: connected ? (settings.activeTools.contains(tool) ? "Working. Click to disconnect" : "Waiting for its first event. Click to disconnect")
                                            : (settings.presentTools.contains(tool) ? "Needed for alerts" : "Not found on this Mac"),
                          muted: connected) { fire(connected ? .disconnect(tool) : .connect(tool)) }
            }
            ActionRow(title: settings.calendarStatus, muted: !settings.calendarNeedsFix, enabled: settings.calendarNeedsFix) { fire(.fixCalendar) }
            ActionRow(title: "Show the tour") { fire(.showTour) }
            if settings.progressOn { ActionRow(title: "Reset levels", detail: "Deletes the counts. Cannot be undone", muted: true) { fire(.resetProgress) } }
            Divider().overlay(theme.hairline).padding(.vertical, 6)
            ActionRow(title: "Hide Dumpcito") { fire(.hide) }
            ActionRow(title: "Quit Dumpcito") { fire(.quit) }
        }
        .padding(8)
        .frame(width: Self.width)
        .glassSurface(cornerRadius: 18)
        .padding(16)
        .environment(\.buddyTheme, theme)
        .animation(Motion.selection, value: settings.skin)
    }

    private var awakeDetail: String {
        guard settings.keepAwake else { return "Asks for your password. Turns itself off" }
        guard let until = settings.keepAwakeUntil else { return "On until you switch it off" }
        return "Turns off at \(until.formatted(date: .omitted, time: .shortened))"
    }

    private func fire(_ action: BuddyMenuAction) {
        dismiss()
        settings.onAction(action)
    }

    private var skins: some View {
        HStack(spacing: 6) {
            ForEach(BuddySkin.allCases) { skin in
                SkinTile(skin: skin, selected: settings.skin == skin) { settings.skin = skin }
            }
        }
        .padding(.top, 2)
    }
}

// MARK: - Pieces

private struct SkinTile: View {
    let skin: BuddySkin
    let selected: Bool
    let action: () -> Void

    @Environment(\.buddyTheme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                SkinPreview(skin: skin, side: 52)
                Text(skin.displayName)
                    .font(BuddyFont.label)
                    .foregroundStyle(selected ? theme.ink : theme.ink2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? theme.fillSelected : (hovering ? theme.fillHover : .clear)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(selected ? theme.ink.opacity(0.5) : .clear, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("\(skin.displayName) skin")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct DurationChips: View {
    @Binding var minutes: Int
    @Environment(\.buddyTheme) private var theme

    private static let options: [(label: String, minutes: Int)] = [("1h", 60), ("4h", 240), ("8h", 480), ("No limit", 0)]

    var body: some View {
        HStack(spacing: 6) {
            Text("Auto-off").font(BuddyFont.meta).foregroundStyle(theme.ink3)
            ForEach(Self.options, id: \.minutes) { o in
                Button { minutes = o.minutes } label: {
                    Text(o.label).font(BuddyFont.label)
                        .foregroundStyle(minutes == o.minutes ? theme.ink : theme.ink2)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(minutes == o.minutes ? theme.fillSelected : .clear))
                        .overlay(Capsule().strokeBorder(minutes == o.minutes ? theme.ink.opacity(0.5) : theme.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(minutes == o.minutes ? .isSelected : [])
            }
        }
        .padding(.horizontal, 10).padding(.bottom, 4)
    }
}

private struct SwitchRow: View {
    let title: String
    var detail: String?
    @Binding var isOn: Bool

    @Environment(\.buddyTheme) private var theme
    @State private var hovering = false

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(BuddyFont.body).foregroundStyle(theme.ink)
                    if let detail { Text(detail).font(BuddyFont.meta).foregroundStyle(theme.ink3) }
                }
                Spacer(minLength: 8)
                Capsule()
                    .fill(isOn ? theme.ink : theme.ink.opacity(0.16))
                    .frame(width: 30, height: 18)
                    .overlay(alignment: isOn ? .trailing : .leading) {
                        Circle().fill(isOn ? theme.onInk : theme.ink.opacity(0.7)).frame(width: 14, height: 14).padding(2)
                    }
                    .animation(Motion.selection, value: isOn)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hovering ? theme.fillHover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

private struct ActionRow: View {
    let title: String
    var detail: String?
    var muted = false
    var enabled = true
    let action: () -> Void

    @Environment(\.buddyTheme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(BuddyFont.body).foregroundStyle(muted ? theme.ink2 : theme.ink)
                if let detail { Text(detail).font(BuddyFont.meta).foregroundStyle(theme.ink3) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hovering && enabled ? theme.fillHover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovering = $0 }
    }
}

private struct ProgressCard: View {
    let summary: ProgressSummary
    @Environment(\.buddyTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Level \(summary.level)").font(.system(size: 20, weight: .semibold, design: .rounded)).foregroundStyle(theme.ink)
                Spacer()
                Text(summary.pace).font(BuddyFont.meta).foregroundStyle(theme.ink3)
            }
            Bar(fraction: summary.fraction, height: 6)
            Text(summary.nextLevelXP.map { "\(summary.xp) of \($0) XP to level \(summary.level + 1)" } ?? "\(summary.xp) XP. Top level")
                .font(BuddyFont.meta).foregroundStyle(theme.ink3)
            VStack(spacing: 7) {
                ForEach(summary.tracks) { t in
                    HStack(spacing: 8) {
                        Text(t.name).font(BuddyFont.body).foregroundStyle(theme.ink2)
                        Spacer(minLength: 6)
                        Text("\(t.weekCount) this week").font(BuddyFont.meta).foregroundStyle(theme.ink3)
                        Text("L\(t.level)").font(BuddyFont.label).foregroundStyle(theme.ink)
                    }
                    Bar(fraction: t.fraction, height: 3)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.fillHover))
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct Bar: View {
    let fraction: Double
    let height: CGFloat
    @Environment(\.buddyTheme) private var theme

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.ink.opacity(0.12))
                Capsule().fill(theme.ink).frame(width: max(height, geo.size.width * fraction))
            }
        }
        .frame(height: height)
    }
}
