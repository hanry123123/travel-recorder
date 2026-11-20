import UIKit
import CoreImage

/// Branding is drawn only into exported still images, outside the user's content.
/// The icon uses the same route geometry and blue gradient as generate_project.py.
enum ShareBranding {
    static let invitationURL = "https://testflight.apple.com/join/AFyPg72U"
    static let footerHeight: CGFloat = 160

    // Keep four quiet modules on every side; never place the logo inside the code.
    static let qrImage: UIImage? = {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(invitationURL.data(using: .utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let code = filter.outputImage else { return nil }
        let extent = code.extent.insetBy(dx: -4, dy: -4)
        let white = CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: extent)
        guard let image = CIContext(options: [.useSoftwareRenderer: false])
            .createCGImage(code.composited(over: white), from: extent) else { return nil }
        return UIImage(cgImage: image, scale: 1, orientation: .up)
    }()

    /// Public within the module so the fixture can inspect the exact production QR.
    static func draw(in frame: CGRect, context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        let card = CGRect(x: max(frame.minX, frame.maxX-470), y: frame.minY,
                          width: min(470, frame.width), height: frame.height)
        UIColor.white.setFill()
        UIBezierPath(roundedRect: card, cornerRadius: 15).fill()
        let qrBounds = CGRect(x: card.maxX-148, y: card.midY-68, width: 136, height: 136)
        if let qr = qrImage, let cg = qr.cgImage {
            // Integer device pixels per module avoid blur at export and preview scales.
            let deviceScale = max(0.01, hypot(context.ctm.a, context.ctm.b))
            let pixelsPerModule = max(1, floor(qrBounds.width*deviceScale/CGFloat(cg.width)))
            let side = CGFloat(cg.width)*pixelsPerModule/deviceScale
            let rect = CGRect(x: (qrBounds.midX-side/2)*deviceScale,
                              y: (qrBounds.midY-side/2)*deviceScale,
                              width: side*deviceScale, height: side*deviceScale).integral
            let aligned = CGRect(x: rect.minX/deviceScale, y: rect.minY/deviceScale,
                                 width: side, height: side)
            context.interpolationQuality = .none
            qr.draw(in: aligned)
        }
        let logo = CGRect(x: card.minX+18, y: card.midY-24, width: 48, height: 48)
        drawLogo(in: logo, context: context)
        let textX = logo.maxX+12
        let textWidth = max(0, qrBounds.minX-textX-8)
        drawText("旅迹", in: CGRect(x: textX, y: card.midY-36, width: textWidth, height: 32),
                 font: .boldSystemFont(ofSize: 25), color: .black)
        let slogan = AppLanguage.english ? "Keep the journeys you take" : "走过的路，留成回忆"
        let invite = AppLanguage.english ? "Scan to try on TestFlight" : "扫码通过 TestFlight 体验"
        drawText(slogan, in: CGRect(x: textX, y: card.midY+1, width: textWidth, height: 24),
                 font: .systemFont(ofSize: 12), color: UIColor(white: 0.4, alpha: 1))
        drawText(invite, in: CGRect(x: textX, y: card.midY+24, width: textWidth, height: 30),
                 font: .systemFont(ofSize: 12), color: UIColor(white: 0.4, alpha: 1))
    }

    private static func drawText(_ value: String, in rect: CGRect, font: UIFont, color: UIColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        (value as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading],
                                attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph], context: nil)
    }

    static func drawLogo(in rect: CGRect, context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        UIBezierPath(roundedRect: rect, cornerRadius: rect.width*0.22).addClip()
        let colors = [UIColor(red: 15/255, green: 125/255, blue: 245/255, alpha: 1).cgColor,
                      UIColor(red: 27/255, green: 93/255, blue: 227/255, alpha: 1).cgColor]
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: rect.minX, y: rect.minY),
                                       end: CGPoint(x: rect.minX, y: rect.maxY), options: [])
        }
        let route: [CGPoint] = [CGPoint(x: 0.28, y: 0.73), CGPoint(x: 0.25, y: 0.64),
                                CGPoint(x: 0.32, y: 0.52), CGPoint(x: 0.49, y: 0.51),
                                CGPoint(x: 0.64, y: 0.55), CGPoint(x: 0.72, y: 0.45),
                                CGPoint(x: 0.67, y: 0.30)]
            .map { CGPoint(x: rect.minX+$0.x*rect.width, y: rect.minY+$0.y*rect.height) }
        context.setStrokeColor(UIColor.white.cgColor)
        context.setFillColor(UIColor.white.cgColor)
        context.setLineWidth(rect.width*0.068)
        context.setLineCap(.round); context.setLineJoin(.round)
        context.move(to: route[0])
        for point in route.dropFirst() { context.addLine(to: point) }
        context.strokePath()
        let radius = rect.width*0.066
        for point in [route[0], route[route.count-1]] {
            context.fillEllipse(in: CGRect(x: point.x-radius, y: point.y-radius, width: radius*2, height: radius*2))
        }
    }
}
