import AppKit
import SwiftUI

/// Native pop-up menu for the compose target. SwiftUI's `Menu` on macOS drops custom label
/// styling, so the trigger is a plain SwiftUI button and the list is a real NSMenu anchored to it.
struct TargetMenuButton: View {
    struct Item {
        enum Kind { case header, option, separator }
        var kind: Kind
        var title: String = ""
        var checked = false
        var action: () -> Void = {}

        static func header(_ title: String) -> Item { Item(kind: .header, title: title) }
        static var separator: Item { Item(kind: .separator) }
        static func option(_ title: String, checked: Bool, action: @escaping () -> Void) -> Item {
            Item(kind: .option, title: title, checked: checked, action: action)
        }
    }

    let title: String
    let items: () -> [Item]

    @State private var anchor = AnchorBox()
    @State private var hovering = false
    @Environment(\.buddyTheme) private var theme

    var body: some View {
        Button {
            guard let view = anchor.view else { return }
            TargetMenuPresenter.popUp(items(), isDark: theme.isDark, below: view)
        } label: {
            HStack(spacing: 4) {
                Text("to").foregroundStyle(theme.ink3)
                Text(title).foregroundStyle(hovering ? theme.ink : theme.ink2).lineLimit(1).truncationMode(.tail)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(theme.ink3)
            }
            .font(BuddyFont.meta)
            .padding(.horizontal, 6)
            .frame(height: 22)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hovering ? theme.fillHover : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(MenuAnchor(box: anchor))
        .onHover { hovering = $0 }
        .animation(Motion.selection, value: hovering)
        .accessibilityLabel("Send to \(title)")
        .accessibilityHint("Choose a session")
    }
}

final class AnchorBox {
    weak var view: NSView?
}

private struct MenuAnchor: NSViewRepresentable {
    let box: AnchorBox

    func makeNSView(context: Context) -> NSView {
        let view = PassthroughView()
        box.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        box.view = view
    }
}

private final class PassthroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
private enum TargetMenuPresenter {
    final class Handlers: NSObject {
        var actions: [() -> Void] = []
        @objc func fire(_ sender: NSMenuItem) {
            guard actions.indices.contains(sender.tag) else { return }
            actions[sender.tag]()
        }
    }

    static func popUp(_ items: [TargetMenuButton.Item], isDark: Bool, below view: NSView) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        let handlers = Handlers()
        for item in items {
            switch item.kind {
            case .header:
                menu.addItem(NSMenuItem.sectionHeader(title: item.title))
            case .separator:
                menu.addItem(.separator())
            case .option:
                let mi = NSMenuItem(title: item.title, action: #selector(Handlers.fire(_:)), keyEquivalent: "")
                mi.target = handlers
                mi.tag = handlers.actions.count
                mi.state = item.checked ? .on : .off
                handlers.actions.append(item.action)
                menu.addItem(mi)
            }
        }
        let y: CGFloat = view.isFlipped ? view.bounds.height + 4 : -4
        // popUp blocks while the menu tracks, so `handlers` lives long enough.
        withExtendedLifetime(handlers) {
            _ = menu.popUp(positioning: nil, at: NSPoint(x: 0, y: y), in: view)
        }
    }
}
