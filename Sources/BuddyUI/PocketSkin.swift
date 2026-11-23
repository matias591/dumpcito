import AppKit
import BuddyCore
import SwiftUI

/// Internal state of the pocket handheld. The app only has MoodKind; sleep/wake are internal
/// (long idle, then the first poke or event). No thinking state: the app has no such mood.
private enum PocketState { case idle, meeting, listening, sent, finished, needs, error, sleep, wake }

private struct PocketSpring {
    var x: Double, v = 0.0, t: Double, k = 0.0, c = 0.0
    init(_ x: Double, _ response: Double, _ damping: Double) {
        self.x = x; t = x
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

private func pocketHash(_ n: Double) -> Double { let v = sin(n * 127.1 + 311.7) * 43758.5453; return v - v.rounded(.down) }
private func pocketClamp(_ x: Double, _ a: Double = 0, _ b: Double = 1) -> Double { min(b, max(a, x)) }
private func pocketColor(_ hex: UInt32, _ a: Double = 1) -> Color {
    Color(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: a)
}

/// LED colour per state (antenna).
private let pocketLED: [PocketState: UInt32] = [
    .idle: 0x34D399, .meeting: 0xFBBF24, .listening: 0x38BDF8, .sent: 0xFFFFFF, .finished: 0x34D399,
    .needs: 0xFF4D4D, .error: 0xFF4D4D, .sleep: 0x3A3D46, .wake: 0xFFFFFF,
]

/// 3x5 "z" and 5 glyphs, and the 2x7 exclamation mark, as pixel rows.
private let pocketZ = ["111", "001", "010", "100", "111"]
private let pocketFive = ["111", "100", "111", "001", "111"]
private let pocketBang = ["11", "11", "11", "11", "11", "00", "11"]
private let pocketTick: [(Int, Int)] = [(2, 5), (3, 6), (4, 7), (5, 6), (6, 5), (7, 4), (8, 3), (9, 2)]

/// Pocket handheld with a green LCD face: pixel eyes and mouth, per-mood screens, springs for
/// every motion. Time-driven, so all of it happens in `advance` + `draw`; nothing touches the model.
final class PocketEngine: SkinEngine {
    private var state = PocketState.idle
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

    /// Nothing is moving except the LED and the cursor, both of which only animate inside the bursts.
    private var isCalm: Bool {
        (state == .idle || state == .sleep) && glance == nil && te > 0.8 && level < 0.01 && t - blink > 0.7
            && t - pressA > 0.4 && t - pressB > 0.4 && t - pressD > 0.4
            && abs(y.v) < 1 && abs(y.x) < 0.5 && abs(x.v) < 1 && abs(rot.v) < 0.05 && abs(rot.x) < 0.02
    }

    private var t = 0.0, t0 = 0.0, last: Date?
    private var y = PocketSpring(0, 0.4, 0.5), x = PocketSpring(0, 0.2, 0.3), rot = PocketSpring(0, 0.38, 0.32)
    private var blink = -9.0, dbl = false, nextBlink = 2.0, nextAmbient = 6.0
    private var glance: (x: Double, y: Double, until: Double)?
    private var fired = Set<String>(), nudge = 0.0
    private var pressA = -9.0, pressB = -9.0, pressD = -9.0, pressDir = 0.0
    private var gazeX = 0, gazeY = 0
    private var level = 0.0

    private var te: Double { t - t0 }
    private func at(_ key: String, _ time: Double) -> Bool {
        if te >= time && !fired.contains(key) { fired.insert(key); return true }
        return false
    }
    private func hop(_ v: Double) { if allowMotion { y.kick(v) } }
    private func tilt(_ v: Double) { if allowMotion { rot.kick(v) } }

    // MARK: State

    func poke() { if state == .sleep { setState(.wake) } }

    private func setState(_ s: PocketState) {
        state = s; t0 = t; fired = []; nudge = t
        switch s {
        case .meeting: hop(-45); tilt(1.2)
        case .listening: hop(-30)
        case .sent: hop(-70); pressA = t + 0.1
        case .finished: hop(-150); tilt(-1.6); pressB = t + 0.15
        case .needs: hop(-90); tilt(-1.4)
        case .error: if allowMotion { x.kick(170) }
        case .wake: tilt(2)
        default: break
        }
    }

    private func ambient() {
        let k = Double.random(in: 0..<1)
        if k < 0.4 {
            glance = (Bool.random() ? -1 : 1, Double(Int.random(in: -1...1)), t + 1 + Double.random(in: 0..<0.6))
            pressD = t; pressDir = glance?.x ?? 0
        } else if k < 0.6 { blink = t; dbl = true }
        else if k < 0.8 { tilt((Bool.random() ? -1 : 1) * 1.3); pressB = t }
        else { hop(-45) }
    }

    private static func state(for kind: MoodKind, current: PocketState) -> PocketState {
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
        if ![.sleep, .error, .wake].contains(state) && t > nextBlink {
            blink = t; dbl = Double.random(in: 0..<1) < 0.2; nextBlink = t + 2.6 + Double.random(in: 0..<3.6)
        }
        var (tx, ty) = cursorGaze()
        tx *= 1.4; ty *= 1.2
        if let g = glance, t < g.until { tx = g.x; ty = g.y } else { glance = nil }
        if state == .listening { tx *= 0.3; ty = 0 }
        if state == .sleep || state == .wake { tx = 0; ty = 0 }
        gazeX = Int(pocketClamp(tx.rounded(), -1, 1)); gazeY = Int(pocketClamp(ty.rounded(), -1, 1))
        if state == .finished && at("h2", 0.62) { hop(-85) }
        if state == .error && at("k2", 0.3) && allowMotion { x.kick(-130) }
        if state == .needs && t - nudge > 3.2 { nudge = t; hop(-60); tilt(1.3) }
        y.step(dt); x.step(dt); rot.step(dt)
    }

    /// Eyes follow the pointer: AppKit's global mouse position against where the character sits in its window.
    private func cursorGaze() -> (Double, Double) {
        guard let w = window else { return (0, 0) }
        let f = w.frame, half = Double(BuddyMetrics.characterSize / 2), pad = Double(BuddyMetrics.outerPadding)
        let cx = corner.isTrailing ? f.maxX - pad - half : f.minX + pad + half
        let cy = corner.isBottom ? f.minY + pad + half : f.maxY - pad - half
        let m = NSEvent.mouseLocation
        return (pocketClamp((m.x - cx) / 230, -1, 1), pocketClamp((cy - m.y) / 230, -1, 1))
    }

    /// The real mic level is not plumbed into the model yet, so listening uses simulated speech.
    private func updateVoice(_ dt: Double) {
        guard state == .listening else { level += (0 - level) * (1 - exp(-dt * 9)); return }
        let syl = pow(max(0, sin(t * 2 * .pi * 2.6 + sin(t * 1.3) * 2.6)), 1.4)
        let phrase = pocketClamp((sin(t * 0.55 + 3) * 0.5 + 0.35) * 1.6)
        let target = pocketClamp(syl * (0.25 + 0.75 * phrase) + 0.05)
        level += (target - level) * (1 - exp(-dt * (target > level ? 32 : 9)))
    }

    private func closed() -> Bool {
        func one(_ d: Double) -> Bool { d >= 0 && d < 0.11 }
        return one(t - blink) || (dbl && one(t - blink - 0.24))
    }

    // MARK: Draw

    func draw(_ ctx: inout GraphicsContext, size: CGSize, scale: CGFloat) {
        ctx.translateBy(x: size.width / 2, y: size.height / 2)
        ctx.scaleBy(x: scale, y: scale)
        let s = state, tt = t, e = te, calm = allowMotion
        func rr(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ r: Double) -> Path {
            Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: r)
        }
        func circle(_ x: Double, _ y: Double, _ r: Double) -> Path { Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)) }

