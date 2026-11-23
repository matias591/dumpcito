import AppKit
import BuddyCore
import SwiftUI

/// Internal state of the pixel mascot. The app only has MoodKind; sleep/wake are internal
/// (long idle, then the first poke or event). Thinking is unused for now but kept for parity with the concept.
private enum PixelState { case idle, meeting, listening, thinking, sent, finished, needs, error, sleep, wake }

private struct PixelSpring {
    var x: Double, v = 0.0, t: Double, k = 0.0, c = 0.0
    init(_ x: Double, _ response: Double, _ damping: Double) {
        self.x = x; t = x
        k = pow(2 * .pi / response, 2); c = 4 * .pi * damping / response
    }
    mutating func kick(_ dv: Double) { v += dv }
    /// Sub-stepped at 240 Hz so stiff springs stay stable at 30 fps.
    mutating func step(_ dt: Double) {
        let n = max(1, Int((dt * 240).rounded(.up))), h = dt / Double(n)
        for _ in 0..<n { v += (k * (t - x) - c * v) * h; x += v * h }
    }
}

private struct PixelRGB {
    var r: Double, g: Double, b: Double
    init(_ hex: UInt32) { r = Double((hex >> 16) & 255); g = Double((hex >> 8) & 255); b = Double(hex & 255) }
    init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }
    mutating func approach(_ o: PixelRGB, _ f: Double) { r += (o.r - r) * f; g += (o.g - g) * f; b += (o.b - b) * f }
    func mixed(_ o: PixelRGB, _ t: Double) -> PixelRGB { PixelRGB(r: r + (o.r - r) * t, g: g + (o.g - g) * t, b: b + (o.b - b) * t) }
    var color: Color { Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: 1) }
}

private func pixelColor(_ hex: UInt32) -> Color { PixelRGB(hex).color }
private func pixelHash(_ n: Double) -> Double { let v = sin(n * 127.1 + 311.7) * 43758.5453; return v - v.rounded(.down) }
private func pixelNoise(_ x: Double) -> Double {
    let i = x.rounded(.down), f = x - i, u = f * f * (3 - 2 * f)
    return (pixelHash(i) + (pixelHash(i + 1) - pixelHash(i)) * u) * 2 - 1
}
private func pixelClamp(_ x: Double, _ a: Double = 0, _ b: Double = 1) -> Double { min(b, max(a, x)) }
private func pixelEaseOut(_ t: Double) -> Double { 1 - pow(1 - pixelClamp(t), 3) }

/// Whole-body colour per state, plus the antenna LED colour.
private let pixelBody: [PixelState: UInt32] = [
    .idle: 0x5EEAD4, .meeting: 0xFDE047, .listening: 0x7DD3FC, .thinking: 0xC4B5FD, .sent: 0x5EEAD4, .finished: 0x86EFAC,
    .needs: 0xFF7A8A, .error: 0xB8B2AA, .sleep: 0x3FBFAE, .wake: 0x5EEAD4,
]
private let pixelLED: [PixelState: UInt32] = [
    .idle: 0x22C55E, .meeting: 0xFACC15, .listening: 0x38BDF8, .thinking: 0x22D3EE, .sent: 0xFFFFFF, .finished: 0x22C55E,
    .needs: 0xFF3B4E, .error: 0xFF3B4E, .sleep: 0x2B2357, .wake: 0xFFFFFF,
]

/// Tiny 1-bit glyphs, one string per row.
private let pixelZ = ["111", "001", "010", "100", "111"]
private let pixelBang = ["11", "11", "11", "00", "11"]
private let pixelPlus = ["010", "111", "010"]

private enum PixelKind { case outline, shade, highlight, body }
private struct PixelCell { let c: Int, r: Int, kind: PixelKind }

