// Renders Resources/AppIcon.icns: the Dumpcito jelly on a dark squircle.
// Usage: swift scripts/make-icon.swift
import AppKit
import CoreGraphics

let S: CGFloat = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
func col(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [CGFloat((hex >> 16) & 255) / 255, CGFloat((hex >> 8) & 255) / 255, CGFloat(hex & 255) / 255, a])!
}
let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

// macOS icon grid: 824pt squircle centred in 1024.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let squircle = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

// Soft drop shadow under the tile
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: col(0x000000, 0.45))
ctx.addPath(squircle); ctx.setFillColor(col(0x15122B)); ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(squircle); ctx.clip()
// Background: deep indigo to near-black
let bg = CGGradient(colorsSpace: cs, colors: [col(0x2A1F5C), col(0x0E0B1F)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 300, y: 924), end: CGPoint(x: 700, y: 100), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
// Colour glows behind the jelly
func glow(_ c: CGPoint, _ r: CGFloat, _ hex: UInt32, _ a: CGFloat) {
    let g = CGGradient(colorsSpace: cs, colors: [col(hex, a), col(hex, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [])
}
glow(CGPoint(x: 330, y: 700), 420, 0x7C5CFF, 0.55)
glow(CGPoint(x: 720, y: 360), 380, 0x2EE6D6, 0.35)

// Jelly body: slightly squashed blob, wobbly outline
let cx: CGFloat = 512, cy: CGFloat = 500
let body = CGMutablePath()
let pts = 120
for i in 0...pts {
    let t = CGFloat(i) / CGFloat(pts) * 2 * .pi
    let wob = 1 + 0.035 * sin(3 * t + 0.6) + 0.025 * sin(5 * t + 1.9)
    var rx = 300 * wob, ry = 262 * wob
    let low = max(0, -sin(t))                         // smooth: flatter, wider bottom
    rx *= 1 + 0.06 * low; ry *= 1 - 0.1 * low
    let p = CGPoint(x: cx + rx * cos(t), y: cy + ry * sin(t))
    i == 0 ? body.move(to: p) : body.addLine(to: p)
}
body.closeSubpath()

// Under-glow
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 90, color: col(0xFF5CA8, 0.7))
ctx.addPath(body); ctx.setFillColor(col(0xFF5CA8)); ctx.fillPath()
ctx.restoreGState()

// Body fill: violet to pink to teal
ctx.saveGState()
ctx.addPath(body); ctx.clip()
let fill = CGGradient(colorsSpace: cs, colors: [col(0x9B7BFF), col(0xFF5CA8), col(0x2EE6D6)] as CFArray, locations: [0, 0.55, 1])!
ctx.drawLinearGradient(fill, start: CGPoint(x: 260, y: 780), end: CGPoint(x: 760, y: 220), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
// Inner volume: darker rim, light centre
let vol = CGGradient(colorsSpace: cs, colors: [col(0xFFFFFF, 0.22), col(0xFFFFFF, 0), col(0x1A0B4A, 0.28)] as CFArray, locations: [0, 0.55, 1])!
ctx.drawRadialGradient(vol, startCenter: CGPoint(x: 440, y: 620), startRadius: 0, endCenter: CGPoint(x: cx, y: cy), endRadius: 330, options: [.drawsAfterEndLocation])
ctx.restoreGState()

// Specular highlight
ctx.saveGState()
ctx.translateBy(x: 372, y: 690); ctx.rotate(by: 0.5)
let hl = CGPath(ellipseIn: CGRect(x: -95, y: -42, width: 190, height: 84), transform: nil)
ctx.addPath(hl); ctx.setFillColor(col(0xFFFFFF, 0.55)); ctx.fillPath()
ctx.restoreGState()
let dot = CGRect(x: 468, y: 722, width: 34, height: 34)
ctx.setFillColor(col(0xFFFFFF, 0.5)); ctx.fillEllipse(in: dot)

// Eyes
func eye(_ x: CGFloat) {
    let r = CGRect(x: x - 40, y: 462, width: 80, height: 128)
    ctx.setFillColor(col(0x140B33)); ctx.addPath(CGPath(roundedRect: r, cornerWidth: 40, cornerHeight: 40, transform: nil)); ctx.fillPath()
    ctx.setFillColor(col(0xFFFFFF, 0.95)); ctx.fillEllipse(in: CGRect(x: x - 20, y: 538, width: 30, height: 30))
}
eye(418); eye(606)
// Little smile
let smile = CGMutablePath()
smile.move(to: CGPoint(x: 462, y: 418))
smile.addQuadCurve(to: CGPoint(x: 562, y: 418), control: CGPoint(x: 512, y: 368))
ctx.setStrokeColor(col(0x140B33)); ctx.setLineWidth(18); ctx.setLineCap(.round); ctx.addPath(smile); ctx.strokePath()

// Alert sparkle (it taps you when it needs you)
func star(_ c: CGPoint, _ r: CGFloat, _ a: CGFloat) {
    let p = CGMutablePath()
    for i in 0..<8 {
        let ang = CGFloat(i) * .pi / 4 - .pi / 2, rad = i % 2 == 0 ? r : r * 0.3
        let pt = CGPoint(x: c.x + rad * cos(ang), y: c.y + rad * sin(ang))
        i == 0 ? p.move(to: pt) : p.addLine(to: pt)
    }
    p.closeSubpath(); ctx.addPath(p); ctx.setFillColor(col(0xFFD166, a)); ctx.fillPath()
}
star(CGPoint(x: 772, y: 770), 64, 1)
star(CGPoint(x: 232, y: 262), 30, 0.85)
ctx.restoreGState()

// Hairline rim
ctx.addPath(squircle); ctx.setStrokeColor(col(0xFFFFFF, 0.10)); ctx.setLineWidth(3); ctx.strokePath()

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
let png = rep.representation(using: .png, properties: [:])!
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/icon-1024.png"
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
