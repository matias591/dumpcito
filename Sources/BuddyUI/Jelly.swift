import AppKit
import BuddyCore
import SwiftUI

/// The character's internal state. The app only has MoodKind; thinking is unused for now,
/// sleep/wake are internal (long idle, then the first poke or event).
enum JellyState { case idle, meeting, listening, thinking, sent, finished, needs, error, sleep, wake }

private struct JSpring {
    var x: Double, v = 0.0, t: Double, k = 0.0, c = 0.0
    init(_ x: Double, _ response: Double, _ damping: Double) { self.x = x; t = x; set(response, damping) }
    mutating func set(_ response: Double, _ damping: Double) {
        k = pow(2 * .pi / response, 2); c = 4 * .pi * damping / response
    }
    mutating func to(_ target: Double) { t = target }
    mutating func kick(_ dv: Double) { v += dv }
    /// Sub-stepped at 240 Hz so stiff springs stay stable at 30 fps.
    mutating func step(_ dt: Double) {
        let n = max(1, Int((dt * 240).rounded(.up))), h = dt / Double(n)
        for _ in 0..<n { v += (k * (t - x) - c * v) * h; x += v * h }
    }
}

private struct RGB {
    var r: Double, g: Double, b: Double
    init(_ hex: UInt32) { r = Double((hex >> 16) & 255); g = Double((hex >> 8) & 255); b = Double(hex & 255) }
    mutating func approach(_ o: RGB, _ f: Double) { r += (o.r - r) * f; g += (o.g - g) * f; b += (o.b - b) * f }
    func color(_ a: Double = 1) -> Color { Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: a) }
}

private let idlePalette: [RGB] = [RGB(0x7C5CFF), RGB(0xFF5CA8), RGB(0x2EE6D6)]
private let palettes: [JellyState: [RGB]] = [
    .idle: idlePalette, .wake: idlePalette, .sent: idlePalette,
    .meeting: [RGB(0xFFD166), RGB(0xFF7AA2), RGB(0x9B6BFF)],
    .listening: [RGB(0x38BDF8), RGB(0x818CF8), RGB(0xE879F9)],
    .thinking: [RGB(0xA78BFA), RGB(0x22D3EE), RGB(0xF472B6)],
    .finished: [RGB(0x34D399), RGB(0xFDE047), RGB(0x22D3EE)],
    .needs: [RGB(0xFF5E62), RGB(0xFF9966), RGB(0xFFD166)],
    .error: [RGB(0x94A3B8), RGB(0x64748B), RGB(0x475569)],
    .sleep: [RGB(0x4C3D99), RGB(0x7A3A75), RGB(0x2A7F8A)],
]

