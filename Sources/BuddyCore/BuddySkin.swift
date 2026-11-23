import Foundation

/// The selectable character looks. The raw value is what gets persisted.
public enum BuddySkin: String, CaseIterable, Sendable, Identifiable {
    case jelly, pixel, pocket

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .jelly: "Jelly"
        case .pixel: "Pixel"
        case .pocket: "Pocket"
        }
    }

    public var tagline: String {
        switch self {
        case .jelly: "A glossy aurora blob that squishes and glows."
        case .pixel: "An 8-bit mascot with an antenna LED."
        case .pocket: "A pocket handheld with an LCD face."
        }
    }
}
