import AppKit
import BuddyCore
import SwiftUI

/// One drawable character. A fresh engine is made per CharacterView, and the view calls
/// `advance` then `draw` on every timeline tick. Engines are time-driven (springs, not frame counts),
/// so a slow schedule never changes how they move.
protocol SkinEngine: AnyObject {
    /// The host window, handed over by a zero-size probe view (for cursor-following eyes).
    var window: NSWindow? { get set }
    /// False while the window is hidden or covered: schedule slows right down.
    var visible: Bool { get set }
    /// Seconds until the next tick. 1/30 while moving; sparse bursts when calm, so idle CPU stays near zero.
    func nextInterval(after date: Date) -> Double
    /// Click on the character. Wakes it from sleep, plays a reaction.
    func poke()
    func advance(to date: Date, kind: MoodKind, allowMotion: Bool, corner: BuddyCorner)
    /// Draw into a square canvas. `scale` = characterSize / 58, so 1.0 means "as designed at 58 pt".
    func draw(_ ctx: inout GraphicsContext, size: CGSize, scale: CGFloat)
}

extension BuddySkin {
    func makeEngine() -> any SkinEngine {
        switch self {
        case .jelly: JellyEngine()
        case .pixel: PixelEngine()
        case .pocket: PocketEngine()
        }
    }
}
