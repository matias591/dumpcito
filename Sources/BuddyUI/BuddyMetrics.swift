import CoreGraphics
import SwiftUI

/// Size constants the host window can use. The root view is self-sizing (transparent background,
/// no fixed full-screen frame), so the host can also just follow the hosting view's fitting size.
public enum BuddyMetrics {
    /// Side of the square character (the "head").
    public static let characterSize: CGFloat = 56
    /// Transparent margin around everything so shadows and the status badge never clip.
    public static let outerPadding: CGFloat = 16
    /// Gap between the character and the bubble / picker / panel above (or below) it.
    public static let stackSpacing: CGFloat = 10
    /// Toast and banner bubbles grow with their content up to this width, then wrap.
    public static let bubbleMaxWidth: CGFloat = 320
    /// Fixed width of the target picker and the expanded panel.
    public static let panelWidth: CGFloat = 320
    /// Upper bound for the picker / expanded panel height (lists scroll beyond this).
    public static let panelMaxHeight: CGFloat = 470

    /// Window size when only the character shows.
    public static var collapsedSize: CGSize {
        CGSize(width: characterSize + outerPadding * 2, height: characterSize + outerPadding * 2)
    }

    /// Largest window the root view will ask for (expanded panel or picker plus the character).
    public static var expandedMaxSize: CGSize {
        CGSize(width: panelWidth + outerPadding * 2,
               height: panelMaxHeight + stackSpacing + characterSize + outerPadding * 2)
    }
}

/// Which screen corner the host pins the buddy to. Surfaces grow away from that corner
/// (up and inward for bottom corners) and animate out of the character.
public enum BuddyCorner: Sendable, Hashable {
    case bottomTrailing, bottomLeading, topTrailing, topLeading

    var isBottom: Bool { self == .bottomTrailing || self == .bottomLeading }
    var isTrailing: Bool { self == .bottomTrailing || self == .topTrailing }

    var alignment: Alignment {
        switch self {
        case .bottomTrailing: .bottomTrailing
        case .bottomLeading: .bottomLeading
        case .topTrailing: .topTrailing
        case .topLeading: .topLeading
        }
    }

    var horizontalAlignment: HorizontalAlignment { isTrailing ? .trailing : .leading }

    /// Transition origin for surfaces: the edge that touches the character.
    var anchor: UnitPoint {
        switch self {
        case .bottomTrailing: .bottomTrailing
        case .bottomLeading: .bottomLeading
        case .topTrailing: .topTrailing
        case .topLeading: .topLeading
        }
    }
}
