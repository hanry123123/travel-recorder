import Foundation

enum MapAlignment: String { case automatic, mainland, original }

/// Storage/GPS stays WGS-84; conversion occurs only at the map boundary.
enum MapCoordinates {
    static func usesGCJ(_ coordinate: Coordinate, mode: MapAlignment) -> Bool {
        guard coordinate.isValid, mode != .original else { return false }
        if mode == .mainland {
            return (72.004...137.8347).contains(coordinate.longitude) && (0.8293...55.8271).contains(coordinate.latitude)
        }
        return MainlandRegion.contains(coordinate)
    }

    static func display(_ coordinate: Coordinate, mode: MapAlignment) -> Coordinate {
        guard coordinate.datum != .legacyMap, usesGCJ(coordinate, mode: mode) else { return coordinate }
        return offset(coordinate)
    }

    static func storedSelection(_ displayed: Coordinate, mode: MapAlignment) -> Coordinate {
        var result = displayed
        if usesGCJ(displayed, mode: mode) {
            // Bounded inverse, with the same forward formula. Keep the decision
            // fixed throughout iteration to avoid oscillation on mask edges.
            for _ in 0..<10 {
                let projected = offset(result)
                let dy = projected.latitude - displayed.latitude
                let dx = projected.longitude - displayed.longitude
                result.latitude -= dy
                result.longitude -= dx
                if abs(dx) < 1e-9 && abs(dy) < 1e-9 { break }
            }
        }
        result.datum = .wgs84
        return result
    }

    // GCJ approximation adapted from MIT-licensed gcoord; see THIRD-PARTY.md.
    private static func offset(_ coordinate: Coordinate) -> Coordinate {
        let x = coordinate.longitude - 105
        let y = coordinate.latitude - 35
        let pi = Double.pi
        let common = (20 * sin(6 * x * pi) + 20 * sin(2 * x * pi)) * 2 / 3
        var north = -100 + 2*x + 3*y + 0.2*y*y + 0.1*x*y + 0.2*sqrt(abs(x))
        north += common + (20*sin(y*pi) + 40*sin(y*pi/3))*2/3
        north += (160*sin(y*pi/12) + 320*sin(y*pi/30))*2/3
        var east = 300 + x + 2*y + 0.1*x*x + 0.1*x*y + 0.1*sqrt(abs(x))
        east += common + (20*sin(x*pi) + 40*sin(x*pi/3))*2/3
        east += (150*sin(x*pi/12) + 300*sin(x*pi/30))*2/3
        let eccentricity = 0.006693421622965823
        let latitudeRadians = coordinate.latitude*pi/180
        let magic = 1 - eccentricity*pow(sin(latitudeRadians), 2)
        let rootMagic = sqrt(magic)
        let latDelta = north*180 / ((6378245*(1-eccentricity)/(magic*rootMagic))*pi)
        let lonDelta = east*180 / ((6378245/rootMagic)*cos(latitudeRadians)*pi)
        return Coordinate(latitude: coordinate.latitude+latDelta, longitude: coordinate.longitude+lonDelta)
    }
}
