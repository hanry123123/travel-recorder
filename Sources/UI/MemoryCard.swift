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
                HStack(spacing: 10) {
                    RoutePreview(points: points).frame(width: geometry.size.width*0.45).clipped()
                    MemoryPhotoCollage(photos: MemoryPresentation.coverPhotos(photos), files: files)
                }
            }.frame(height: 132)
            HStack {
                Text(trip.title).font(.headline).foregroundColor(.primary).lineLimit(1)
                Spacer()
                if trip.status != .ended { Text(TravelFormat.status(trip.status)).font(.caption).foregroundColor(.blue) }
            }
            Text(trip.startedAt, style: .date).font(.caption).foregroundColor(.secondary)
            HStack {
                Label(TravelFormat.distance(trip.distance), systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                Spacer()
                Label("\(photos.count) 张", systemImage: "photo")
            }.font(.caption).foregroundColor(.secondary)
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
                VStack(spacing: 6) { Image(systemName: "photo"); Text("暂无照片").font(.caption) }
                    .foregroundColor(.secondary).frame(width: geometry.size.width, height: geometry.size.height)
                    .background(Color(UIColor.tertiarySystemFill)).cornerRadius(9)
            } else if photos.count == 1 {
                tile(photos[0], width: geometry.size.width, height: geometry.size.height)
            } else {
                let column = (geometry.size.width-5)/2
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
        LocalPhoto(file: files.url(photo.thumbnailFile)).id(photo.thumbnailFile)
            .frame(width: max(1, width), height: max(1, height)).clipped().cornerRadius(7)
    }
}
