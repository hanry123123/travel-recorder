import Foundation
import UIKit
import Photos

/// In-memory requests only. PhotoKit manages the system library/iCloud cache.
final class PhotoImageRequest {
    private let lock = NSLock()
    private var cancelled = false
    private var photoID: PHImageRequestID?
    func install(_ id: PHImageRequestID) {
        lock.lock(); photoID = id; let stop = cancelled; lock.unlock()
        if stop { PHImageManager.default().cancelImageRequest(id) }
    }
    func cancel() {
        lock.lock(); cancelled = true; let id = photoID; lock.unlock()
        if let id = id { PHImageManager.default().cancelImageRequest(id) }
    }
    func deliver(_ image: UIImage?, completion: @escaping (UIImage?) -> Void) {
        DispatchQueue.main.async {
            self.lock.lock(); let stop = self.cancelled; self.lock.unlock()
            if !stop { completion(image) }
        }
    }
}
enum PhotoImageLoader {
    static func assetID(_ url: URL) -> String? {
        guard url.scheme == "travel-photo", let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.queryItems?.first(where: { $0.name == "unavailable" })?.value != "1",
              let id = components.queryItems?.first(where: { $0.name == "id" })?.value, !id.isEmpty else { return nil }
        return id
    }
    @discardableResult static func load(_ url: URL, edge: CGFloat = 640, completion: @escaping (UIImage?) -> Void) -> PhotoImageRequest {
        let request = PhotoImageRequest()
        DispatchQueue.global(qos: .userInitiated).async {
            if url.isFileURL { request.deliver(UIImage(contentsOfFile: url.path), completion: completion); return }
            guard let id = assetID(url), let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else {
                request.deliver(nil, completion: completion); return
            }
            let options = PHImageRequestOptions()
            options.version = .current; options.deliveryMode = .opportunistic
            options.resizeMode = .fast; options.isNetworkAccessAllowed = true
            let idValue = PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: edge, height: edge), contentMode: .aspectFit, options: options) { image, info in
                if (info?[PHImageCancelledKey] as? Bool) == true { return }
                if image != nil || (info?[PHImageResultIsDegradedKey] as? Bool) != true { request.deliver(image, completion: completion) }
            }
            request.install(idValue)
        }
        return request
    }
    /// Called only by the share rendering worker. No originals/thumbnails are written.
    static func shareImage(_ url: URL) -> UIImage? {
        if url.isFileURL { return UIImage(contentsOfFile: url.path) }
        guard !Thread.isMainThread, let id = assetID(url), let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return nil }
        let options = PHImageRequestOptions()
        options.version = .current; options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact; options.isNetworkAccessAllowed = true
        let semaphore = DispatchSemaphore(value: 0); let lock = NSLock()
        var result: UIImage?; var completed = false
        let requestID = PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 1600, height: 1600), contentMode: .aspectFit, options: options) { image, info in
            if (info?[PHImageResultIsDegradedKey] as? Bool) == true { return }
            lock.lock(); if !completed { result = image; completed = true; semaphore.signal() }; lock.unlock()
        }
        if semaphore.wait(timeout: .now()+45) == .timedOut {
            lock.lock(); completed = true; lock.unlock()
            PHImageManager.default().cancelImageRequest(requestID)
            return nil
        }
        lock.lock(); defer { lock.unlock() }; return result
    }
}
