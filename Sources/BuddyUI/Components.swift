import BuddyCore
import SwiftUI

// MARK: - Status dot

/// working: white dot, slow opacity pulse. idle: grey dot. needs you: hollow amber ring.
/// Shape differs as well as tone, so status never depends on colour alone.
struct StatusDot: View {
    let status: DotStatus
    var size: CGFloat = 8
    var pulses = true
    /// Drawn on the character's dark screen regardless of appearance.
    var onDark = false

    @Environment(\.buddyTheme) private var envTheme
    @Environment(\.buddyAnimationsActive) private var animationsActive
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let theme = onDark ? Theme(isDark: true, highContrast: envTheme.highContrast) : envTheme
        Group {
            switch status {
            case .working:
                ZStack {
                    if pulses && !reduceMotion {
                        // Sonar ping behind a solid core: never reads as the grey idle dot.
                        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animationsActive)) { context in
                            let u = Self.phase(context.date)
                            Circle()
                                .fill(theme.ink)
                                .scaleEffect(1 + 1.1 * u)
                                .opacity(0.45 * (1 - u))
                        }
                    }
                    Circle().fill(theme.ink)
                }
            case .idle:
                Circle().fill(theme.ink.opacity(0.36))
            case .needsYou:
                Circle().strokeBorder(theme.amber, lineWidth: max(1.4, size * 0.2))
            case .dormant:
                RoundedRectangle(cornerRadius: 1).fill(theme.ink.opacity(0.36)).frame(width: size, height: 1.5)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// 0 -> 1 over a 1.8 s cycle, eased out so the ring decelerates as it fades.
    private static func phase(_ date: Date) -> CGFloat {
        let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.8) / 1.8
        return CGFloat(1 - pow(1 - t, 2))
    }
}

// MARK: - Session row

struct SessionRow: View {
    let session: AgentSession
    var highlighted = false
    /// Picker: the selected row shows a return key instead of its age.
    var showsReturnKey = false
    /// From the Recent group: not heartbeating, so no live status.
    var dormant = false

    private var status: DotStatus { dormant ? .dormant : session.dotStatus }

    @Environment(\.buddyTheme) private var theme

    static let height: CGFloat = 40

    var body: some View {
        HStack(spacing: 10) {
            StatusDot(status: status)
                .frame(width: 12)
            VStack(alignment: .leading, spacing: 1) {
                Text(session.title)
                    .font(BuddyFont.rowTitle)
                    .foregroundStyle(theme.ink)
                    .lineLimit(1)
                Text(Fmt.shortPath(session.cwd))
                    .font(BuddyFont.meta)
                    .foregroundStyle(theme.ink3)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 8)
            if showsReturnKey {
                KeyCap(symbol: "return")
            } else if session.needsAttention && !dormant {
                Text("needs you").font(BuddyFont.meta).foregroundStyle(theme.ink2)
            } else {
                TimelineView(.everyMinute) { _ in
                    Text(Fmt.age(session.lastActivity)).font(BuddyFont.meta).foregroundStyle(theme.ink3)
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: Self.height)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(highlighted ? theme.fillSelected : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(session.title), \(status.label), \(Fmt.shortPath(session.cwd))")
    }
}

/// "New session" row: plus glyph in the dot column, cwd it will start in.
struct NewSessionRow: View {
    let cwd: String
    var highlighted = false
    var showsReturnKey = false

    @Environment(\.buddyTheme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(theme.ink2)
                .frame(width: 12)
            VStack(alignment: .leading, spacing: 1) {
                Text("New session")
                    .font(BuddyFont.rowTitle)
                    .foregroundStyle(theme.ink)
                Text(Fmt.shortPath(cwd))
                    .font(BuddyFont.meta)
                    .foregroundStyle(theme.ink3)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 8)
            if showsReturnKey { KeyCap(symbol: "return") }
        }
        .padding(.horizontal, 10)
        .frame(height: SessionRow.height)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(highlighted ? theme.fillSelected : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("New session in \(Fmt.shortPath(cwd))")
    }
}

// MARK: - Small pieces

struct SectionLabel: View {
    let text: String
    var trailing: String?
    @Environment(\.buddyTheme) private var theme

    static let height: CGFloat = 24

    var body: some View {
        HStack {
            Text(text)
            Spacer()
            if let trailing { Text(trailing) }
        }
        .font(BuddyFont.label)
        .textCase(.uppercase)
        .tracking(0.6)
        .foregroundStyle(theme.ink3)
        .padding(.horizontal, 10)
        .frame(height: Self.height)
        .accessibilityAddTraits(.isHeader)
    }
}

struct KeyCap: View {
    let symbol: String
    @Environment(\.buddyTheme) private var theme

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(theme.ink2)
            .frame(width: 20, height: 16)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(theme.hairline, lineWidth: 1)
            )
            .accessibilityHidden(true)
    }
}

struct Hairline: View {
    @Environment(\.buddyTheme) private var theme
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(theme.hairline)
            .frame(height: max(0.5, 1 / displayScale))
    }
}

// MARK: - Buttons

/// Compact rounded-rect button. `prominent` = inverted fill (the one primary action on a surface).
struct PillButton: View {
    let title: String
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(BuddyFont.button)
        }
        .buttonStyle(PillStyle(prominent: prominent))
    }
}

private struct PillStyle: ButtonStyle {
    let prominent: Bool
    func makeBody(configuration: Configuration) -> some View {
        PillBody(configuration: configuration, prominent: prominent)
    }
}

private struct PillBody: View {
    let configuration: ButtonStyleConfiguration
    let prominent: Bool
    @State private var hovering = false
    @Environment(\.buddyTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        configuration.label
            .foregroundStyle(prominent ? theme.onInk : theme.ink)
            .padding(.horizontal, 11)
            .frame(height: 24)
            .background(
                shape.fill(prominent
                           ? theme.ink.opacity(hovering ? 0.86 : 1)
                           : (hovering ? theme.fillSelected : theme.fillHover))
            )
            .contentShape(shape)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .animation(Motion.press, value: configuration.isPressed)
            .animation(Motion.selection, value: hovering)
            .onHover { hovering = $0 }
    }
}

/// Square icon button (close, send). Highlights on hover, dips on press.
struct IconButton: View {
    let systemName: String
    let label: String
    var size: CGFloat = 20
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: prominent ? 11 : 9, weight: .bold))
        }
        .buttonStyle(IconStyle(size: size, prominent: prominent))
        .accessibilityLabel(label)
    }
}

private struct IconStyle: ButtonStyle {
    let size: CGFloat
    let prominent: Bool
    func makeBody(configuration: Configuration) -> some View {
        IconBody(configuration: configuration, size: size, prominent: prominent)
    }
}

private struct IconBody: View {
    let configuration: ButtonStyleConfiguration
    let size: CGFloat
    let prominent: Bool
    @State private var hovering = false
    @Environment(\.buddyTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
        configuration.label
            .foregroundStyle(prominent ? theme.onInk : (hovering ? theme.ink : theme.ink3))
            .frame(width: size, height: size)
            .background(
                shape.fill(prominent ? theme.ink : (hovering ? theme.fillSelected : Color.clear))
            )
            .contentShape(shape)
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(isEnabled ? 1 : 0.3)
            .animation(Motion.press, value: configuration.isPressed)
            .animation(Motion.selection, value: hovering)
            .onHover { hovering = $0 }
    }
}