/// The body silhouette: a 16 x 13 rounded block (corner radius 5) with a 1-cell outline,
/// a shaded bottom and a small highlight top-left. Built once.
private let pixelCells: [PixelCell] = {
    func inside(_ c: Int, _ r: Int) -> Bool {
        let x = Double(c) + 0.5, y = Double(r) + 0.5
        let dx = max(5 - x, 0, x - 11), dy = max(5 - y, 0, y - 8)
        return r >= 0 && r < 13 && c >= 0 && c < 16 && dx * dx + dy * dy <= 25
    }
    var out: [PixelCell] = []
    for r in 0..<13 {
        for c in 0..<16 where inside(c, r) {
            let edge = !inside(c - 1, r) || !inside(c + 1, r) || !inside(c, r - 1) || !inside(c, r + 1)
            let kind: PixelKind = edge ? .outline : r >= 9 ? .shade : ((r == 1 || r == 2) && c >= 2 && c <= 4) ? .highlight : .body
            out.append(PixelCell(c: c, r: r, kind: kind))
        }
    }
    return out
}()

/// 8-bit mascot: everything snaps to a 16-column pixel grid, the whole body tints per state and
/// the antenna LED reports status. Time-driven like Jelly, so all of it happens in `advance` + `draw`.
final class PixelEngine: SkinEngine {
    private var state = PixelState.idle
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

    /// Nothing is moving except the idle LED blink, so frames can be sparse.
    private var isCalm: Bool {
        (state == .idle || state == .sleep) && glance == nil && te > 0.8 && level < 0.01 && t - blink > 0.7
            && t - flick > 0.5 && abs(y.v) < 1 && abs(y.x) < 0.5 && abs(x.v) < 1 && abs(x.x) < 0.5
    }

    /// Design unit: one grid cell in points (designed at 58 pt). Spring kicks were tuned for 3.1.
    private let U = 2.6
    private var kscale: Double { U / 3.1 }

    private var t = 0.0, t0 = 0.0, last: Date?
    private var y = PixelSpring(0, 0.4, 0.5), x = PixelSpring(0, 0.18, 0.3)
    private var blink = -9.0, dbl = false, nextBlink = 2.0, nextAmbient = 6.0, flick = -9.0
    private var glance: (x: Int, y: Int, until: Double)?
    private var fired = Set<String>(), nudge = 0.0, sendT = -9.0
    private var cur = PixelRGB(pixelBody[.idle] ?? 0)
    private var tgt = PixelRGB(pixelBody[.idle] ?? 0)
    private var gaze = (x: 0, y: 0)
    private var level = 0.0

    private var te: Double { t - t0 }
    private func at(_ key: String, _ time: Double) -> Bool {
        if te >= time && !fired.contains(key) { fired.insert(key); return true }
        return false
    }
    private func hop(_ v: Double) { if allowMotion { y.kick(v * kscale) } }

    // MARK: State

    func poke() { if state == .sleep { setState(.wake) } }

    private func setState(_ s: PixelState) {
        state = s; t0 = t; fired = []; nudge = t
        tgt = PixelRGB(pixelBody[s] ?? 0x5EEAD4)
        guard allowMotion else { return }
        switch s {
        case .meeting: hop(-45)
        case .listening: hop(-35)
        case .sent: hop(-80)
        case .finished: hop(-150)
        case .needs: hop(-90)
        case .error: x.kick(160 * kscale)
        default: break
        }
    }

    private func ambient() {
        let k = Double.random(in: 0..<1)
        if k < 0.35 { glance = (Bool.random() ? -1 : 1, Int.random(in: -1...1), t + 1 + Double.random(in: 0..<0.6)) }
        else if k < 0.55 { blink = t; dbl = true }
        else if k < 0.75 { hop(-40) }
        else { flick = t }
    }

