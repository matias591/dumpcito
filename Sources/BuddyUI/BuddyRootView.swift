import BuddyCore
import SwiftUI

/// The whole buddy: the character plus whatever surface the current mood calls for.
///
/// Self-sizing with a transparent background: host it in a borderless, non-opaque NSPanel and
/// size the window to the hosting view's fitting size (see `BuddyMetrics`). If the host instead
/// gives it a larger window, content stays pinned to `corner`.
///
/// Precedence: listening / choosing target always win; otherwise `model.expanded` shows the panel
/// (an active toast appears inside it as a notice); otherwise the mood's bubble; idle shows nothing
/// but the character.
public struct BuddyRootView: View {
    private let model: BuddyModel
    private let composeBridge: BuddyComposeBridge
    private let cornerOverride: BuddyCorner?

    @State private var windowVisible = true

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(model: BuddyModel,
                composeBridge: BuddyComposeBridge = BuddyComposeBridge(),
                corner: BuddyCorner? = nil) {
        self.model = model
        self.composeBridge = composeBridge
        self.cornerOverride = corner
    }

    /// Follows where the host window sits on screen so the bubble/panel always opens toward the centre.
    private var corner: BuddyCorner {
        if let cornerOverride { return cornerOverride }
        switch (model.anchoredTop, model.anchoredLeading) {
        case (false, false): return .bottomTrailing
        case (false, true): return .bottomLeading
        case (true, false): return .topTrailing
        case (true, true): return .topLeading
        }
    }

    public var body: some View {
        let theme = Theme(isDark: colorScheme == .dark, highContrast: contrast == .increased)
        let kind = model.mood.kind
        let surface = surfaceKind

        VStack(alignment: corner.horizontalAlignment, spacing: BuddyMetrics.stackSpacing) {
            if corner.isBottom {
                surfaceLayer(surface)
                character(kind, surface: surface)
            } else {
                character(kind, surface: surface)
                surfaceLayer(surface)
            }
        }
        .padding(BuddyMetrics.outerPadding)
        .fixedSize()
        .animation(reduceMotion ? Motion.reduced : Motion.surface, value: surface)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: corner.alignment)
        .environment(\.buddyTheme, theme)
        .environment(\.buddyAnimationsActive, windowVisible)
        .background(WindowVisibilityReader { windowVisible = $0 })
        .onChange(of: kind) { _, newKind in moodDidChange(to: newKind) }
    }

    // MARK: Character

    private func character(_ kind: MoodKind, surface: SurfaceKind) -> some View {
        CharacterView(
            skin: model.skin,
            kind: kind,
            corner: corner,
            badge: badge,
            allowMotion: !reduceMotion,
            action: characterTapped
        )
        .id(model.skin)
        // Up to +15% at the top stage, anchored at the bottom so it grows upward.
        .scaleEffect(1 + 0.0375 * CGFloat(max(0, min(4, model.stage - 1))), anchor: .bottom)
        .animation(Motion.expression, value: model.stage)
        .accessibilityLabel("Dumpcito")
        .accessibilityValue(model.mood.accessibilityValue)
        .accessibilityHint(model.expanded ? "Collapses the panel" : "Shows sessions and the next meeting")
    }

    /// needs-you anywhere wins; else a static white dot if anything is working.
    private var badge: DotStatus? {
        if case .sessionNeedsYou = model.mood { return .needsYou }
        if model.liveSessions.contains(where: \.needsAttention) { return .needsYou }
        if model.liveSessions.contains(where: { $0.state == .working }) { return .working }
        return nil
    }

    private func characterTapped() {
        switch model.mood {
        case .choosingTarget:
            model.onDismiss()
        case .listening:
            break
        default:
            withAnimation(reduceMotion ? Motion.reduced : Motion.surface) { model.expanded.toggle() }
        }
    }

    // MARK: Surfaces

    private var surfaceKind: SurfaceKind {
        switch model.mood {
        case .listening: return .bubble(.listening)
        case .choosingTarget: return .picker
        default: break
        }
        if model.expanded { return .panel }
        return model.mood.kind == .idle ? .none : .bubble(model.mood.kind)
    }

    @ViewBuilder private func surfaceLayer(_ surface: SurfaceKind) -> some View {
        if surface != .none {
            surfaceContent(surface)
                .id(surface)
                .transition(surfaceTransition)
                .zIndex(1)
        }
    }

    @ViewBuilder private func surfaceContent(_ surface: SurfaceKind) -> some View {
        switch surface {
        case .none:
            EmptyView()
        case .bubble:
            MoodBubble(model: model)
        case .picker:
            if case let .choosingTarget(capture) = model.mood {
                TargetPicker(capture: capture,
                             live: model.liveSessions,
                             recent: model.recentSessions,
                             onPick: { model.onPick($0) },
                             onDismiss: { model.onDismiss() })
            }
        case .panel:
            ExpandedPanel(model: model, composeBridge: composeBridge) {
                withAnimation(reduceMotion ? Motion.reduced : Motion.surface) { model.expanded = false }
            }
        }
    }

    /// Grows out of the character and returns into it along the same path.
    private var surfaceTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .scale(scale: 0.94, anchor: corner.anchor)
            .combined(with: .offset(y: corner.isBottom ? 6 : -6))
            .combined(with: .opacity)
    }

    // MARK: Mood changes

    private func moodDidChange(to kind: MoodKind) {
        if let text = model.mood.announcement {
            AccessibilityNotification.Announcement(text).post()
        }
    }
}
