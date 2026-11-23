import BuddyCore
import SwiftUI

/// Small surface next to the collapsed character: meeting nudge, listening transcript, toasts.
struct MoodBubble: View {
    let model: BuddyModel

    var body: some View {
        CappedWidth(maxWidth: BuddyMetrics.bubbleMaxWidth) {
            content
                .padding(.leading, 12)
                .padding(.trailing, 8)
                .padding(.vertical, 10)
        }
        .glassSurface(cornerRadius: 14)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var content: some View {
        switch model.mood {
        case let .meetingSoon(meeting):
            MeetingNudge(meeting: meeting,
                         onJoin: { model.onJoinMeeting(meeting) },
                         onDismiss: { model.onDismiss() })
        case let .listening(partial):
            ListeningContent(partial: partial)
                .padding(.trailing, 4)
        default:
            ToastContent(model: model)
        }
    }
}

// MARK: - Meeting

struct MeetingNudge: View {
    let meeting: MeetingEvent
    let onJoin: () -> Void
    let onDismiss: () -> Void

    @Environment(\.buddyTheme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(meeting.title)
                    .font(BuddyFont.title)
                    .foregroundStyle(theme.ink)
                    .lineLimit(1)
                TimelineView(.everyMinute) { _ in
                    Text("\(Fmt.countdown(to: meeting)) \u{00B7} \(Fmt.timeRange(meeting))")
                        .font(BuddyFont.meta)
                        .foregroundStyle(theme.ink2)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 4)
            if meeting.joinURL != nil {
                PillButton(title: "Join", prominent: true, action: onJoin)
                    .accessibilityLabel("Join \(meeting.title)")
            }
            IconButton(systemName: "xmark", label: "Dismiss", action: onDismiss)
        }
    }
}

// MARK: - Listening

struct ListeningContent: View {
    let partial: String

    @Environment(\.buddyTheme) private var theme
    @Environment(\.buddyAnimationsActive) private var animationsActive

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Listening")
                Spacer(minLength: 12)
                Text("release to send")
            }
            .font(BuddyFont.label)
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(theme.ink3)

            // Terminal caret after the text, blinking at 1 Hz (2 renders per second).
            if animationsActive {
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    transcript(caretOn: Int(context.date.timeIntervalSinceReferenceDate / 0.5) % 2 == 0)
                }
            } else {
                transcript(caretOn: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(partial.isEmpty ? "Listening" : "Listening: \(partial)")
    }

    /// ~41 monospaced 12 pt characters (7.2 pt each) fit a 320 pt bubble line; 4 lines with slack for word wrap.
    private static let tailBudget = 130

    private func transcript(caretOn: Bool) -> some View {
        let caret = Text("\u{258D}").foregroundStyle(caretOn ? theme.ink : Color.clear)
        let body: Text = partial.isEmpty
            ? Text("Say something").foregroundStyle(theme.ink3)
            : Text(verbatim: Fmt.tail(partial, maxChars: Self.tailBudget)).foregroundStyle(theme.ink)
        return Text("\(body)\(caret)")
            .font(BuddyFont.transcript)
            .lineSpacing(2)
            .lineLimit(5)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Toasts

/// Finished / needs you / sent / error. Shared by the collapsed bubble and the panel's notice row.
struct ToastContent: View {
    let model: BuddyModel

    @Environment(\.buddyTheme) private var theme

    var body: some View {
        switch model.mood {
        case let .sessionFinished(session):
            sessionToast(session, label: "Finished", status: .idle)
        case let .sessionNeedsYou(session):
            sessionToast(session, label: "Needs you", status: .needsYou)
        case let .sent(text):
            messageToast(symbol: "checkmark", text: text, lines: 2)
        case let .error(text):
            messageToast(symbol: "exclamationmark", text: text, lines: 3)
        case let .meetingSoon(meeting):
            MeetingNudge(meeting: meeting,
                         onJoin: { model.onJoinMeeting(meeting) },
                         onDismiss: { model.onDismiss() })
        default:
            EmptyView()
        }
    }

    private func sessionToast(_ session: AgentSession, label: String, status: DotStatus) -> some View {
        HStack(spacing: 10) {
            StatusDot(status: status)
                .frame(width: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(BuddyFont.label)
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(theme.ink3)
                Text(session.title)
                    .font(BuddyFont.title)
                    .foregroundStyle(theme.ink)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 4)
            PillButton(title: "Open", prominent: status == .needsYou) { model.onOpenSession(session) }
                .accessibilityLabel("Open \(session.title)")
            IconButton(systemName: "xmark", label: "Dismiss") { model.onDismiss() }
        }
    }

    private func messageToast(symbol: String, text: String, lines: Int) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(theme.ink2)
                .frame(width: 12, height: 18)
                .accessibilityHidden(true)
            Text(text)
                .font(BuddyFont.body)
                .foregroundStyle(theme.ink)
                .lineLimit(lines)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 1)
            Spacer(minLength: 4)
            IconButton(systemName: "xmark", label: "Dismiss") { model.onDismiss() }
        }
    }
}