        let buzz = s == .needs && calm && e.truncatingRemainder(dividingBy: 3.2) < 0.5 ? 0.03 * sin(tt * 70) : 0
        let ang = rot.x * 0.1 + buzz
        ctx.translateBy(x: x.x, y: 24 + y.x)
        ctx.rotate(by: .radians(ang))

        /* ground shadow (counter-rotated so it stays flat) */
        let lift = max(0, -y.x)
        do {
            var g = ctx; g.rotate(by: .radians(-ang))
            g.fill(Path(ellipseIn: CGRect(x: -18, y: 1 - 2.5, width: 36, height: 5)), with: .color(.black.opacity(0.35 * pocketClamp(1 - lift * 0.012))))
        }

        /* antenna + LED */
        let on: Bool
        switch s {
        case .idle: on = tt.truncatingRemainder(dividingBy: 2.4) < 1.6
        case .meeting: on = tt.truncatingRemainder(dividingBy: 1) < 0.5
        case .listening: on = level > 0.1
        case .needs: on = tt.truncatingRemainder(dividingBy: 0.5) < 0.25
        case .error: on = pocketHash(Double(Int(tt * 9))) > 0.3
        case .sleep: on = false
        default: on = true
        }
        let led = pocketLED[s] ?? 0x34D399
        var ant = Path(); ant.move(to: CGPoint(x: 12, y: -45)); ant.addLine(to: CGPoint(x: 15, y: -54))
        ctx.stroke(ant, with: .color(pocketColor(0x8D897C)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        if on { ctx.fill(circle(15, -54.5, 5.2), with: .color(pocketColor(led, 0.3))) }
        ctx.fill(circle(15, -54.5, 2.2), with: .color(on ? pocketColor(led) : pocketColor(0x4A4C55)))

        /* body */
        let body = rr(-18, -46, 36, 46, 8)
        do {
            var sh = ctx; sh.addFilter(.shadow(color: .black.opacity(0.3), radius: 4.5, x: 0, y: 3))
            sh.fill(body, with: .linearGradient(Gradient(colors: [pocketColor(0xF8F6F0), pocketColor(0xDBD8CC)]), startPoint: CGPoint(x: 0, y: -46), endPoint: CGPoint(x: 0, y: 0)))
        }
        ctx.stroke(body, with: .color(.black.opacity(0.2)), lineWidth: 0.7)
        ctx.fill(rr(-14.5, -42.5, 29, 24, 4), with: .color(pocketColor(0x2B2D36)))

        /* LCD */
        let LX = -12.5, LY = -40.0, u = 1.78
        let asleep = s == .sleep
        var inv = false
        if s == .needs { inv = Int(e / 0.45) % 2 == 0 }
        if s == .meeting { inv = e.truncatingRemainder(dividingBy: 1.6) < 0.14 }
        let bgc = inv ? pocketColor(0x26311B) : asleep ? pocketColor(0x8FA874) : pocketColor(0xC8E6A0)
        let ink = inv ? pocketColor(0xC8E6A0) : asleep ? pocketColor(0x4A5C38) : pocketColor(0x25301A)
        let lcd = rr(LX, LY, 25, 19, 2.5)
        ctx.fill(lcd, with: .color(bgc))
        var l = ctx; l.clip(to: lcd)
        let jit = s == .error && e < 0.7 && calm ? (pocketHash(Double(Int(tt * 20))) - 0.5 > 0 ? 0.9 : -0.9) : 0
        func P(_ c: Int, _ r: Int, _ col: Color? = nil) {
            l.fill(Path(CGRect(x: LX + 1.2 + Double(c) * u + jit, y: LY + 1.1 + Double(r) * u, width: u + 0.25, height: u + 0.25)), with: .color(col ?? ink))
        }
        func pat(_ g: [String], _ c: Int, _ r: Int) {
            for (j, row) in g.enumerated() { for (i, v) in row.enumerated() where v == "1" { P(c + i, r + j) } }
        }
        func face() {
            var eyes = 0   // 0 open, 1 blink, 2 closed
            if closed() { eyes = 1 }
            if asleep { eyes = 2 }
            if s == .wake { eyes = e < 0.9 ? 2 : e < 1.2 ? 1 : 0 }
            for L in [3, 9] {
                if eyes == 0 { for j in 0..<3 { for i in 0..<2 { P(L + i + gazeX, 2 + j + gazeY) } } }
                else if eyes == 1 { P(L, 3); P(L + 1, 3) }
                else { P(L, 4); P(L + 1, 4) }
            }
            if !asleep { P(5, 7); P(6, 8); P(7, 8); P(8, 7) } else { P(6, 7); P(7, 7) }
        }
        switch s {
        case .meeting:
            for i in 3..<11 { P(i, 1); P(i, 2); P(i, 8) }
            for j in 1..<9 { P(3, j); P(10, j) }
            pat(pocketFive, 5, 3); P(4, 0); P(9, 0)
        case .listening:
            for i in 0..<7 {
                let band = pocketClamp(level * (0.55 + 0.45 * sin(tt * 9 + Double(i) * 1.7)))
                for j in 0..<(1 + Int((band * 7).rounded())) { P(1 + i * 2, 8 - j) }
            }
        case .sent:
            if e < 0.7 {
                let c = Int(e * 14) - 2
                for j in 0..<5 { for i in 0...(2 - abs(j - 2)) { P(c + i, 2 + j) } }
            } else { for (c, r) in pocketTick { P(c, r); P(c + 1, r) } }
        case .finished:
            for (c, r) in pocketTick { P(c, r); P(c + 1, r) }
            if Int(tt * 6) % 2 == 1 { P(11, 1); P(12, 0); P(12, 2); P(1, 8) }
        case .needs:
            if inv { pat(pocketBang, 6, 1) } else { face() }
        case .error:
            for i in 0..<7 { P(3 + i, 1 + i); P(4 + i, 1 + i); P(9 - i, 1 + i); P(10 - i, 1 + i) }
        case .wake where e < 0.8:
            let n = Int(e / 0.8 * 10)
            for r in 0...n { for c in stride(from: r % 2, to: 14, by: 2) { P(c, r) } }
        default:
            face()
            if asleep {
                for j in 0..<2 {
                    let ph = ((e + Double(j) * 1.6).truncatingRemainder(dividingBy: 3.2)) / 3.2
                    l.opacity = sin(.pi * ph)
                    pat(pocketZ, 10 + j, 4 - Int(ph * 4) - j * 2)
                }
                l.opacity = 1
            } else if s == .idle {
                // Blinking text cursor; only visible (and only moving) inside animation bursts.
                if tt.truncatingRemainder(dividingBy: 1.0) < 0.5 { P(10, 9); P(11, 9) }
            }
        }
        var y0 = LY
        while y0 < LY + 19 { l.fill(Path(CGRect(x: LX, y: y0, width: 25, height: 0.5)), with: .color(.black.opacity(0.05))); y0 += 1.4 }
        ctx.draw(Text("buddy").font(.system(size: 3.4, weight: .medium, design: .monospaced)).foregroundColor(.black.opacity(0.38)),
                 at: CGPoint(x: -13.5, y: -15.6), anchor: .bottomLeading)

        /* controls */
        let pd = tt - pressD < 0.25 ? pressDir * 0.7 : 0
        func dn(_ since: Double) -> Double { since >= 0 && since < 0.18 ? 0.7 : 0 }
        let pa = dn(tt - pressA), pb = dn(tt - pressB)
        let pad = Color(red: 0.227, green: 0.235, blue: 0.275)
        ctx.fill(rr(-13.4 + pd, -10.8, 8.8, 2.9, 1), with: .color(pad))
        ctx.fill(rr(-10.5 + pd, -13.7, 2.9, 8.8, 1), with: .color(pad))
        ctx.fill(circle(10.5, -11 + pa, 3.3), with: .color(pocketColor(0x2F5BFF)))
        ctx.fill(circle(9.6, -12.2 + pa, 1.1), with: .color(.white.opacity(0.35)))
        ctx.fill(circle(4.8, -6.6 + pb, 3.3), with: .color(pocketColor(0xFF6B6B)))
        ctx.fill(circle(3.9, -7.8 + pb, 1.1), with: .color(.white.opacity(0.35)))
        for i in 0..<6 {
            let r = 0.65 + (s == .listening ? level * 0.9 * ((i + 1) % 3 != 0 ? 1 : 0.6) : 0)
            ctx.fill(circle(-8.5 + Double(i) * 3.4, -2.8, r), with: .color(Color(red: 0.157, green: 0.157, blue: 0.18).opacity(0.55)))
        }
    }
}
