import AppKit

let destination = CommandLine.arguments[1]
let size = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
NSColor(calibratedRed: 0.055, green: 0.06, blue: 0.075, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 62, y: 62, width: 900, height: 900), xRadius: 205, yRadius: 205).fill()
for index in 0..<9 {
    let path = NSBezierPath(ovalIn: NSRect(x: 205 + index * 4, y: 300 - index * 12, width: 615 - index * 8, height: 420 + index * 24))
    let transform = AffineTransform(translationByX: 512, byY: 512)
    var rotation = transform
    rotation.rotate(byDegrees: CGFloat(index * 21))
    rotation.translate(x: -512, y: -512)
    path.transform(using: rotation)
    NSColor(calibratedRed: 0.55, green: 0.41, blue: 0.93, alpha: 0.45).setStroke()
    path.lineWidth = 4
    path.stroke()
}
let heights: [CGFloat] = [70, 150, 240, 330, 205, 120, 65]
NSColor(calibratedRed: 0.79, green: 0.97, blue: 0.43, alpha: 1).setFill()
for (index, height) in heights.enumerated() {
    NSBezierPath(roundedRect: NSRect(x: 310 + CGFloat(index) * 59, y: 512 - height / 2, width: 30, height: height), xRadius: 15, yRadius: 15).fill()
}
image.unlockFocus()
guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot render icon") }
// icns supports a PNG-compressed 1024px icon in the ic10 element.
func bigEndian(_ value: UInt32) -> Data { var number = value.bigEndian; return withUnsafeBytes(of: &number) { Data($0) } }
var output = Data("icns".utf8)
output += bigEndian(UInt32(16 + png.count))
output += Data("ic10".utf8)
output += bigEndian(UInt32(8 + png.count))
output += png
try output.write(to: URL(fileURLWithPath: destination))
