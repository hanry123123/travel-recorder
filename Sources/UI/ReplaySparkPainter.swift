import CoreGraphics

/// Actual iPhone drawing, also compiled into the native frame preview.
enum ReplaySparkPainter {
    static func draw(in context: CGContext, head: CGPoint, sparks: [ReplaySpark]) {
        context.saveGState()
        context.setLineCap(.round)
        for spark in sparks where spark.opacity > 0.01 {
            let heat = CGFloat(spark.heat), alpha = CGFloat(spark.opacity)
            let dx = spark.tip.x-spark.tail.x, dy = spark.tip.y-spark.tail.y
            let length = max(0.01, (dx*dx+dy*dy).squareRoot())
            let width = CGFloat(spark.width)*0.55
            // The streak narrows behind the bright moving tip, like an exposure trail.
            let shape = CGMutablePath()
            shape.move(to: spark.tail)
            shape.addLine(to: CGPoint(x: spark.tip.x-dy/length*width, y: spark.tip.y+dx/length*width))
            shape.addQuadCurve(to: CGPoint(x: spark.tip.x+dy/length*width, y: spark.tip.y-dx/length*width),
                              control: CGPoint(x: spark.tip.x+dx/length*width, y: spark.tip.y+dy/length*width))
            shape.closeSubpath()
            context.saveGState()
            context.setShadow(offset: .zero, blur: 3, color: CGColor(red: 1, green: 0.3, blue: 0.01, alpha: alpha*0.8))
            context.setFillColor(CGColor(red: 1, green: 0.42, blue: 0.025, alpha: alpha))
            context.addPath(shape); context.fillPath()
            context.setShadow(offset: .zero, blur: 0, color: nil)
            context.addPath(shape); context.clip()
            let colors = [CGColor(red: 1, green: 0.10, blue: 0.01, alpha: alpha*0.25),
                          CGColor(red: 1, green: 0.18+0.82*heat, blue: 0.025+0.84*heat*heat, alpha: alpha)] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                context.drawLinearGradient(gradient, start: spark.tail, end: spark.tip, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            }
            context.restoreGState()
        }
        // The tracking point stays red and distinct from the yellow-white sparks.
        context.setFillColor(CGColor(red: 0.96, green: 0.045, blue: 0.08, alpha: 1))
        context.fillEllipse(in: CGRect(x: head.x-4.5, y: head.y-4.5, width: 9, height: 9))
        context.restoreGState()
    }
}