    private static func state(for kind: MoodKind, current: PixelState) -> PixelState {
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
        cur.approach(tgt, 1 - exp(-dt * 6))
        if ![.sleep, .thinking, .error, .wake].contains(state) && t > nextBlink {
            blink = t; dbl = Double.random(in: 0..<1) < 0.2; nextBlink = t + 2.4 + Double.random(in: 0..<3.6)
        }
        // Gaze snaps to the grid: each eye shifts by at most one cell.
        let (cx, cy) = cursorGaze()
        var tx = cx * 1.4, ty = cy * 1.2
        if let g = glance, t < g.until { tx = Double(g.x); ty = Double(g.y) } else { glance = nil }
        switch state {
        case .meeting: tx = corner.isTrailing ? -1 : 1; ty = corner.isBottom ? -1 : 1
        case .thinking, .sent: tx = 1; ty = -1
        case .error: tx = 0; ty = 1
        case .sleep, .wake: tx = 0; ty = 0
        case .listening: tx *= 0.3; ty = 0
        default: break
        }
        gaze = (Int(pixelClamp(tx.rounded(), -1, 1)), Int(pixelClamp(ty.rounded(), -1, 1)))
        if state == .finished && at("h2", 0.62) { hop(-90) }
        if state == .error && at("k2", 0.3) && allowMotion { x.kick(-140 * kscale) }
        if state == .needs && t - nudge > 3.2 { nudge = t; hop(-70) }
        if state == .sent && at("throw", 0.2) { sendT = t }
        y.step(dt); x.step(dt)
    }

    /// Eyes follow the pointer: AppKit's global mouse position against where the character sits in its window.
    private func cursorGaze() -> (Double, Double) {
        guard let w = window else { return (0, 0) }
        let f = w.frame, half = Double(BuddyMetrics.characterSize / 2), pad = Double(BuddyMetrics.outerPadding)
        let cx = corner.isTrailing ? f.maxX - pad - half : f.minX + pad + half
        let cy = corner.isBottom ? f.minY + pad + half : f.maxY - pad - half
        let m = NSEvent.mouseLocation
        return (pixelClamp((m.x - cx) / 230, -1, 1), pixelClamp((cy - m.y) / 230, -1, 1))
    }

