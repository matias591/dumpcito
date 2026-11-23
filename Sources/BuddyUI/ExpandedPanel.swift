import BuddyCore
import SwiftUI

/// Click-to-expand panel: optional notice (active toast), next meeting, sessions, compose.
struct ExpandedPanel: View {
    let model: BuddyModel
    let composeBridge: BuddyComposeBridge
    let onCollapse: () -> Void

    @State private var draft = ""
    @State private var chosenTarget: DispatchTarget?
    @FocusState private var composeFocused: Bool
    @Environment(\.buddyTheme) private var theme

    private static let maxVisibleRows = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if hasNotice {
                ToastContent(model: model)
                    .padding(.leading, 12)
                    .padding(.trailing, 8)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.fillSelected)
                    )
                    .padding(6)
                Hairline()
            }
            meeting
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            Hairline()
            sessions
                .padding(6)
            Hairline()
            compose
                .padding(10)
        }
        .frame(width: BuddyMetrics.panelWidth)
        .glassSurface(cornerRadius: 18)
        .onExitCommand(perform: onCollapse)
    }

    private var hasNotice: Bool {
        switch model.mood.kind {
        case .finished, .needsYou, .sent, .error: true
        default: false
        }
    }

    // MARK: Meeting

    @ViewBuilder private var meeting: some View {
        if let m = model.nextMeeting {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Next")
                        .font(BuddyFont.label)
                        .textCase(.uppercase)
                        .tracking(0.6)
                        .foregroundStyle(theme.ink3)
                    Text(m.title)
                        .font(BuddyFont.title)
                        .foregroundStyle(theme.ink)
                        .lineLimit(1)
                    TimelineView(.everyMinute) { _ in
                        Text("\(Fmt.countdown(to: m)) \u{00B7} \(Fmt.timeRange(m))")
                            .font(BuddyFont.meta)
                            .foregroundStyle(theme.ink2)
                            .lineLimit(1)
                    }
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 8)
                if m.joinURL != nil {
                    PillButton(title: "Join", prominent: !hasNotice) { model.onJoinMeeting(m) }
                        .accessibilityLabel("Join \(m.title)")
                }
            }
        } else {
            HStack(spacing: 8) {
                Text("No meetings soon")
                    .font(BuddyFont.meta)
                    .foregroundStyle(theme.ink3)
                Spacer()
            }
        }
    }

    // MARK: Sessions

    @ViewBuilder private var sessions: some View {
        let showingRecent = model.liveSessions.isEmpty
        let list = showingRecent ? model.recentSessions : model.liveSessions
        VStack(spacing: 0) {
            SectionLabel(text: showingRecent && !list.isEmpty ? "Recent" : "Sessions",
                         trailing: showingRecent || list.isEmpty ? nil : "\(list.count) live")
            if list.isEmpty {
                Text("No sessions yet")
                    .font(BuddyFont.meta)
                    .foregroundStyle(theme.ink3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .frame(height: SessionRow.height)
            } else {
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        ForEach(list) { session in
                            HoverRow { hovering in
                                Button { model.onOpenSession(session) } label: {
                                    SessionRow(session: session, highlighted: hovering, dormant: showingRecent)
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("Opens the session")
                            }
                        }
                    }
                }
                .scrollIndicators(.never)
                .scrollDisabled(list.count <= Self.maxVisibleRows)
                .frame(height: CGFloat(min(list.count, Self.maxVisibleRows)) * SessionRow.height)
            }
        }
    }

    // MARK: Compose

    private var compose: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Ask Claude", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(BuddyFont.body)
                .foregroundStyle(theme.ink)
                .lineLimit(1...4)
                .focused($composeFocused)
                .onSubmit(send)
                .onExitCommand(perform: onCollapse)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(theme.fillField)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(composeFocused ? theme.ink3 : Color.clear, lineWidth: 1)
                )
                .animation(Motion.selection, value: composeFocused)
                .accessibilityLabel("Prompt")

            HStack(spacing: 6) {
                targetMenu
                Spacer(minLength: 8)
                IconButton(systemName: "arrow.up", label: "Send", size: 24, prominent: true, action: send)
                    .disabled(trimmedDraft.isEmpty)
            }
        }
    }

    private var targetMenu: some View {
        TargetMenuButton(title: targetTitle) {
            let current = target
            var items: [TargetMenuButton.Item] = []
            let showingRecent = model.liveSessions.isEmpty
            let sessions = showingRecent ? model.recentSessions : model.liveSessions
            if !sessions.isEmpty {
                items.append(.header(showingRecent ? "Recent" : "Live"))
                for s in sessions {
                    let t = DispatchTarget.session(id: s.id)
                    items.append(.option(s.title, checked: current == t) { chosenTarget = t })
                }
                items.append(.separator)
            }
            let cwd = newCwd
            let isNew: Bool = if case .newSession = current { true } else { false }
            items.append(.option("New session in \(Fmt.shortPath(cwd))", checked: isNew) {
                chosenTarget = .newSession(cwd: cwd)
            })
            return items
        }
    }

    private var newCwd: String {
        Fmt.defaultNewSessionCwd(live: model.liveSessions, recent: model.recentSessions)
    }

    private var trimmedDraft: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The chosen target if it still exists, else the most recent live session, else New session.
    private var target: DispatchTarget {
        if let chosenTarget {
            switch chosenTarget {
            case .newSession: return chosenTarget
            case let .session(id):
                if session(id) != nil { return chosenTarget }
            }
        }
        if let first = model.liveSessions.first { return .session(id: first.id) }
        return .newSession(cwd: newCwd)
    }

    private var targetTitle: String {
        switch target {
        case .newSession: "New session"
        case let .session(id): session(id)?.title ?? "Session"
        }
    }

    private func session(_ id: String) -> AgentSession? {
        model.liveSessions.first { $0.id == id } ?? model.recentSessions.first { $0.id == id }
    }

    private func send() {
        let text = trimmedDraft
        guard !text.isEmpty else { return }
        composeBridge.onCompose(text, target)
        draft = ""
    }
}

/// Tracks hover for a row without re-rendering its siblings.
private struct HoverRow<Content: View>: View {
    @ViewBuilder let content: (Bool) -> Content
    @State private var hovering = false

    var body: some View {
        content(hovering)
            .onHover { hovering = $0 }
            .animation(Motion.selection, value: hovering)
    }
}
