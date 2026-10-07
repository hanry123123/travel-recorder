import Foundation
import ImageIO
import CoreGraphics

struct PreparedPhoto {
    let imageFile: String
    let thumbnailFile: String
    let coordinate: Coordinate?
    let capturedAt: Date?
}

final class PhotoFileStore {
    let directory: URL
    init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: directory.path)
        #endif
    }
    func url(_ name: String) -> URL { directory.appendingPathComponent(URL(fileURLWithPath: name).lastPathComponent) }
    func prepare(data: Data) throws -> PreparedPhoto {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { throw TripError.storage("无法读取这张照片") }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] ?? [:]
        let image = try resized(source, edge: 2560)
        let thumbnail = try resized(source, edge: 320)
        let key = UUID().uuidString
        let fullName = key + ".jpg"
        let thumbName = key + "-thumb.jpg"
        do {
            try jpeg(image).write(to: url(fullName), options: writeOptions)
            try jpeg(thumbnail).write(to: url(thumbName), options: writeOptions)
        } catch {
            remove(fullName); remove(thumbName)
            throw error
        }
        return PreparedPhoto(imageFile: fullName, thumbnailFile: thumbName, coordinate: Self.coordinate(in: properties), capturedAt: Self.captureDate(in: properties))
    }
    private var writeOptions: Data.WritingOptions {
        #if os(iOS)
        return [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        #else
        return .atomic
        #endif
    }
    private func resized(_ source: CGImageSource, edge: Int) throws -> CGImage {
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: edge, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceShouldCacheImmediately: true]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw TripError.storage("照片解码失败") }
        return image
    }
    private func jpeg(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else { throw TripError.storage("照片编码失败") }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw TripError.storage("照片编码失败") }
        return data as Data
    }
    func remove(_ file: String) { try? FileManager.default.removeItem(at: url(file)) }
    static func coordinate(in properties: [String: Any]) -> Coordinate? {
        guard let gps = properties[kCGImagePropertyGPSDictionary as String] as? [String: Any],
              let latitude = gps[kCGImagePropertyGPSLatitude as String] as? Double,
              let longitude = gps[kCGImagePropertyGPSLongitude as String] as? Double,
              let latRef = gps[kCGImagePropertyGPSLatitudeRef as String] as? String,
              let lonRef = gps[kCGImagePropertyGPSLongitudeRef as String] as? String,
              ["N", "S"].contains(latRef.uppercased()), ["E", "W"].contains(lonRef.uppercased()) else { return nil }
        let coordinate = Coordinate(latitude: latitude * (latRef.uppercased() == "S" ? -1 : 1), longitude: longitude * (lonRef.uppercased() == "W" ? -1 : 1))
        return coordinate.isValid ? coordinate : nil
    }
    static func captureDate(in properties: [String: Any]) -> Date? {
        guard let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any], let string = exif[kCGImagePropertyExifDateTimeOriginal as String] as? String else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        if let offset = exif["OffsetTimeOriginal"] as? String {
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ssXXXXX"
            return formatter.date(from: string + offset)
        }
        // Missing time zone is interpreted using the device's local time; PhotoKit date takes priority.
        return formatter.date(from: string)
    }
}
