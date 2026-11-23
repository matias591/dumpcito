import BuddyCore
import SwiftUI

/// The buddy: a soft-body jelly (see Jelly.swift). The canvas is larger than the layout slot so
/// the glow, ripples and sparkles can spill past the 56 pt body; only the body takes clicks.
struct CharacterView: View {
    let skin: BuddySkin
    let kind: MoodKind
    let corner: BuddyCorner
    let badge: DotStatus?
    let allowMotion: Bool
    let action: () -> Void

    @State private var engine: any SkinEngine
    @State private var wake = 0
    @Environment(\.buddyAnimationsActive) private var animationsActive

    init(skin: BuddySkin, kind: MoodKind, corner: BuddyCorner, badge: DotStatus?, allowMotion: Bool, action: @escaping () -> Void) {
        self.skin = skin; self.kind = kind; self.corner = corner; self.badge = badge
        self.allowMotion = allowMotion; self.action = action
        _engine = State(initialValue: skin.makeEngine())
    }

    private let size = BuddyMetrics.characterSize
    private let canvasSide: CGFloat = 112

    var body: some View {
        engine.visible = animationsActive
        return Button {
            engine.poke()
            wake &+= 1
            action()
        } label: {
            TimelineView(JellySchedule(engine: engine)) { context in
                Canvas { gc, canvasSize in
                    engine.advance(to: context.date, kind: kind, allowMotion: allowMotion, corner: corner)
                    var gc = gc
                    engine.draw(&gc, size: canvasSize, scale: size / 58)
                }
            }
            .id("\(kind)-\(wake)")
            .frame(width: canvasSide, height: canvasSide)
            .frame(width: size, height: size)
            .background(JellyWindowProbe(engine: engine))
            .overlay(alignment: .topTrailing) {
                if let badge {
                    Badge(status: badge)
                        .offset(x: 4, y: -4)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
            }
            .animation(Motion.expression, value: badge)
        }
        .buttonStyle(CharacterButtonStyle())
    }
}

// MARK: - Badge

/// Status dot knocked out of the head's corner. Static (no pulse) to keep idle CPU at zero.
private struct Badge: View {
    let status: DotStatus
    @Environment(\.buddyTheme) private var theme

    var body: some View {
        ZStack {
            Circle().fill(theme.screen)
            Circle().strokeBorder(theme.bezel, lineWidth: 0.5)
            StatusDot(status: status, size: 8, pulses: false, onDark: true)
        }
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)
    }
}

// MARK: - Interaction

private struct CharacterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        CharacterPressBody(configuration: configuration)
    }
}

private struct CharacterPressBody: View {
    let configuration: ButtonStyleConfiguration
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let scale: CGFloat = configuration.isPressed ? 0.93 : (hovering && !reduceMotion ? 1.04 : 1)
        configuration.label
            .scaleEffect(reduceMotion ? 1 : scale, anchor: .bottom)
            .opacity(reduceMotion && configuration.isPressed ? 0.75 : 1)
            .animation(configuration.isPressed ? Motion.press : Motion.hover, value: configuration.isPressed)
            .animation(Motion.hover, value: hovering)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .onHover { hovering = $0 }
            .focusEffectDisabled()
    }
}
