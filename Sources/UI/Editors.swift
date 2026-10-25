import SwiftUI
import PhotosUI

// A single sheet per presenter also supports the original iOS 14.0 SwiftUI runtime.
enum TravelSheet: Identifiable {
    case diary(DiaryEntry), photo(PhotoAttachment), placement(PhotoAttachment), trip(Trip), picker(UUID)
    case favorite(Trip), share(TripShareSnapshot), photoGroup([PhotoAttachment])
    var id: String {
        switch self {
        case .diary(let value): return "diary:" + value.id.uuidString
        case .photo(let value): return "photo:" + value.id.uuidString
        case .placement(let value): return "placement:" + value.id.uuidString
        case .trip(let value): return "trip:" + value.id.uuidString
        case .picker(let value): return "picker:" + value.uuidString
        case .favorite(let value): return "favorite:" + value.id.uuidString
        case .share(let value): return "share:" + value.id.uuidString
        case .photoGroup(let values): return "group:" + values.map { $0.id.uuidString }.joined()
        }
    }
}
struct TravelSheetContent: View {
    @EnvironmentObject var store: TravelStore
    let sheet: TravelSheet
    var onPickerFinished: () -> Void = {}
    var body: some View {
        switch sheet {
        case .diary(let entry): DiaryEditor(entry: entry)
        case .photo(let photo): PhotoDetail(original: photo)
        case .placement(let photo): PlacementView(photo: photo)
        case .trip(let trip): TripEditor(trip: trip)
        case .picker(let tripID): PhotoPicker { results in onPickerFinished(); store.importPhotos(results, into: tripID) }
        case .favorite(let trip): FavoriteEditor(trip: trip)
        case .share(let snapshot): TripShareScreen(snapshot: snapshot)
        case .photoGroup(let values): PhotoGroupScreen(photos: values)
        }
    }
}

struct PhotoPicker: UIViewControllerRepresentable {
    let completion: ([PHPickerResult]) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion) }
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 0
        configuration.preferredAssetRepresentationMode = .current
        let controller = PHPickerViewController(configuration: configuration)
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let completion: ([PHPickerResult]) -> Void
        init(_ completion: @escaping ([PHPickerResult]) -> Void) { self.completion = completion }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) { completion(results) }
    }
}

struct DiaryEditor: View {
    @EnvironmentObject var store: TravelStore
    @Environment(\.presentationMode) var presentation
    @State var entry: DiaryEntry
    @State private var pending: DispatchWorkItem?
    @State private var saveState = "编辑后自动保存"
    @State private var deleteConfirmation = false
    @State private var deleted = false
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 14) {
                TextField("给这段回忆起个标题", text: $entry.title).font(.title2)
                if let coordinate = entry.coordinate { Label(String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude), systemImage: "mappin.and.ellipse").font(.caption).foregroundColor(.secondary) }
                ZStack(alignment: .topLeading) {
                    if entry.text.isEmpty { Text("此刻看到了什么？记下你的感受…").foregroundColor(.secondary).padding(.top, 8).padding(.leading, 5) }
                    TextEditor(text: $entry.text).opacity(entry.text.isEmpty ? 0.75 : 1).accessibilityLabel("日记正文")
                }
                HStack {
                    Text(saveState).font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Button(action: { deleteConfirmation = true }) { Image(systemName: "trash").foregroundColor(.red) }.accessibilityLabel("删除日记")
                }
            }.padding()
            .navigationTitle("写日记").navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("完成") { if save() { presentation.wrappedValue.dismiss() } })
            .onChange(of: entry.text) { _ in scheduleSave() }
            .onChange(of: entry.title) { _ in scheduleSave() }
            .onDisappear { pending?.cancel(); if !deleted { _ = save() } }
            .alert(isPresented: $deleteConfirmation) {
                Alert(title: Text("删除这篇日记？"), message: Text("删除后无法恢复。"), primaryButton: .destructive(Text("删除")) { pending?.cancel(); if store.deleteDiary(entry) { deleted = true; presentation.wrappedValue.dismiss() } }, secondaryButton: .cancel(Text("取消")))
            }
        }.navigationViewStyle(StackNavigationViewStyle())
    }
    private func scheduleSave() {
        pending?.cancel(); saveState = "正在编辑…"
        let work = DispatchWorkItem { _ = self.save() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now()+0.8, execute: work)
    }
    @discardableResult private func save() -> Bool {
        if entry.title.isEmpty && entry.text.isEmpty && !store.diaries(entry.tripID).contains(where: { $0.id == entry.id }) { return true }
        var value = entry; value.updatedAt = Date()
        let result = store.saveDiary(value)
        saveState = result ? "已保存在手机" : "保存失败，请重试"
        return result
    }
}

