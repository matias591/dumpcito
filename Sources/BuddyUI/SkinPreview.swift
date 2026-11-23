import BuddyCore
import SwiftUI

/// A live, quiet idle frame of a skin, for the picker and the walkthrough.
public struct SkinPreview: View {
    let skin: BuddySkin
    var side: CGFloat
    var animated: Bool

    @State private var engine: any SkinEngine

    public init(skin: BuddySkin, side: CGFloat = 56, animated: Bool = true) {
        self.skin = skin; self.side = side; self.animated = animated
        _engine = State(initialValue: skin.makeEngine())
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animated)) { context in
            Canvas { gc, size in
                engine.advance(to: context.date, kind: .idle, allowMotion: animated, corner: .bottomTrailing)
                var gc = gc
                engine.draw(&gc, size: size, scale: side / 58)
            }
        }
        // Glow and sparkles spill past the body, so draw on a canvas twice the slot and let it overflow.
        .frame(width: side * 2, height: side * 2)
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}
