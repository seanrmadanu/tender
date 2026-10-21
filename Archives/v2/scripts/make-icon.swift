import AppKit
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
NSColor(red: 0.08, green: 0.23, blue: 0.18, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: 1024, height: 1024).fill()
NSColor(red: 0.80, green: 0.84, blue: 0.67, alpha: 0.4).setStroke()
for i in 0..<55 {
    let n = CGFloat(i) * 13
    let p = NSBezierPath()
    p.move(to: NSPoint(x: -100 + n, y: 1100))
    p.curve(to: NSPoint(x: 1200, y: -100 + n), controlPoint1: NSPoint(x: 1000 + n, y: 900), controlPoint2: NSPoint(x: -200 + n, y: 200))
    p.lineWidth = 2; p.stroke()
}
NSColor(red: 0.08, green: 0.23, blue: 0.18, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: 222, y: 222, width: 580, height: 580)).fill()
NSColor(red: 0.94, green: 0.93, blue: 0.85, alpha: 1).setStroke()
let ring = NSBezierPath(ovalIn: NSRect(x: 237, y: 237, width: 550, height: 550)); ring.lineWidth = 3; ring.stroke()
let text = "t" as NSString
text.draw(at: NSPoint(x: 370, y: 225), withAttributes: [.font: NSFont(name: "Baskerville", size: 620)!, .foregroundColor: NSColor(red: 0.96, green: 0.95, blue: 0.88, alpha: 1)])
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
