import Foundation
import Photos
import PhotosUI
import UniformTypeIdentifiers

struct ImportedPhotoInput {
    var data: Data
    var assetID: String?
    var date: Date?
    var coordinate: Coordinate?
}
final class PhotoLibraryService: NSObject, PHPhotoLibraryChangeObserver {
    var onChange: (() -> Void)?
    private var observing = false
    var authorization: PHAuthorizationStatus { PHPhotoLibrary.authorizationStatus(for: .readWrite) }
    func request(_ completion: @escaping () -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in DispatchQueue.main.async { self.observe(); completion() } }
    }
    func observe() {
        guard !observing, authorization == .authorized || authorization == .limited else { return }
        PHPhotoLibrary.shared().register(self)
        observing = true
    }
    deinit { if observing { PHPhotoLibrary.shared().unregisterChangeObserver(self) } }
    func photoLibraryDidChange(_ changeInstance: PHChange) { DispatchQueue.main.async { self.onChange?() } }
    func candidates(for trip: Trip, now: Date) -> [PHAsset] {
        guard authorization == .authorized || authorization == .limited else { return [] }
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d AND creationDate >= %@ AND creationDate <= %@", PHAssetMediaType.image.rawValue, trip.startedAt as NSDate, (trip.endedAt ?? now) as NSDate)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        var assets: [PHAsset] = []
        PHAsset.fetchAssets(with: options).enumerateObjects { asset, _, _ in
            if !asset.mediaSubtypes.contains(.photoScreenshot) { assets.append(asset) }
        }
        return assets
    }
    func asset(_ identifier: String) -> PHAsset? {
        guard authorization == .authorized || authorization == .limited else { return nil }
        return PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject
    }
    func read(_ asset: PHAsset, completion: @escaping (Result<ImportedPhotoInput, Error>) -> Void) {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.version = .current
        PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, info in
            if (info?[PHImageResultIsDegradedKey] as? Bool) == true { return }
            if let data = data {
                let location = asset.location.map { Coordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) }
                completion(.success(ImportedPhotoInput(data: data, assetID: asset.localIdentifier, date: asset.creationDate, coordinate: location)))
            } else {
                completion(.failure(info?[PHImageErrorKey] as? Error ?? TripError.storage("照片暂不可用，请联网后重试。")))
            }
        }
    }
    func read(_ result: PHPickerResult, completion: @escaping (Result<ImportedPhotoInput, Error>) -> Void) {
        if let id = result.assetIdentifier, let asset = asset(id) { read(asset, completion: completion); return }
        let provider = result.itemProvider
        guard let type = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .image) == true }) else {
            completion(.failure(TripError.storage("请选择静态照片"))); return
        }
        provider.loadDataRepresentation(forTypeIdentifier: type) { data, error in
            if let data = data { completion(.success(ImportedPhotoInput(data: data, assetID: result.assetIdentifier, date: nil, coordinate: nil))) }
            else { completion(.failure(error ?? TripError.storage("照片暂不可用，请联网后重试。"))) }
        }
    }
}
