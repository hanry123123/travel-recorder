import SwiftUI

struct FavoriteEditor: View {
    @EnvironmentObject var store: TravelStore
    @Environment(\.presentationMode) private var presentation
    let trip: Trip
    @State private var reason: String
    init(trip: Trip) {
        self.trip = trip; _reason = State(initialValue: trip.favoriteReason ?? "")
    }
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text(L("为什么想收藏这段旅程？")), footer: Text(L("可以留空"))) {
                    TextEditor(text: $reason).frame(minHeight: 150)
                }
                if trip.isFavorite {
                    Button(L("取消收藏")) {
                        if store.setFavorite(trip.id, reason: nil, enabled: false) { presentation.wrappedValue.dismiss() }
                    }.foregroundColor(.red)
                }
            }.navigationTitle(trip.isFavorite ? L("编辑收藏") : L("收藏旅程"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(leading: Button(L("取消")) { presentation.wrappedValue.dismiss() }, trailing: Button(L("保存")) {
                if store.setFavorite(trip.id, reason: reason, enabled: true) { presentation.wrappedValue.dismiss() }
            })
        }.navigationViewStyle(StackNavigationViewStyle())
    }
}

struct TripActions: View {
    @EnvironmentObject var store: TravelStore
    let trip: Trip
    @Binding var sheet: TravelSheet?
    var body: some View {
        HStack(spacing: 24) {
            Button(action: { sheet = .favorite(trip) }) {
                Image(systemName: trip.isFavorite ? "star.fill" : "star")
                    .font(.system(size: 22)).frame(width: 44, height: 44)
                    .accessibilityLabel(trip.isFavorite ? L("编辑收藏") : L("收藏旅程"))
                    .foregroundColor(trip.isFavorite ? .orange : .blue)
            }
            Button(action: { sheet = .share(store.shareSnapshot(trip.id)) }) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 22)).frame(width: 44, height: 44)
                    .accessibilityLabel(L("分享旅程"))
                    .foregroundColor(.blue)
            }
        }.font(.subheadline).buttonStyle(PlainButtonStyle())
    }
}

struct PhotoGroupScreen: View {
    @EnvironmentObject var store: TravelStore
    @Environment(\.presentationMode) private var presentation
    let photos: [PhotoAttachment]
    @State private var sheet: TravelSheet?
    private var currentPhotos: [PhotoAttachment] {
        guard let id = photos.first?.tripID else { return [] }
        let ids = Set(photos.map { $0.id })
        return store.attachments(id).filter { ids.contains($0.id) }
    }
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                    ForEach(currentPhotos) { photo in
                        Button(action: { sheet = .photo(photo) }) {
                            PhotoThumbnail(file: photo.sourceURL(in: store.files.directory), height: 140)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .accessibilityLabel(L("查看照片"))
                    }
                }.padding()
            }.navigationTitle(L("这里的照片")).navigationBarItems(trailing: Button(L("完成")) { presentation.wrappedValue.dismiss() })
            .sheet(item: $sheet) { TravelSheetContent(sheet: $0).environmentObject(store) }
        }.navigationViewStyle(StackNavigationViewStyle())
    }
}
