// 绘制「时迹」应用图标：白色圆角底 + 彩色时间分布环 + 靛蓝表盘与白色指针
// 用法：swiftc Scripts/make_icon.swift -o build/make_icon && build/make_icon Resources/AppIcon-1024.png
import AppKit

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
let space = CGColorSpaceCreateDeviceRGB()
let center = CGPoint(x: 512, y: 512)
let gradientOpts: CGGradientDrawingOptions = [.drawsBeforeStartLocation, .drawsAfterEndLocation]

// 1. 白色圆角底（macOS 图标网格：824×824，四周留 100）
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 26, color: rgb(0x000000, 0.28))
ctx.addPath(tilePath)
ctx.setFillColor(rgb(0xFFFFFF))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(tilePath)
ctx.clip()
let bg = CGGradient(colorsSpace: space, colors: [rgb(0xFFFFFF), rgb(0xF1F2F7)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: gradientOpts)
ctx.restoreGState()

// 细描边，让白底在白色背景（访达、浅色模式）里也有轮廓
ctx.addPath(tilePath)
ctx.setStrokeColor(rgb(0x000000, 0.07))
ctx.setLineWidth(2)
ctx.strokePath()

// 2. 时间分布环（从 12 点顺时针）
let ringRadius: CGFloat = 262
let ringWidth: CGFloat = 92
ctx.setLineWidth(ringWidth)
ctx.setLineCap(.butt)
ctx.addArc(center: center, radius: ringRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
ctx.setStrokeColor(rgb(0xE6E8F1))
ctx.strokePath()

let segments: [(CGFloat, UInt32)] = [
    (0.30, 0x4C8BF5), // 蓝
    (0.20, 0x8E5CF7), // 紫
    (0.15, 0xF59E0B), // 橙
    (0.13, 0x10B981), // 绿
    (0.10, 0xEC4899), // 粉
]
let gap: CGFloat = 2.6 * .pi / 180
var cursor: CGFloat = .pi / 2
for (frac, color) in segments {
    let sweep = frac * 2 * .pi
    ctx.addArc(center: center, radius: ringRadius, startAngle: cursor - gap / 2,
               endAngle: cursor - sweep + gap / 2, clockwise: true)
    ctx.setStrokeColor(rgb(color))
    ctx.strokePath()
    cursor -= sweep
}

// 3. 靛蓝表盘
let faceR: CGFloat = 196
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: rgb(0x1F1B5E, 0.35))
ctx.addEllipse(in: CGRect(x: center.x - faceR, y: center.y - faceR, width: faceR * 2, height: faceR * 2))
ctx.setFillColor(rgb(0x3A2FA8))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addEllipse(in: CGRect(x: center.x - faceR, y: center.y - faceR, width: faceR * 2, height: faceR * 2))
ctx.clip()
let face = CGGradient(colorsSpace: space, colors: [rgb(0x6474FF), rgb(0x3A2FA8), rgb(0x241E70)] as CFArray,
                      locations: [0, 0.55, 1])!
ctx.drawLinearGradient(face, start: CGPoint(x: center.x - 120, y: center.y + 190),
                       end: CGPoint(x: center.x + 120, y: center.y - 190), options: gradientOpts)
ctx.restoreGState()

// 4. 刻度（12/3/6/9）
ctx.setLineCap(.round)
ctx.setLineWidth(14)
ctx.setStrokeColor(rgb(0xFFFFFF, 0.55))
for i in 0..<4 {
    let a = CGFloat(i) * .pi / 2
    let r1: CGFloat = 146, r2: CGFloat = 166
    ctx.move(to: CGPoint(x: center.x + cos(a) * r1, y: center.y + sin(a) * r1))
    ctx.addLine(to: CGPoint(x: center.x + cos(a) * r2, y: center.y + sin(a) * r2))
    ctx.strokePath()
}

// 5. 白色指针（10:10）
func hand(clockAngleDeg: CGFloat, length: CGFloat, width: CGFloat) {
    let a = (90 - clockAngleDeg) * .pi / 180
    ctx.setLineCap(.round)
    ctx.setLineWidth(width)
    ctx.setStrokeColor(rgb(0xFFFFFF))
    ctx.move(to: center)
    ctx.addLine(to: CGPoint(x: center.x + cos(a) * length, y: center.y + sin(a) * length))
    ctx.strokePath()
}
hand(clockAngleDeg: 305, length: 92, width: 28)
hand(clockAngleDeg: 60, length: 128, width: 20)

ctx.addEllipse(in: CGRect(x: center.x - 28, y: center.y - 28, width: 56, height: 56))
ctx.setFillColor(rgb(0xFFFFFF))
ctx.fillPath()
ctx.addEllipse(in: CGRect(x: center.x - 13, y: center.y - 13, width: 26, height: 26))
ctx.setFillColor(rgb(0xF59E0B))
ctx.fillPath()

NSGraphicsContext.restoreGraphicsState()
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png")
try! rep.representation(using: .png, properties: [:])!.write(to: out)
print("wrote \(out.path)")