    /// The real mic level is not plumbed into the model yet, so listening uses simulated speech.
    private func updateVoice(_ dt: Double) {
        guard state == .listening else { level += (0 - level) * (1 - exp(-dt * 9)); return }
        let syl = pow(max(0, sin(t * 2 * .pi * 2.6 + pixelNoise(t * 1.3) * 2.6)), 1.4)
        let phrase = pixelClamp((pixelNoise(t * 0.55 + 3) + 0.35) * 1.6)
        let target = pixelClamp(syl * (0.25 + 0.75 * phrase) + pixelNoise(t * 23) * 0.05 + 0.05)
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
        let s = state, tt = t, e = te, asleep = s == .sleep, u = U, W = 16.0
        let ink = pixelColor(0x1D1147), white = Color.white
        let shade = cur.mixed(PixelRGB(r: 20, g: 0, b: 60), 0.2).color
        let hi = cur.mixed(PixelRGB(r: 255, g: 255, b: 255), 0.6).color
        let bodyColor = cur.color, led = pixelColor(pixelLED[s] ?? 0x22C55E)

        // Grid-snapped bounce / shake offsets.
        let oy = (y.x / u).rounded() * u, ox = (x.x / u).rounded() * u
        let squash = asleep || (allowMotion && y.x > -2 * kscale && abs(y.v) > 90 * kscale)
        let stretch = !squash && ((s == .wake && e < 0.35) || (allowMotion && y.x < -u * 3))
        let x0 = -W * u / 2 + ox, y0 = -8.8 * u, ground = y0 + 18 * u
        func mapR(_ r: Int) -> Int { r + (squash && r > 4 ? -1 : 0) + (stretch && r > 4 ? 1 : 0) }
        /// Body-space cell (follows squash/stretch).
        func px(_ c: Int, _ r: Int, _ col: Color) {
            ctx.fill(Path(CGRect(x: x0 + Double(c) * u, y: y0 + Double(mapR(r) + 4) * u + oy + (squash ? u : 0), width: u + 0.35, height: u + 0.35)), with: .color(col))
        }
        /// Extras-space cell (ignores squash/stretch).
        func ex(_ c: Int, _ r: Int, _ col: Color) {
            ctx.fill(Path(CGRect(x: x0 + Double(c) * u, y: y0 + Double(r + 4) * u + oy, width: u + 0.35, height: u + 0.35)), with: .color(col))
        }
        func pat(_ g: [String], _ c: Int, _ r: Int, _ col: Color) {
            for (j, row) in g.enumerated() { for (i, v) in row.enumerated() where v == "1" { ex(c + i, r + j, col) } }
        }

        /* ground shadow */
        let lift = max(0, -y.x / u), sw = max(6, 12 - lift)
        ctx.fill(Path(CGRect(x: x0 - ox + (W - sw) / 2 * u, y: ground - u * 0.3, width: sw * u, height: u * 0.8)), with: .color(.black.opacity(0.3)))

        /* body */
        for q in pixelCells {
            if squash && q.r == 4 { continue }
            let col: Color
            switch q.kind {
            case .outline: col = ink
            case .shade: col = shade
            case .highlight: col = hi
            case .body: col = bodyColor
            }
            px(q.c, q.r, col)
            if stretch && q.r == 4 { px(q.c, 5, col) }
        }
        for c in [3, 4, 5, 10, 11, 12] { px(c, 13, ink) }  // feet

        /* face */
        enum Eye { case open, wide, blink, closed, happy, cross }
        var eye = Eye.open
        if closed() { eye = .blink }
        if s == .listening || s == .needs { eye = .wide }
        if s == .sent || s == .finished { eye = .happy }
        if s == .error { eye = .cross }
        if asleep { eye = .closed }
        if s == .wake { eye = e < 0.5 ? .closed : e < 0.9 ? .blink : .open }
        let gx = gaze.x, gy = gaze.y
        for L in [4, 10] {
            switch eye {
            case .open:
                for j in 0..<3 { for i in 0..<2 { px(L + i + gx, 5 + j + gy, ink) } }
                px(L + gx, 5 + gy, white)
            case .wide:
                for j in 0..<4 { for i in 0..<2 { px(L + i + gx, 4 + j + gy, ink) } }
                px(L + gx, 4 + gy, white)
            case .blink: px(L, 6, ink); px(L + 1, 6, ink)
            case .closed: px(L, 7, ink); px(L + 1, 7, ink)
            case .happy: px(L - 1, 7, ink); px(L, 6, ink); px(L + 1, 6, ink); px(L + 2, 7, ink)
            case .cross: for (i, j) in [(0, 0), (2, 0), (1, 1), (0, 2), (2, 2)] { px(L - 1 + i, 5 + j, ink) }
            }
        }
        if s != .error {
            let blush = pixelColor(0xFF8FAB)
            for c in [2, 3, 12, 13] { px(c, 9, blush) }
        }
        let mouth: [(Int, Int)]
        switch s {
        case .listening, .needs: mouth = [(7, 9), (8, 9), (7, 10), (8, 10)]
        case .error: mouth = [(6, 10), (7, 9), (8, 9), (9, 10)]
        case .sleep: mouth = [(7, 10), (8, 10)]
        case .sent, .finished: mouth = [(6, 9), (7, 9), (8, 9), (9, 9), (7, 10), (8, 10)]
        default: mouth = [(6, 9), (7, 10), (8, 10), (9, 9)]
        }
        for (c, r) in mouth { px(c, r, ink) }

        /* antenna + LED: the LED pattern is the status readout */
        let lit: Bool
        switch s {
        case .idle: lit = tt.truncatingRemainder(dividingBy: 2.4) < 1.6
        case .meeting: lit = tt.truncatingRemainder(dividingBy: 1) < 0.5
        case .listening: lit = level > 0.12
        case .thinking: lit = Int(tt * 6) % 2 == 0
        case .needs: lit = tt.truncatingRemainder(dividingBy: 0.66) < 0.33
        case .error: lit = pixelHash(Double(Int(tt * 9))) > 0.3
        case .sleep: lit = false
        default: lit = true
        }
        let on = lit || (tt - flick < 0.3 && Int((tt - flick) * 20) % 2 == 0)
        for (c, r) in [(7, -2), (8, -2), (7, -1), (8, -1)] { px(c, r, ink) }
        if on {
            ctx.opacity = 0.28
            for (c, r) in [(6, -5), (7, -5), (8, -5), (9, -5), (6, -4), (9, -4), (6, -3), (9, -3), (7, -2), (8, -2)] { ex(c, r, led) }
            ctx.opacity = 1
        }
        for (c, r) in [(7, -4), (8, -4), (7, -3), (8, -3)] { ex(c, r, on ? led : pixelColor(0x4B3F8A)) }

        /* extras */
        if s == .listening {
            let n = 1 + Int(level * 3.4 + (tt * 3).truncatingRemainder(dividingBy: 1) * 0.6)
            for i in 0..<min(3, n) {
                ctx.opacity = 0.9 - Double(i) * 0.2
                for (a, b) in [(0, 0), (1, 1), (1, 2), (1, 3), (0, 4)] { ex(17 + i * 2 + a, 4 + b, bodyColor) }
            }
            ctx.opacity = 1
        }
        if s == .thinking {
            for i in 0..<3 {
                let up = Int(tt * 5) % 3 == i ? -1 : 0
                for (a, b) in [(0, 0), (1, 0), (0, 1), (1, 1)] { ex(17 + i * 2 + a, 1 + up + b, white) }
            }
        }
        if s == .needs { pat(pixelBang, 17, -2 + Int(tt * 2.5) % 2, pixelColor(0xFF3B4E)) }
        if s == .error {
            let d = (e * 2.2).truncatingRemainder(dividingBy: 1), drop = pixelColor(0x7DD3FC)
            ex(15, 5 + Int(d * 4), drop); ex(15, 6 + Int(d * 4), drop)
        }
        if asleep {
            for j in 0..<2 {
                let ph = ((e + Double(j) * 1.6).truncatingRemainder(dividingBy: 3.2)) / 3.2
                ctx.opacity = sin(.pi * ph)
                pat(pixelZ, 15 + j * 2 + Int(ph * 3), 2 - Int(ph * 6) - j, white)
            }
            ctx.opacity = 1
        }
        if s == .finished {
            let cols = [pixelColor(0xFDE047), white, pixelColor(0xFF8FAB)]
            for (c, r, d) in [(-3, 2, 0.0), (18, 0, 0.2), (-2, 9, 0.45), (19, 8, 0.7), (9, -7, 0.3)] {
                let q = (e - d) / 1.6
                if q > 0 && q < 1 && Int(tt * 8 + Double(c)) % 3 != 0 { pat(pixelPlus, c, r - Int(q * 3), cols[abs(c) % 3]) }
            }
        }
        let ps = tt - sendT
        if ps > 0 && ps < 0.9 {
            let en = pixelEaseOut(ps / 0.9), c = 14 + Int((en * 11).rounded()), r = -1 - Int((en * 9).rounded())
            ctx.opacity = ps > 0.7 ? (0.9 - ps) / 0.2 : 1
            // A little envelope flying off to the top right.
            for i in 0..<6 { for j in 0..<4 { ex(c + i, r + j, (i == 0 || i == 5 || j == 0 || j == 3) ? ink : white) } }
            for (a, b) in [(1, 1), (2, 2), (3, 2), (4, 1)] { ex(c + a, r + b, ink) }
            ctx.opacity = 1
        }
    }
}
