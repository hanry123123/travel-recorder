import SwiftUI

struct MemoryCard: View {
    let trip: Trip
    let points: [TrackPoint]
    let photos: [PhotoAttachment]
    let files: PhotoFileStore
    @ObservedObject var places: TripPlaceNames
    private var endpoints: String {
        [points.first?.coordinate, points.last?.coordinate].map { $0.map(MemoryPresentation.placeKey) ?? "" }.joined(separator: "|")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(places.name(for: points.first?.coordinate) + " to " + places.name(for: points.last?.coordinate))
                .font(.subheadline).fontWeight(.semibold).foregroundColor(.primary)
                .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            GeometryReader { geometry in
                let routeWidth = max(0, geometry.size.width * 0.45)
                let photoWidth = max(0, geometry.size.width - routeWidth - 10)
                HStack(spacing: 10) {
                    RoutePreview(points: points).frame(width: routeWidth, height: 132).clipped()
                    MemoryPhotoCollage(photos: MemoryPresentation.coverPhotos(photos), files: files)
                        .frame(width: photoWidth, height: 132).clipped()
                }
                .frame(width: geometry.size.width, height: 132)
            }.frame(height: 132).clipped()
            HStack {
                Text(trip.title).font(.headline).foregroundColor(.primary).lineLimit(1)
                Spacer()
                if trip.isFavorite { Image(systemName: "star.fill").foregroundColor(.orange) }
                if trip.status != .ended { Text(TravelFormat.status(trip.status)).font(.caption).foregroundColor(.blue) }
            }
            Text(trip.startedAt, style: .date).font(.caption).foregroundColor(.secondary)
            HStack {
                Label(TravelFormat.distance(trip.distance), systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                Spacer()
                Label((AppLanguage.english ? "\(photos.count) photos" : "\(photos.count) 张"), systemImage: "photo")
            }.font(.caption).foregroundColor(.secondary)
            if let reason = trip.favoriteReason, trip.isFavorite, !reason.isEmpty { Text(L("收藏理由：") + reason).font(.caption).foregroundColor(.secondary).lineLimit(2) }
            if !trip.features.isEmpty { Text(trip.features).font(.caption).foregroundColor(.blue).lineLimit(1) }
        }.padding(14).background(Color(UIColor.secondarySystemGroupedBackground)).cornerRadius(16)
        .onAppear(perform: requestNames)
        .onChange(of: endpoints) { _ in requestNames() }
        .onDisappear { places.hide(tripID: trip.id) }
    }
    private func requestNames() { places.show(tripID: trip.id, start: points.first?.coordinate, end: points.last?.coordinate, moving: trip.status != .ended) }
}

private struct MemoryPhotoCollage: View {
    let photos: [PhotoAttachment]
    let files: PhotoFileStore
    var body: some View {
        GeometryReader { geometry in
            if photos.isEmpty {
                VStack(spacing: 6) { Image(systemName: "photo"); Text(L("暂无照片")).font(.caption) }
                    .foregroundColor(.secondary).frame(width: geometry.size.width, height: geometry.size.height)
                    .background(Color(UIColor.tertiarySystemFill)).cornerRadius(9)
            } else if photos.count == 1 {
                tile(photos[0], width: geometry.size.width, height: geometry.size.height)
            } else {
                let column = max(0, (geometry.size.width-5)/2)
                HStack(spacing: 5) {
                    tile(photos[0], width: column, height: geometry.size.height)
                    if photos.count == 2 { tile(photos[1], width: column, height: geometry.size.height) }
                    else {
                        VStack(spacing: 5) {
                            tile(photos[1], width: column, height: (geometry.size.height-5)/2)
                            tile(photos[2], width: column, height: (geometry.size.height-5)/2)
                        }
                    }
                }
            }
        }
    }
    private func tile(_ photo: PhotoAttachment, width: CGFloat, height: CGFloat) -> some View {
        PhotoThumbnail(file: photo.sourceURL(in: files.directory), height: max(0, height), cornerRadius: 7)
            .id(photo.id).frame(width: max(0, width))
    }
}
