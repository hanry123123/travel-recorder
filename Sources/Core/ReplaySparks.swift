import Foundation
import CoreGraphics

struct ReplaySpark: Equatable {
    let tip: CGPoint
    let tail: CGPoint
    let opacity: Double
    let width: Double
    let heat: Double
}

/// Ballistic embers driven only by replay time, including when scrubbing backwards.
enum ReplaySparks {
    private static func random(_ seed: Double) -> Double {
        let value = sin(seed*12.9898+78.233)*43758.5453
        return value-floor(value)
    }
    static func frame(at time: Double, emissionEnd: Double = .infinity, reducedMotion: Bool = false,
                      locate: (Double) -> (point: CGPoint, section: Int)?) -> [ReplaySpark] {
        guard time.isFinite, time >= 0, let head = locate(time) else { return [] }
        let rate = reducedMotion ? 12.0 : 48.0
        let maxLife = reducedMotion ? 0.5 : 1.05
        let first = max(0, ceil((time-maxLife)*rate))
        let last = floor(min(time, emissionEnd)*rate)
        guard last >= first else { return [] }
        return (0...Int(last-first)).compactMap { offset in
            let serial = first+Double(offset), born = serial/rate, age = time-born
            let variation = random(serial), spread = random(serial+971)
            let life = reducedMotion ? 0.30+variation*0.20 : 0.45+variation*0.60
            guard age >= 0, age < life, let origin = locate(born), origin.section == head.section else { return nil }
            var direction = CGPoint.zero
            if let previous = locate(max(0, born-0.04)), previous.section == origin.section {
                let dx = origin.point.x-previous.point.x, dy = origin.point.y-previous.point.y
                let length = hypot(dx, dy)
                if length > 0.001 { direction = CGPoint(x: dx/length, y: dy/length) }
            }
            // Mostly cast backwards, with irregular sideways sparks; never a regular ring.
            let angle = direction == .zero || spread > 0.72 ? spread*2*Double.pi :
                atan2(-Double(direction.y), -Double(direction.x))+(spread/0.72-0.5)*2.8
            let speed = (reducedMotion ? 18.0 : 42.0)+random(serial+51)*(reducedMotion ? 20 : 90)
            let vx = cos(angle)*speed+Double(direction.x)*12
            let vy = sin(angle)*speed+Double(direction.y)*12
            let drag = 2.2, gravity = reducedMotion ? 18.0 : 110.0
            func position(_ age: Double) -> CGPoint {
                let travel = (1-exp(-drag*age))/drag
                return CGPoint(x: Double(origin.point.x)+cos(angle)*4+vx*travel,
                               y: Double(origin.point.y)+sin(angle)*4+vy*travel+0.5*gravity*age*age)
            }
            let exposure = reducedMotion ? 0.04 : 0.045+random(serial+127)*0.05
            let heat = pow(1-age/life, 0.6)
            return ReplaySpark(tip: position(age), tail: position(max(0, age-exposure)),
                               opacity: min(1, age/0.02)*pow(1-age/life, 0.55),
                               width: 0.75+random(serial+307)*0.85, heat: heat)
        }
    }
}