struct TripEditor: View {
    @EnvironmentObject var store: TravelStore
    @Environment(\.presentationMode) var presentation
    @State var trip: Trip
    @State private var pending: DispatchWorkItem?
    @State private var message = "编辑后自动保存"
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("旅程名称")) { TextField("名称", text: $trip.title) }
                Section(header: Text("这段旅程的特点"), footer: Text("例如：海边、徒步、周末出发、美食")) { TextField("特点或标签", text: $trip.features) }
                Section(header: Text("总体感受")) { TextEditor(text: $trip.reflection).frame(minHeight: 220).accessibilityLabel("旅程总体感受") }
                Section { Text(message).font(.caption).foregroundColor(.secondary) }
            }
            .navigationTitle("旅程感受").navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("完成") { if save() { presentation.wrappedValue.dismiss() } })
            .onChange(of: trip.title) { _ in schedule() }
            .onChange(of: trip.features) { _ in schedule() }
            .onChange(of: trip.reflection) { _ in schedule() }
            .onDisappear { pending?.cancel(); _ = save() }
        }.navigationViewStyle(StackNavigationViewStyle())
    }
    private func schedule() {
        pending?.cancel(); message = "正在编辑…"
        let work = DispatchWorkItem { _ = self.save() }; pending = work
        DispatchQueue.main.asyncAfter(deadline: .now()+0.8, execute: work)
    }
    private func save() -> Bool { let success = store.update(trip); message = success ? "已保存在手机" : "保存失败，请重试"; return success }
}

struct PlacementView: View {
    @EnvironmentObject var store: TravelStore
    @Environment(\.presentationMode) var presentation
    let photo: PhotoAttachment
    @State private var coordinate: Coordinate?
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Text("在地图上轻点照片拍摄的位置").font(.subheadline).padding()
                TravelMap(points: store.points(photo.tripID), selection: coordinate ?? photo.mapCoordinate, fallback: store.currentCoordinate, onCoordinate: { coordinate = $0 })
                if let value = coordinate ?? photo.coordinate { Text(String(format: "%.5f, %.5f", value.latitude, value.longitude)).font(.caption).foregroundColor(.secondary).padding() }
            }
            .navigationTitle("放到地图上").navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(leading: Button("取消") { presentation.wrappedValue.dismiss() }, trailing: Button("放在这里") {
                if let value = coordinate ?? photo.mapCoordinate, store.place(photo, at: value.identified) { presentation.wrappedValue.dismiss() }
            }.disabled(coordinate == nil && photo.coordinate == nil))
        }.navigationViewStyle(StackNavigationViewStyle())
    }
}

