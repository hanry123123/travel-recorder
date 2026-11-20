import Foundation
import Photos
import PhotosUI
import UniformTypeIdentifiers
import UIKit

struct LibraryPhotoMetadata {
    let createdAt: Date?
    let modifiedAt: Date?
    let coordinate: Coordinate?
}

struct LibraryPhotoSnapshot {
    let authorization: PHAuthorizationStatus
    let authorizationUnchanged: Bool
    let assets: [String: LibraryPhotoMetadata]
    var canConfirmMissing: Bool { authorization == .authorized && authorizationUnchanged }
}

class PhotoLibraryService: NSObject, PHPhotoLibraryChangeObserver {
    var onChange: (() -> Void)?
    private var observing = false
    private let observationQueue = DispatchQueue(label: "travel.photo.observation")
    var authorization: PHAuthorizationStatus { PHPhotoLibrary.authorizationStatus(for: .readWrite) }
    func request(_ completion: @escaping () -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in DispatchQueue.main.async { self.observe(); completion() } }
    }
    func observe() {
        observationQueue.async { [weak self] in
            guard let self = self, !self.observing, self.authorization == .authorized || self.authorization == .limited else { return }
            PHPhotoLibrary.shared().register(self)
            self.observing = true
        }
    }
    deinit { if observing { PHPhotoLibrary.shared().unregisterChangeObserver(self) } }
    func photoLibraryDidChange(_ changeInstance: PHChange) { DispatchQueue.main.async { NotificationCenter.default.post(name: .travelPhotoLibraryChanged, object: nil); self.onChange?() } }
    /// Hidden photos remain in the library. Include them so hiding is never treated as deletion.
    func snapshot(identifiers: [String]) -> LibraryPhotoSnapshot {
        let before = authorization
        var assets: [String: LibraryPhotoMetadata] = [:]
        if before == .authorized || before == .limited {
            let options = PHFetchOptions(); options.includeHiddenAssets = true
            PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: options).enumerateObjects { asset, _, _ in
                assets[asset.localIdentifier] = LibraryPhotoMetadata(createdAt: asset.creationDate,
                    modifiedAt: asset.modificationDate,
                    coordinate: asset.location.map { Coordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) })
            }
        }
        return LibraryPhotoSnapshot(authorization: before, authorizationUnchanged: before == authorization, assets: assets)
    }
    func candidates(for trip: Trip, now: Date) -> [PHAsset] {
        guard authorization == .authorized || authorization == .limited else { return [] }
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d AND creationDate >= %@ AND creationDate <= %@", PHAssetMediaType.image.rawValue, trip.startedAt as NSDate, (trip.endedAt ?? now) as NSDate)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        var assets: [PHAsset] = []
        PHAsset.fetchAssets(with: options).enumerateObjects { asset, _, _ in
            if !asset.mediaSubtypes.contains(.photoScreenshot), !self.isSharePoster(asset) { assets.append(asset) }
        }
        return assets
    }
    // The system share sheet saves the JPEG without reporting its new Photos ID.
    // Inspect local originals on the scan queue only for poster-sized candidates.
    private func isSharePoster(_ asset: PHAsset) -> Bool {
        let size = SharePosterLayout.posterSize
        let scale = SharePosterLayout.exportScale
        guard asset.pixelWidth == Int(size.width * scale),
              asset.pixelHeight == Int(size.height * scale) else { return false }
        let options = PHImageRequestOptions()
        options.version = .original
        options.isSynchronous = true
        options.isNetworkAccessAllowed = false
        var marked = false
        PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
            if let data = data { marked = PhotoFileStore.isShareImage(data) }
        }
        return marked
    }
    func asset(_ identifier: String) -> PHAsset? {
        guard authorization == .authorized || authorization == .limited else { return nil }
        return PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject
    }
}

extension Notification.Name { static let travelPhotoLibraryChanged = Notification.Name("travel.photoLibraryChanged") }
