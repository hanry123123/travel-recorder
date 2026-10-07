import Foundation
import CoreGraphics
import ImageIO

// This draws the production particle model/painter over a synthetic route, not a device screenshot.
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let scale: CGFloat = 2
func head(_ t: Double) -> CGPoint { CGPoint(x: 50+t*36, y: 80+sin(t*1.1)*22) }
func frame(_ time: Double) -> CGImage {
    let context = CGContext(data: nil, width: 720, height: 960, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
    context.scaleBy(x: scale, y: scale)
    context.translateBy(x: 0, y: 480); context.scaleBy(x: 1, y: -1)
    for row in 0..<3 {
        context.saveGState()
        context.translateBy(x: 0, y: CGFloat(row*160))
        let dark = row == 1
        context.setFillColor(CGColor(gray: dark ? 0.10 : 0.96, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 360, height: 160))
        context.setStrokeColor(CGColor(red: 0.12, green: 0.49, blue: 0.95, alpha: 1))
        context.setLineWidth(4); context.setLineCap(.round)
        for index in 0...210 {
            let p = head(Double(index)/30)
            if index == 0 { context.move(to: p) } else { context.addLine(to: p) }
        }
        context.strokePath()
        let sparks = ReplaySparks.frame(at: time, reducedMotion: row == 2) { (head($0), 0) }
        ReplaySparkPainter.draw(in: context, head: head(time), sparks: sparks)
        context.restoreGState()
    }
    return context.makeImage()!
}
let png = CGImageDestinationCreateWithURL(output.appendingPathComponent("sparks-preview.png") as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(png, frame(2.15), nil)
precondition(CGImageDestinationFinalize(png))
let gif = CGImageDestinationCreateWithURL(output.appendingPathComponent("sparks-preview.gif") as CFURL, "com.compuserve.gif" as CFString, 90, nil)!
CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
for index in 0..<90 {
    CGImageDestinationAddImage(gif, frame(Double(index)/30), [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0/30]] as CFDictionary)
}
precondition(CGImageDestinationFinalize(gif))
// Inspect production paint pixels: a red center and no former 17-point halo.
let ctx = CGContext(data: nil, width: 80, height: 80, bitsPerComponent: 8, bytesPerRow: 320,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 80, height: 80))
ReplaySparkPainter.draw(in: ctx, head: CGPoint(x: 40, y: 40), sparks: [])
let data = ctx.data!.assumingMemoryBound(to: UInt8.self)
let center = 40*320+40*4, outside = 40*320+54*4
print("center RGB", data[center], data[center+1], data[center+2])
precondition(data[center] > 200 && data[center+1] < 100 && data[center+2] < 100)
precondition(data[outside] == 255 && data[outside+1] == 255 && data[outside+2] == 255)
print("PAINT PASS: red center; no halo; 90 frames from production spark math and painter. Synthetic route, not iPhone UI.")
