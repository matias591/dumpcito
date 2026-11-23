import AppKit
import SwiftUI

/// Dark (or light) semi-transparent rounded surface: blurred material + contrast tint + hairline,
/// with an outside-only shadow. Falls back to a solid fill for Reduce Transparency / Increase Contrast.
struct GlassBackground: View {
    var cornerRadius: CGFloat

    @Environment(\.buddyTheme) private var theme
    @Environment(\.buddyMaterialBlending) private var blending
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            OuterShadow(shape: shape, color: theme.shadow, radius: 14, y: 6)
            if reduceTransparency || theme.highContrast {
                shape.fill(theme.solidSurface)
            } else {
                VisualEffectBlur(
                    blending: blending == .behindWindow ? .behindWindow : .withinWindow,
                    isDark: theme.isDark,
                    cornerRadius: cornerRadius
                )
                .clipShape(shape)
                shape.fill(theme.glassTint)
            }
            shape.strokeBorder(theme.hairline, lineWidth: max(0.5, 1 / displayScale))
        }
        .allowsHitTesting(false)
    }
}

extension View {
    func glassSurface(cornerRadius: CGFloat) -> some View {
        background(GlassBackground(cornerRadius: cornerRadius))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Shadow drawn only outside the shape, so it never muddies a translucent surface from beneath.
struct OuterShadow<S: Shape>: View {
    let shape: S
    let color: Color
    let radius: CGFloat
    let y: CGFloat

    var body: some View {
        shape.fill(Color.black)
            .shadow(color: color, radius: radius, x: 0, y: y)
            .mask {
                ZStack {
                    Rectangle().padding(-(radius * 2 + abs(y)))
                    shape.fill(Color.black).blendMode(.destinationOut)
                }
                .compositingGroup()
            }
            .allowsHitTesting(false)
    }
}

/// NSVisualEffectView wrapper. `.behindWindow` blurs the desktop under a transparent NSPanel,
/// which SwiftUI's own Material cannot do. Kept `.active` so it stays glassy while the app is inactive.
struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blending: NSVisualEffectView.BlendingMode
    var isDark: Bool
    var cornerRadius: CGFloat

    final class Coordinator {
        var radius: CGFloat = -1
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .active
        view.isEmphasized = false
        apply(to: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        apply(to: view, coordinator: context.coordinator)
    }

    private func apply(to view: NSVisualEffectView, coordinator: Coordinator) {
        if view.material != material { view.material = material }
        if view.blendingMode != blending { view.blendingMode = blending }
        let name: NSAppearance.Name = isDark ? .darkAqua : .aqua
        if view.appearance?.name != name { view.appearance = NSAppearance(named: name) }
        if coordinator.radius != cornerRadius {
            coordinator.radius = cornerRadius
            // The window server clips behind-window blur by maskImage, not by SwiftUI's clipShape.
            view.maskImage = Self.mask(cornerRadius: cornerRadius)
        }
    }

    static func mask(cornerRadius r: CGFloat) -> NSImage {
        let inset = ceil(r * 1.6)
        let edge = inset * 2 + 1
        let path = RoundedRectangle(cornerRadius: r, style: .continuous)
            .path(in: CGRect(x: 0, y: 0, width: edge, height: edge)).cgPath
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.addPath(path)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fillPath()
            return true
        }
        image.capInsets = NSEdgeInsets(top: inset, left: inset, bottom: inset, right: inset)
        image.resizingMode = .stretch
        return image
    }
}

/// Lays its single child out at its natural width, capped at `maxWidth`, so text wraps at the cap
/// even when an ancestor uses `fixedSize()`.
struct CappedWidth: Layout {
    var maxWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let natural = child.sizeThatFits(.unspecified)
        let width = min(natural.width, maxWidth, proposal.width ?? .infinity)
        return child.sizeThatFits(ProposedViewSize(width: width, height: nil))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}