private func hash(_ n: Double) -> Double { let v = sin(n * 127.1 + 311.7) * 43758.5453; return v - v.rounded(.down) }
private func noise1(_ x: Double) -> Double {
    let i = x.rounded(.down), f = x - i, u = f * f * (3 - 2 * f)
    return (hash(i) + (hash(i + 1) - hash(i)) * u) * 2 - 1
}
private func noise2(_ x: Double, _ y: Double) -> Double {
    let ix = x.rounded(.down), iy = y.rounded(.down), fx = x - ix, fy = y - iy
    let ux = fx * fx * (3 - 2 * fx), uy = fy * fy * (3 - 2 * fy)
    func h(_ a: Double, _ b: Double) -> Double { hash(a * 57 + b * 113.3) }
    func mix(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
    return mix(mix(h(ix, iy), h(ix + 1, iy), ux), mix(h(ix, iy + 1), h(ix + 1, iy + 1), ux), uy) * 2 - 1
}
private func clamp(_ x: Double, _ a: Double = 0, _ b: Double = 1) -> Double { min(b, max(a, x)) }
private func easeOut(_ t: Double) -> Double { 1 - pow(1 - clamp(t), 3) }

/// Soft-body jelly: one blob, a palette per state, springs for every motion. Time-driven, so all
/// of it happens in `advance` + `draw`; nothing here touches the model.
final class JellyEngine: SkinEngine {
    private(set) var state = JellyState.idle
    private var kind = MoodKind.idle
    private var allowMotion = true
    private var corner = BuddyCorner.bottomTrailing
    weak var window: NSWindow?
    /// False while the window is hidden or covered; the schedule slows right down.
    var visible = true

    private var calmAnchor: Date?
    func nextInterval(after date: Date) -> Double {
        guard visible else { return 1 }
        guard isCalm else { calmAnchor = nil; return 1.0 / 30 }
        let anchor = calmAnchor ?? date
        calmAnchor = anchor
        let phase = date.timeIntervalSince(anchor).truncatingRemainder(dividingBy: 5)
        return phase < 0.9 ? 1.0 / 30 : 5 - phase
    }

    /// Nothing is moving except the slow breath, so frames can be sparse.
    var isCalm: Bool {
        (state == .idle || state == .sleep) && glance == nil && te > 0.8 && level < 0.01 && t - blink > 0.4
            && abs(y.v) < 1 && abs(y.x) < 0.5 && abs(x.v) < 1 && abs(sx.v) < 0.05 && abs(sy.v) < 0.05
    }

    private var t = 0.0, t0 = 0.0, last: Date?
    private var y = JSpring(0, 0.42, 0.45), x = JSpring(0, 0.22, 0.3)
    private var sx = JSpring(1, 0.3, 0.4), sy = JSpring(1, 0.3, 0.4)
    private var gx = JSpring(0, 0.2, 0.8), gy = JSpring(0, 0.2, 0.8)
    private var blink = -9.0, dbl = false, nextBlink = 2.0, nextAmbient = 6.0
    private var glance: (x: Double, y: Double, until: Double)?
    private var fired = Set<String>(), nudge = 0.0, sendT = -9.0
    private var cur = idlePalette, tgt = idlePalette
    private var level = 0.0

    private var te: Double { t - t0 }
    private func at(_ key: String, _ time: Double) -> Bool {
        if te >= time && !fired.contains(key) { fired.insert(key); return true }
        return false
    }
    private func hop(_ v: Double) { if allowMotion { y.kick(v) } }

    // MARK: State

    func poke() { if state == .sleep { setState(.wake) } }

    private func setState(_ s: JellyState) {
        let wasSleeping = state == .sleep
        state = s; t0 = t; fired = []; nudge = t
        tgt = palettes[s] ?? idlePalette
        sy.to(s == .sleep ? 0.8 : s == .error ? 0.86 : 1); sx.to(s == .sleep ? 1.12 : s == .error ? 1.08 : 1)
        guard allowMotion else { return }
        if wasSleeping && s != .wake { sy.kick(3); sx.kick(-2) }
        switch s {
        case .meeting: hop(-55)
        case .listening: hop(-30)
        case .finished: hop(-210)
        case .needs: hop(-120)
        case .sent: sy.to(0.84); sx.to(1.12)
        case .error: x.kick(170)
        default: break
        }
    }

    private func ambient() {
        let k = Double.random(in: 0..<1)
        if k < 0.3 { glance = (Double.random(in: -1...1), Double.random(in: -0.9...0.5), t + 0.9 + Double.random(in: 0..<0.7)) }
        else if k < 0.5 { if allowMotion { sx.kick(1.8); sy.kick(-1.4) } }
        else if k < 0.7 { hop(-70) }
        else { blink = t; dbl = true }
    }

    private static func state(for kind: MoodKind, current: JellyState) -> JellyState {
        switch kind {
        case .idle, .choosing: return (current == .sleep || current == .wake) ? current : .idle
        case .meeting: return .meeting
        case .listening: return .listening
        case .finished: return .finished
        case .needsYou: return .needs
        case .sent: return .sent
        case .error: return .error
        }
    }

    // MARK: Step

    func advance(to date: Date, kind newKind: MoodKind, allowMotion motion: Bool, corner c: BuddyCorner) {
        allowMotion = motion; corner = c
        let dt = min(0.05, max(0, date.timeIntervalSince(last ?? date))); last = date; t += dt
        if newKind != kind {
            kind = newKind
            let next = Self.state(for: newKind, current: state)
            if next != state { setState(next) }
        }
        if state == .idle && te > 300 { setState(.sleep) }
        if state == .wake && te > 2.6 { setState(.idle) }
        if t > nextAmbient && state == .idle { ambient(); nextAmbient = t + 5 + Double.random(in: 0..<3) }
        updateVoice(dt)
        for i in 0..<3 {
            let f = 1 - exp(-dt * 5)
            cur[i].approach(tgt[i], f)
        }
        if ![.sleep, .thinking, .error].contains(state) && t > nextBlink {
            blink = t; dbl = Double.random(in: 0..<1) < 0.2; nextBlink = t + 2.2 + Double.random(in: 0..<3.4)
        }
        var (gazeX, gazeY) = cursorGaze()
        if let g = glance, t < g.until { gazeX = g.x; gazeY = g.y } else { glance = nil }
        switch state {
        case .meeting: gazeX = corner.isTrailing ? -0.8 : 0.8; gazeY = corner.isBottom ? -0.8 : 0.8
        case .thinking, .sent: gazeX = 0.8; gazeY = -0.9
        case .error: gazeX = 0; gazeY = 0.8
        case .sleep, .wake: gazeX = 0; gazeY = 0
        default: break
        }
        gx.to(gazeX * 2.6); gy.to(gazeY * 2)
        if state == .sent && at("throw", 0.2) { sy.to(1); sx.to(1); hop(-170); sendT = t }
        if state == .finished && at("h2", 0.6) { hop(-100) }
        if state == .needs && t - nudge > 3.2 { nudge = t; hop(-70) }
        if state == .error && at("k2", 0.3) && allowMotion { x.kick(-140) }
        if state == .wake && at("pop", 0.3) && allowMotion { sy.kick(3.4); sx.kick(-2.2) }
        y.step(dt); x.step(dt); sx.step(dt); sy.step(dt); gx.step(dt); gy.step(dt)
    }

    /// Eyes follow the pointer: AppKit's global mouse position against where the character sits in its window.
    private func cursorGaze() -> (Double, Double) {
        guard let w = window else { return (0, 0) }
        let f = w.frame, half = Double(BuddyMetrics.characterSize / 2), pad = Double(BuddyMetrics.outerPadding)
        let cx = corner.isTrailing ? f.maxX - pad - half : f.minX + pad + half
        let cy = corner.isBottom ? f.minY + pad + half : f.maxY - pad - half
        let m = NSEvent.mouseLocation
        return (clamp((m.x - cx) / 230, -1, 1), clamp((cy - m.y) / 230, -1, 1))
    }

    /// The real mic level is not plumbed into the model yet, so listening uses simulated speech.
    private func updateVoice(_ dt: Double) {
        guard state == .listening else { level += (0 - level) * (1 - exp(-dt * 9)); return }
        let syl = pow(max(0, sin(t * 2 * .pi * 2.6 + noise1(t * 1.3) * 2.6)), 1.4)
        let phrase = clamp((noise1(t * 0.55 + 3) + 0.35) * 1.6)
        let target = clamp(syl * (0.25 + 0.75 * phrase) + noise1(t * 23) * 0.05 + 0.05)
        level += (target - level) * (1 - exp(-dt * (target > level ? 32 : 9)))
    }

    private func closed() -> Bool {
        func one(_ d: Double) -> Bool { d >= 0 && d < 0.12 }
        return one(t - blink) || (dbl && one(t - blink - 0.26))
    }

    // MARK: Draw

    func draw(_ ctx: inout GraphicsContext, size: CGSize, scale: CGFloat) {
        ctx.translateBy(x: size.width / 2, y: size.height / 2)
        ctx.scaleBy(x: scale, y: scale)
        let s = state, tt = t, e = te
        let vs = clamp(-y.v * 0.0011, -0.16, 0.16)
        let breath = sin(tt * 2 * .pi / 3.2) * (s == .sleep ? 0.05 : 0.03) * (allowMotion ? 1 : 0.4)
        let lv = s == .listening ? level : 0
        let R0 = 24.0, N = 20
        let scx = (sx.x - vs * 0.6) * (1 - breath * 0.6) * (1 + lv * 0.1)
        let scy = (sy.x + vs) * (1 + breath) * (1 + lv * 0.1)
        let Rx = R0 * scx, Ry = R0 * scy, cx = x.x, cy = 22 - Ry + y.x * 0.9
        let c1 = cur[0], c2 = cur[1], c3 = cur[2]

        func blob() -> Path {
            var pts: [CGPoint] = []
            for i in 0..<N {
                let a = Double(i) / Double(N) * 2 * .pi
                let w = 1 + 0.045 * noise2(cos(a) * 1.2 + tt * 0.5, sin(a) * 1.2 + tt * 0.42) + lv * 0.07 * sin(a * 3 + tt * 9)
                pts.append(CGPoint(x: cx + cos(a) * Rx * w, y: cy + sin(a) * Ry * w))
            }
            func mid(_ p: CGPoint, _ q: CGPoint) -> CGPoint { CGPoint(x: (p.x + q.x) / 2, y: (p.y + q.y) / 2) }
            var path = Path(); path.move(to: mid(pts[N - 1], pts[0]))
            for i in 0..<N { path.addQuadCurve(to: mid(pts[i], pts[(i + 1) % N]), control: pts[i]) }
            path.closeSubpath(); return path
        }
        func circle(_ x: Double, _ y: Double, _ r: Double) -> Path { Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)) }
        func oval(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double) -> Path { Path(ellipseIn: CGRect(x: x - rx, y: y - abs(ry), width: 2 * rx, height: 2 * abs(ry))) }
        func ring(_ r: Double, _ color: Color, _ w: Double) { ctx.stroke(circle(cx, cy, r), with: .color(color), lineWidth: w) }

        /* ground shadow + glow */
        let lift = max(0, -y.x)
        ctx.fill(oval(cx, 23, Rx * 0.8 * (1 - lift * 0.004), 2.6), with: .color(.black.opacity(0.35 * clamp(1 - lift * 0.012))))
        let glow = 0.3 + (s == .needs ? 0.25 * sin(tt * 4.2) : 0) + lv * 0.3
        ctx.fill(circle(cx, cy, Rx * 1.75), with: .radialGradient(Gradient(colors: [c1.color(glow), c1.color(0)]), center: CGPoint(x: cx, y: cy), startRadius: Rx * 0.4, endRadius: Rx * 1.75))

        /* rings behind */
        if s == .listening { for j in 0..<3 { let ph = (tt * 1.1 + Double(j) / 3).truncatingRemainder(dividingBy: 1); ring(Rx * (1.05 + ph * 0.9), c2.color((1 - ph) * (0.25 + lv * 0.6)), 1.5) } }
        if s == .needs { let ph = (e.truncatingRemainder(dividingBy: 1.2)) / 1.2; ring(Rx * (1.02 + ph * 0.9), c2.color((1 - ph) * 0.8), 2.2) }
        if s == .wake && e < 0.9 { let ph = e / 0.9; ring(Rx * (1 + ph * 1.1), c3.color((1 - ph) * 0.8), 2) }

        /* body */
        let ang = tt * 0.6 + (s == .thinking ? tt * 3 : 0)
        let lg = GraphicsContext.Shading.linearGradient(Gradient(stops: [.init(color: c1.color(), location: 0), .init(color: c2.color(), location: 0.5), .init(color: c3.color(), location: 1)]),
            startPoint: CGPoint(x: cx + cos(ang) * Rx, y: cy + sin(ang) * Ry), endPoint: CGPoint(x: cx - cos(ang) * Rx, y: cy - sin(ang) * Ry))
        let body = blob()
        ctx.fill(body, with: lg)
        ctx.fill(body, with: .radialGradient(Gradient(colors: [Color(red: 0.08, green: 0, blue: 0.27).opacity(0.3), Color(red: 0.08, green: 0, blue: 0.27).opacity(0)]),
            center: CGPoint(x: cx, y: cy + Ry * 0.95), startRadius: 1, endRadius: Rx * 1.1))
        ctx.fill(body, with: .radialGradient(Gradient(stops: [.init(color: .white.opacity(0.6), location: 0), .init(color: .white.opacity(0.08), location: 0.6), .init(color: .white.opacity(0), location: 1)]),
            center: CGPoint(x: cx - Rx * 0.35, y: cy - Ry * 0.5), startRadius: 1, endRadius: Rx * 1.05))
        ctx.stroke(body, with: .color(.white.opacity(0.4)), lineWidth: 0.8)
        do {
            var c = ctx; c.translateBy(x: cx - Rx * 0.42, y: cy - Ry * 0.62); c.rotate(by: .radians(-0.6))
            c.fill(oval(0, 0, Rx * 0.16, Ry * 0.08), with: .color(.white.opacity(0.75)))
        }

        /* face */
        let ink = Color(red: 0.106, green: 0.063, blue: 0.22)
        let ey = cy - Ry * 0.05 + gy.x, mx = cx + gx.x * 0.6
        let base: Double = s == .sleep ? 0 : s == .thinking ? 0.55 : s == .needs ? 1.22 : 1
        let eo = closed() ? 0.06 : base
        let line = StrokeStyle(lineWidth: 1.9, lineCap: .round)
        for sg in [-1.0, 1.0] {
            let exx = mx + sg * Rx * 0.34 + gx.x * 0.5
            if s == .sent || s == .finished {
                var p = Path(); p.move(to: CGPoint(x: exx - 3.2, y: ey + 1.6)); p.addQuadCurve(to: CGPoint(x: exx + 3.2, y: ey + 1.6), control: CGPoint(x: exx, y: ey - 3.6))
                ctx.stroke(p, with: .color(ink), style: line)
            } else if s == .sleep || eo < 0.1 {
                var p = Path(); p.move(to: CGPoint(x: exx - 3, y: ey)); p.addQuadCurve(to: CGPoint(x: exx + 3, y: ey), control: CGPoint(x: exx, y: ey + 2))
                ctx.stroke(p, with: .color(ink), style: line)
            } else {
                ctx.fill(oval(exx, ey, 3.1, 4.4 * eo), with: .color(ink))
                ctx.fill(circle(exx - 1.1, ey - 1.5 * eo, 1.15), with: .color(.white))
            }
            ctx.fill(oval(exx + sg * 1.8, ey + 6.2, 3, 1.8), with: .color(Color(red: 1, green: 0.47, blue: 0.67).opacity(0.42)))
        }
        let my = ey + 6.5
        switch s {
        case .listening: ctx.fill(oval(mx, my, 2.4, 1.2 + level * 3.4), with: .color(ink))
        case .needs: ctx.fill(oval(mx, my, 2, 2.7), with: .color(ink))
        case .sent, .finished:
            var p = Path(); p.move(to: CGPoint(x: mx - 4, y: my - 1)); p.addQuadCurve(to: CGPoint(x: mx + 4, y: my - 1), control: CGPoint(x: mx, y: my + 6)); p.closeSubpath()
            ctx.fill(p, with: .color(ink))
        case .error:
            var p = Path(); p.move(to: CGPoint(x: mx - 3, y: my + 1.5)); p.addQuadCurve(to: CGPoint(x: mx + 3, y: my + 1.5), control: CGPoint(x: mx, y: my - 2.5))
            ctx.stroke(p, with: .color(ink), style: line)
        case .sleep: break
        default:
            var p = Path(); p.move(to: CGPoint(x: mx - 3, y: my - 0.5)); p.addQuadCurve(to: CGPoint(x: mx + 3, y: my - 0.5), control: CGPoint(x: mx, y: my + 3.2))
            ctx.stroke(p, with: .color(ink), style: line)
        }

        /* extras in front */
        if s == .thinking {
            for j in 0..<3 { let a = tt * 4 + Double(j) * 2 * .pi / 3
                ctx.fill(circle(cx + cos(a) * Rx * 1.3, cy + sin(a) * Ry * 0.55 - Ry * 0.6, 2.3), with: .color(cur[j].color(0.95))) }
        }
        if s == .error { let d = (e * 1.8).truncatingRemainder(dividingBy: 1); ctx.fill(oval(cx + Rx * 0.5, ey + 3 + d * 12, 1.4, 2), with: .color(Color(red: 0.49, green: 0.83, blue: 0.99))) }
        if s == .sleep && e > 0.8 {
            for j in 0..<3 {
                let ph = ((e - 0.8 + Double(j) * 1.3).truncatingRemainder(dividingBy: 3.9)) / 3.9
                var c = ctx; c.opacity = sin(.pi * ph)
                c.draw(Text("z").font(.system(size: 5 + ph * 4, weight: .semibold, design: .rounded)).foregroundColor(.white.opacity(0.85)),
                       at: CGPoint(x: cx + Rx * 0.6 + ph * 10, y: cy - Ry * 0.8 - ph * 14))
            }
        }
        if s == .finished {
            let tq = e - 0.1
            if tq > 0 && tq < 1.7 {
                for j in 0..<14 {
                    let a = -Double.pi / 2 + (hash(Double(j) * 3.3) - 0.5) * 2.4, speed = (38 + hash(Double(j) * 7.7) * 50) * 0.6
                    let px = cx + cos(a) * speed * tq, py = cy - Ry * 0.6 + sin(a) * speed * tq + 40 * tq * tq
                    let col = j % 3 == 0 ? Color.white : cur[j % 3].color()
                    ctx.fill(circle(px, py, 1.5 + hash(Double(j)) * 1.3), with: .color(col.opacity(clamp(1 - tq / 1.7))))
                }
            }
        }
        let ps = tt - sendT
        if ps > 0 && ps < 1 {
            for j in stride(from: 3, through: 0, by: -1) {
                let ee = easeOut(ps - Double(j) * 0.04)
                let col = j == 0 ? Color.white : c1.color()
                ctx.fill(circle(cx + ee * 26, cy - Ry * 0.5 - ee * 24, 3.6 - Double(j) * 0.6), with: .color(col.opacity((1 - ps) * (1 - Double(j) * 0.22))))
            }
        }
    }
}

/// Zero-size NSView that hands the host window to the engine (for cursor-following eyes).
struct JellyWindowProbe: NSViewRepresentable {
    let engine: any SkinEngine
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { engine.window = view.window }
    }
}

/// 30 fps while the jelly moves. When calm it animates in short bursts (0.9 s every 5 s) and the
/// timeline sleeps in between: any steady rate above ~1 fps costs the same as 30 fps, so sparse
/// bursts are what keeps idle CPU near zero. Mood changes and clicks restart the timeline.
struct JellySchedule: TimelineSchedule {
    let engine: any SkinEngine
    func entries(from start: Date, mode: TimelineScheduleMode) -> UnfoldFirstSequence<Date> {
        sequence(first: start) { previous in previous.addingTimeInterval(engine.nextInterval(after: previous)) }
    }
}
