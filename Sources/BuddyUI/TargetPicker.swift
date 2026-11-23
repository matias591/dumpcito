import BuddyCore
import SwiftUI

/// "Send to which session?" after a capture. Live sessions first, then New session.
/// With no live sessions: New session, then a Recent group.
/// Keyboard: up/down, return, 1-9, esc. Hover moves the selection; click sends.
struct TargetPicker: View {
    let capture: CaptureResult
    let live: [AgentSession]
    let recent: [AgentSession]
    let onPick: (DispatchTarget) -> Void
    let onDismiss: () -> Void

    @State private var selection = 0
    @FocusState private var focused: Bool
    @Environment(\.buddyTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let maxListHeight: CGFloat = 6 * SessionRow.height + 2 * SectionLabel.height

    private enum Row: Identifiable {
        case label(String)
        case session(AgentSession, index: Int, dormant: Bool)
        case newSession(cwd: String, index: Int)

        var id: String {
            switch self {
            case let .label(text): "label-\(text)"
            case let .session(s, _, _): "s-\(s.id)"
            case .newSession: "new"
            }
        }

        var height: CGFloat {
            if case .label = self { return SectionLabel.height }
            return SessionRow.height
        }
    }

    private var newCwd: String { Fmt.defaultNewSessionCwd(live: live, recent: recent) }

    /// Selectable targets in display order.
    private var targets: [DispatchTarget] {
        if live.isEmpty {
            return [.newSession(cwd: newCwd)] + recent.map { .session(id: $0.id) }
        }
        return live.map { .session(id: $0.id) } + [.newSession(cwd: newCwd)]
    }

    private var rows: [Row] {
        var out: [Row] = []
        if live.isEmpty {
            out.append(.label("No live sessions"))
            out.append(.newSession(cwd: newCwd, index: 0))
            if !recent.isEmpty {
                out.append(.label("Recent"))
                for (i, s) in recent.enumerated() { out.append(.session(s, index: i + 1, dormant: true)) }
            }
        } else {
            out.append(.label("Live"))
            for (i, s) in live.enumerated() { out.append(.session(s, index: i, dormant: false)) }
            out.append(.newSession(cwd: newCwd, index: live.count))
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            quote
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 12)
            Hairline()
            list
                .padding(6)
            Hairline()
            footer
        }
        .frame(width: BuddyMetrics.panelWidth)
        .glassSurface(cornerRadius: 18)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { focused = true }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.return) { pick(selection); return .handled }
        .onKeyPress(.escape) { onDismiss(); return .handled }
        .onKeyPress(characters: .decimalDigits, phases: .down) { press in
            guard let n = Int(press.characters), n >= 1, n <= min(9, targets.count) else { return .ignored }
            pick(n - 1)
            return .handled
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Send to")
    }

    private var header: some View {
        HStack {
            Text("Send to")
                .font(BuddyFont.title)
                .foregroundStyle(theme.ink)
            Spacer()
            IconButton(systemName: "xmark", label: "Cancel", action: onDismiss)
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.top, 10)
    }

    private var quote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if capture.transcript.isEmpty {
                    Text("No speech captured").foregroundStyle(theme.ink3)
                } else {
                    Text(verbatim: capture.transcript).foregroundStyle(theme.ink)
                }
            }
            .font(BuddyFont.transcript)
            .lineSpacing(2)
            .lineLimit(4)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 10)
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1).fill(theme.hairline).frame(width: 2)
            }

            if capture.screenshotURL != nil {
                Label("Screenshot attached", systemImage: "viewfinder")
                    .font(BuddyFont.meta)
                    .foregroundStyle(theme.ink3)
                    .padding(.leading, 10)
            }
        }
    }

    private var list: some View {
        let rows = rows
        let total = rows.reduce(0) { $0 + $1.height }
        return ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        rowView(row).id(row.id)
                    }
                }
            }
            .scrollIndicators(.never)
            .scrollDisabled(total <= Self.maxListHeight)
            .frame(height: min(total, Self.maxListHeight))
            .onChange(of: selection) { _, new in
                guard total > Self.maxListHeight,
                      let row = rows.first(where: { rowIndex($0) == new }) else { return }
                withAnimation(reduceMotion ? nil : Motion.selection) { proxy.scrollTo(row.id) }
            }
        }
    }

    @ViewBuilder private func rowView(_ row: Row) -> some View {
        switch row {
        case let .label(text):
            SectionLabel(text: text)
        case let .session(session, index, dormant):
            Button { pick(index) } label: {
                SessionRow(session: session, highlighted: index == selection,
                           showsReturnKey: index == selection, dormant: dormant)
            }
            .buttonStyle(.plain)
            .onHover { if $0 { selection = index } }
            .accessibilityAddTraits(index == selection ? .isSelected : [])
        case let .newSession(cwd, index):
            Button { pick(index) } label: {
                NewSessionRow(cwd: cwd, highlighted: index == selection, showsReturnKey: index == selection)
            }
            .buttonStyle(.plain)
            .onHover { if $0 { selection = index } }
            .accessibilityAddTraits(index == selection ? .isSelected : [])
        }
    }

    private func rowIndex(_ row: Row) -> Int? {
        switch row {
        case .label: nil
        case let .session(_, i, _): i
        case let .newSession(_, i): i
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            hint("\u{2191}\u{2193}", "move")
            hint("return", "send", symbol: true)
            hint("1\u{2013}9", "pick")
            hint("esc", "close")
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: 30)
        .accessibilityHidden(true)
    }

    private func hint(_ key: String, _ action: String, symbol: Bool = false) -> some View {
        HStack(spacing: 4) {
            if symbol {
                Image(systemName: key).font(.system(size: 8, weight: .semibold))
            } else {
                Text(key)
            }
            Text(action).foregroundStyle(theme.ink3.opacity(0.8))
        }
        .font(BuddyFont.label)
        .foregroundStyle(theme.ink2)
    }

    private func move(_ delta: Int) {
        guard !targets.isEmpty else { return }
        let next = min(max(selection + delta, 0), targets.count - 1)
        withAnimation(reduceMotion ? nil : Motion.selection) { selection = next }
    }

    private func pick(_ index: Int) {
        guard targets.indices.contains(index) else { return }
        selection = index
        onPick(targets[index])
    }
}
