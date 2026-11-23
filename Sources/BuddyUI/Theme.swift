import SwiftUI

/// Colour tokens. Black / white / grey only; `amber` is the single functional hue and is used
/// exclusively for the "needs you" status ring. See docs/DESIGN.md.
struct Theme: Equatable, Sendable {
    var isDark: Bool
    var highContrast: Bool

    private var base: Color { isDark ? .white : .black }

    /// Primary text and icons.
    var ink: Color { isDark ? Color(white: 0.96) : Color(white: 0.07) }
    var ink2: Color { ink.opacity(highContrast ? 0.84 : 0.66) }
    var ink3: Color { ink.opacity(highContrast ? 0.68 : 0.46) }
    /// Text on the inverted (primary) button.
    var onInk: Color { isDark ? Color(white: 0.06) : Color(white: 0.98) }

    var hairline: Color { base.opacity(highContrast ? 0.42 : (isDark ? 0.15 : 0.11)) }
    var fillHover: Color { base.opacity(isDark ? 0.07 : 0.05) }
    var fillSelected: Color { base.opacity(isDark ? 0.13 : 0.08) }
    var fillField: Color { base.opacity(isDark ? 0.07 : 0.05) }

    /// Tint laid over the blurred material so text keeps contrast on any desktop.
    var glassTint: Color { isDark ? Color.black.opacity(0.50) : Color.white.opacity(0.62) }
    /// Used instead of glass when Reduce Transparency or Increase Contrast is on.
    var solidSurface: Color { isDark ? Color(white: 0.10) : Color(white: 0.97) }
    var shadow: Color { Color.black.opacity(isDark ? 0.42 : 0.16) }

    /// The single status hue: "needs you" ring.
    var amber: Color {
        isDark ? Color(red: 0.91, green: 0.65, blue: 0.25) : Color(red: 0.70, green: 0.46, blue: 0.10)
    }

    // The character is a tiny CRT: its screen stays dark in both appearances.
    var screen: Color { Color(white: 0.055) }
    var face: Color { Color(white: 0.95) }
    var bezel: Color { Color.white.opacity(highContrast ? 0.34 : 0.16) }
    /// Extra outer edge so the dark head reads on a white desktop.
    var characterOutline: Color { isDark ? Color.black.opacity(0.35) : Color.black.opacity(0.22) }
}

enum BuddyFont {
    static let title = Font.system(size: 13, weight: .semibold)
    static let rowTitle = Font.system(size: 13, weight: .medium)
    static let body = Font.system(size: 13)
    static let meta = Font.system(size: 11, design: .monospaced)
    static let label = Font.system(size: 10, weight: .medium, design: .monospaced)
    static let transcript = Font.system(size: 12, design: .monospaced)
    static let button = Font.system(size: 12, weight: .semibold)
}

enum Motion {
    /// Surfaces (bubbles, picker, panel): critically damped, no overshoot.
    static let surface = Animation.spring(response: 0.34, dampingFraction: 1.0)
    /// Expression morphs on the face: a touch of life.
    static let expression = Animation.spring(response: 0.30, dampingFraction: 0.78)
    static let press = Animation.spring(response: 0.16, dampingFraction: 1.0)
    static let hover = Animation.spring(response: 0.28, dampingFraction: 0.72)
    static let selection = Animation.spring(response: 0.22, dampingFraction: 1.0)
    /// Reduce Motion replacement: short cross-fade.
    static let reduced = Animation.easeInOut(duration: 0.18)
}

// MARK: - Environment

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme(isDark: true, highContrast: false)
}

private struct AnimationsActiveKey: EnvironmentKey {
    static let defaultValue = true
}

/// How the glass surfaces blur. The host NSPanel wants `.behindWindow` (blur the desktop);
/// previews/galleries that draw their own backdrop inside the window want `.withinWindow`.
public enum BuddyMaterialBlending: Sendable, Hashable {
    case behindWindow
    case withinWindow
}

private struct MaterialBlendingKey: EnvironmentKey {
    static let defaultValue = BuddyMaterialBlending.behindWindow
}

extension EnvironmentValues {
    var buddyTheme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }

    /// False while the host window is fully occluded: looping animations stop.
    var buddyAnimationsActive: Bool {
        get { self[AnimationsActiveKey.self] }
        set { self[AnimationsActiveKey.self] = newValue }
    }

    var buddyMaterialBlending: BuddyMaterialBlending {
        get { self[MaterialBlendingKey.self] }
        set { self[MaterialBlendingKey.self] = newValue }
    }
}

public extension View {
    /// Preview/gallery helper. The real app keeps the default (`.behindWindow`).
    func buddyMaterialBlending(_ blending: BuddyMaterialBlending) -> some View {
        environment(\.buddyMaterialBlending, blending)
    }
}
