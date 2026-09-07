// 產生 App 圖示：藍紫漸層圓角方形 + 白色垃圾桶 + 三顆閃亮星星（「清得乾乾淨淨」的意象）
import AppKit

let size: CGFloat = 1024
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"

let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()

// 底板（留邊距，符合 macOS 圖示規範）
let inset: CGFloat = 70
let rect = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let plate = NSBezierPath(roundedRect: rect, xRadius: 196, yRadius: 196)

NSGraphicsContext.current?.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowBlurRadius = 36
shadow.shadowOffset = NSSize(width: 0, height: -16)
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.set()
NSColor(calibratedRed: 0.12, green: 0.32, blue: 0.75, alpha: 1).setFill()
plate.fill()
NSGraphicsContext.current?.restoreGraphicsState()

// 主漸層：靛藍 → 天藍
let grad = NSGradient(colors: [
    NSColor(calibratedRed: 0.36, green: 0.62, blue: 1.00, alpha: 1),
    NSColor(calibratedRed: 0.22, green: 0.42, blue: 0.95, alpha: 1),
    NSColor(calibratedRed: 0.20, green: 0.22, blue: 0.72, alpha: 1),
])!
grad.draw(in: plate, angle: -70)

// 左上柔光
let glow = NSGradient(starting: NSColor.white.withAlphaComponent(0.25),
                      ending: NSColor.white.withAlphaComponent(0))!
glow.draw(in: plate, relativeCenterPosition: NSPoint(x: -0.4, y: 0.6))

// 白色圖形：垃圾桶
NSGraphicsContext.current?.saveGraphicsState()
let gShadow = NSShadow()
gShadow.shadowBlurRadius = 20
gShadow.shadowOffset = NSSize(width: 0, height: -10)
gShadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
gShadow.set()
NSColor.white.setFill()
NSColor.white.setStroke()

let cx = size / 2 - 40
let baseY: CGFloat = 250
// 桶身（略呈梯形、圓角）
let body = NSBezierPath()
body.move(to: NSPoint(x: cx - 200, y: baseY + 420))
body.line(to: NSPoint(x: cx + 200, y: baseY + 420))
body.line(to: NSPoint(x: cx + 168, y: baseY + 40))
body.curve(to: NSPoint(x: cx + 128, y: baseY), controlPoint1: NSPoint(x: cx + 166, y: baseY + 14), controlPoint2: NSPoint(x: cx + 150, y: baseY))
body.line(to: NSPoint(x: cx - 128, y: baseY))
body.curve(to: NSPoint(x: cx - 168, y: baseY + 40), controlPoint1: NSPoint(x: cx - 150, y: baseY), controlPoint2: NSPoint(x: cx - 166, y: baseY + 14))
body.close()
body.fill()

// 桶身的三道直條（以底色畫出，看起來像鏤空）
NSGraphicsContext.current?.saveGraphicsState()
NSShadow().set()
NSColor(calibratedRed: 0.24, green: 0.40, blue: 0.90, alpha: 1).setFill()
for dx in [-90, 0, 90] as [CGFloat] {
    let slot = NSBezierPath(roundedRect: NSRect(x: cx + dx - 16, y: baseY + 70, width: 32, height: 290), xRadius: 16, yRadius: 16)
    slot.fill()
}
NSColor.white.setFill()
NSGraphicsContext.current?.restoreGraphicsState()

// 桶蓋
let lid = NSBezierPath(roundedRect: NSRect(x: cx - 240, y: baseY + 448, width: 480, height: 58), xRadius: 29, yRadius: 29)
lid.fill()
// 提把
let handle = NSBezierPath(roundedRect: NSRect(x: cx - 80, y: baseY + 492, width: 160, height: 70), xRadius: 30, yRadius: 30)
handle.lineWidth = 34
handle.stroke()

// 三顆閃亮的四角星（右上）
func sparkle(_ c: NSPoint, _ r: CGFloat) {
    let p = NSBezierPath()
    p.move(to: NSPoint(x: c.x, y: c.y + r))
    p.curve(to: NSPoint(x: c.x + r, y: c.y), controlPoint1: NSPoint(x: c.x + r * 0.12, y: c.y + r * 0.12), controlPoint2: NSPoint(x: c.x + r * 0.12, y: c.y + r * 0.12))
    p.curve(to: NSPoint(x: c.x, y: c.y - r), controlPoint1: NSPoint(x: c.x + r * 0.12, y: c.y - r * 0.12), controlPoint2: NSPoint(x: c.x + r * 0.12, y: c.y - r * 0.12))
    p.curve(to: NSPoint(x: c.x - r, y: c.y), controlPoint1: NSPoint(x: c.x - r * 0.12, y: c.y - r * 0.12), controlPoint2: NSPoint(x: c.x - r * 0.12, y: c.y - r * 0.12))
    p.curve(to: NSPoint(x: c.x, y: c.y + r), controlPoint1: NSPoint(x: c.x - r * 0.12, y: c.y + r * 0.12), controlPoint2: NSPoint(x: c.x - r * 0.12, y: c.y + r * 0.12))
    p.close()
    p.fill()
}
sparkle(NSPoint(x: 790, y: 790), 92)
sparkle(NSPoint(x: 690, y: 690), 46)
sparkle(NSPoint(x: 850, y: 640), 34)
NSGraphicsContext.current?.restoreGraphicsState()

img.unlockFocus()

guard let tiff = img.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fputs("無法產生 PNG\n", stderr)
    exit(1)
}
try! png.write(to: URL(fileURLWithPath: outPath))
print("圖示已輸出：\(outPath)")