struct PhotoDetail: View {
    @EnvironmentObject var store: TravelStore
    @Environment(\.presentationMode) var presentation
    let original: PhotoAttachment
    @State private var sheet: TravelSheet?
    @State private var deleting = false
    var photo: PhotoAttachment { store.attachments(original.tripID).first { $0.id == original.id } ?? original }
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    LocalPhoto(file: store.files.url(photo.imageFile), full: true).frame(maxWidth: .infinity).frame(height: 320).background(Color(UIColor.secondarySystemBackground)).clipped()
                    VStack(alignment: .leading, spacing: 18) {
                        if photo.isPreview == true {
                            Text("预览已就绪，完整照片仍在准备。").foregroundColor(.secondary)
                            Button("重新读取照片") { if let trip = store.trip(photo.tripID) { store.scanPhotos(for: trip, force: true) } }
                        }
                        if photo.captureDateKnown { Text(photo.capturedAt, style: .date).font(.headline) }
                        else { Text("拍摄日期未知").font(.headline) }
                        Button(action: { sheet = .placement(photo) }) { Label(photo.coordinate == nil ? "还没有位置 · 放到地图上" : "查看或修改照片位置", systemImage: "mappin.and.ellipse") }
                        Button(action: { sheet = .diary(store.diaries(photo.tripID).first { $0.photoID == photo.id } ?? DiaryEntry(tripID: photo.tripID, photoID: photo.id, coordinate: photo.coordinate, createdAt: Date(), updatedAt: Date())) }) { Label("写照片日记", systemImage: "square.and.pencil") }.disabled(photo.isPreview == true)
                        ForEach(store.diaries(photo.tripID).filter { $0.photoID == photo.id }) { entry in
                            Button(action: { sheet = .diary(entry) }) { VStack(alignment: .leading, spacing: 8) { Text(entry.title.isEmpty ? "照片日记" : entry.title).font(.headline); Text(entry.text).foregroundColor(.primary).multilineTextAlignment(.leading) } }
                        }
                        Text(photo.isPreview == true ? "完整照片保存成功后，可编辑照片位置与日记。" : "照片副本已保存在旅迹中，系统相册原图删除后仍可查看。").font(.caption).foregroundColor(.secondary)
                        Button("从旅程移除照片") { deleting = true }.foregroundColor(.red)
                    }.padding(.horizontal)
                }.padding(.bottom)
            }
            .navigationTitle("旅途照片").navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("完成") { presentation.wrappedValue.dismiss() })
            .sheet(item: $sheet) { TravelSheetContent(sheet: $0).environmentObject(store) }
            .alert(isPresented: $deleting) {
                Alert(title: Text("移除这张照片？"), message: Text("系统相册原图不受影响。已有日记会保留。"), primaryButton: .destructive(Text("移除")) { if store.removePhoto(photo) { presentation.wrappedValue.dismiss() } }, secondaryButton: .cancel(Text("取消")))
            }
        }.navigationViewStyle(StackNavigationViewStyle())
    }
}

struct LocalPhoto: View {
    let file: URL
    var full = false
    @State private var image: UIImage?
    @State private var request = UUID()
    @State private var loadedPath: String?
    private static let cache = NSCache<NSString, UIImage>()
    var body: some View {
        Group {
            if let image = image {
                if full { Image(uiImage: image).resizable().scaledToFit() }
                else { Image(uiImage: image).resizable().scaledToFill() }
            } else { ZStack { Color(UIColor.secondarySystemBackground); Image(systemName: "photo").foregroundColor(.secondary) } }
        }.onAppear(perform: load).onChange(of: file) { _ in load() }
    }
    private func load() {
        if loadedPath == file.path && image != nil { return }
        let token = UUID(); request = token
        loadedPath = file.path
        if let cached = Self.cache.object(forKey: file.path as NSString) { image = cached; return }
        DispatchQueue.global(qos: .userInitiated).async {
            let loaded = UIImage(contentsOfFile: file.path)
            if let loaded = loaded { Self.cache.totalCostLimit = 40 * 1024 * 1024; Self.cache.setObject(loaded, forKey: file.path as NSString, cost: Int(loaded.size.width*loaded.size.height*4)) }
            DispatchQueue.main.async { if request == token, let loaded = loaded { image = loaded } }
        }
    }
}
