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
    @State private var saveState = L("编辑后自动保存")
    @State private var deleteConfirmation = false
    @State private var deleted = false
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 14) {
                TextField(L("给这段回忆起个标题"), text: $entry.title).font(.title2)
                if let coordinate = entry.coordinate { Label(String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude), systemImage: "mappin.and.ellipse").font(.caption).foregroundColor(.secondary) }
                ZStack(alignment: .topLeading) {
                    if entry.text.isEmpty { Text(L("此刻看到了什么？记下你的感受…")).foregroundColor(.secondary).padding(.top, 8).padding(.leading, 5) }
                    TextEditor(text: $entry.text).opacity(entry.text.isEmpty ? 0.75 : 1).accessibilityLabel(L("日记正文"))
                }
                HStack {
                    Text(saveState).font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Button(action: { deleteConfirmation = true }) { Image(systemName: "trash").foregroundColor(.red) }.accessibilityLabel(L("删除日记"))
                }
            }.padding()
            .navigationTitle(L("写日记")).navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button(L("完成")) { if save() { presentation.wrappedValue.dismiss() } })
            .onChange(of: entry.text) { _ in scheduleSave() }
            .onChange(of: entry.title) { _ in scheduleSave() }
            .onDisappear { pending?.cancel(); if !deleted { _ = save() } }
            .alert(isPresented: $deleteConfirmation) {
                Alert(title: Text(L("删除这篇日记？")), message: Text(L("删除后无法恢复。")), primaryButton: .destructive(Text(L("删除"))) { pending?.cancel(); if store.deleteDiary(entry) { deleted = true; presentation.wrappedValue.dismiss() } }, secondaryButton: .cancel(Text(L("取消"))))
            }
        }.navigationViewStyle(StackNavigationViewStyle())
    }
    private func scheduleSave() {
        pending?.cancel(); saveState = L("正在编辑…")
        let work = DispatchWorkItem { _ = self.save() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now()+0.8, execute: work)
    }
    @discardableResult private func save() -> Bool {
        if entry.title.isEmpty && entry.text.isEmpty && !store.diaries(entry.tripID).contains(where: { $0.id == entry.id }) { return true }
        var value = entry; value.updatedAt = Date()
        let result = store.saveDiary(value)
        saveState = result ? L("已保存在手机") : L("保存失败，请重试")
        return result
    }
}

struct TripEditor: View {
    @EnvironmentObject var store: TravelStore
    @Environment(\.presentationMode) var presentation
    @State var trip: Trip
    @State private var pending: DispatchWorkItem?
    @State private var message = L("编辑后自动保存")
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text(L("旅程名称"))) { TextField(L("名称"), text: $trip.title) }
                Section(header: Text(L("这段旅程的特点")), footer: Text(L("例如：海边、徒步、周末出发、美食"))) { TextField(L("特点或标签"), text: $trip.features) }
                Section(header: Text(L("总体感受"))) { TextEditor(text: $trip.reflection).frame(minHeight: 220).accessibilityLabel(L("旅程总体感受")) }
                Section { Text(message).font(.caption).foregroundColor(.secondary) }
            }
            .navigationTitle(L("旅程感受")).navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button(L("完成")) { if save() { presentation.wrappedValue.dismiss() } })
            .onChange(of: trip.title) { _ in schedule() }
            .onChange(of: trip.features) { _ in schedule() }
            .onChange(of: trip.reflection) { _ in schedule() }
            .onDisappear { pending?.cancel(); _ = save() }
        }.navigationViewStyle(StackNavigationViewStyle())
    }
    private func schedule() {
        pending?.cancel(); message = L("正在编辑…")
        let work = DispatchWorkItem { _ = self.save() }; pending = work
        DispatchQueue.main.asyncAfter(deadline: .now()+0.8, execute: work)
    }
    private func save() -> Bool { let success = store.update(trip); message = success ? L("已保存在手机") : L("保存失败，请重试"); return success }
}

struct PlacementView: View {
    @EnvironmentObject var store: TravelStore
    @Environment(\.presentationMode) var presentation
    let photo: PhotoAttachment
    @State private var coordinate: Coordinate?
    @State private var message: String?
    private var selected: Coordinate? { coordinate ?? photo.mapCoordinate }
    var body: some View {
        VStack(spacing: 0) {
            PlacementHeader(enabled: selected?.isValid == true,
                            cancel: { presentation.wrappedValue.dismiss() }, confirm: save).frame(height: 52)
            Text(L("在地图上轻点照片拍摄的位置")).font(.subheadline).padding()
            TravelMap(points: store.points(photo.tripID), selection: selected, pickingLocation: true,
                      fallback: store.currentCoordinate, onCoordinate: { coordinate = $0; message = nil })
            if let value = selected {
                Text(String(format: "%.5f, %.5f", value.latitude, value.longitude)).font(.caption).foregroundColor(.secondary).padding()
            }
            if let message = message { Text(message).foregroundColor(.red).padding(.horizontal) }
        }
    }
    private func save() {
        guard let value = selected else { return }
        do {
            try store.placeExistingPhoto(photo, at: value.identified)
            presentation.wrappedValue.dismiss()
        } catch { message = error.localizedDescription }
    }
}

private struct PlacementHeader: UIViewRepresentable {
    let enabled: Bool
    let cancel: () -> Void
    let confirm: () -> Void
    func makeUIView(context: Context) -> ShareHeaderView {
        let header = ShareHeaderView()
        header.doneButton.accessibilityIdentifier = "travel.placement.cancel"
        header.nextButton.accessibilityIdentifier = "travel.placement.confirm"
        return header
    }
    func updateUIView(_ header: ShareHeaderView, context: Context) {
        header.configure(title: L("放到地图上"), left: L("取消"), right: L("放在这里"),
                         enabled: enabled, onDone: cancel, onNext: confirm)
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
                    LocalPhoto(file: photo.sourceURL(in: store.files.directory, thumbnail: false), full: true).frame(maxWidth: .infinity).frame(height: 320).background(Color(UIColor.secondarySystemBackground)).clipped()
                    VStack(alignment: .leading, spacing: 18) {
                        if photo.isPreview == true {
                            Text(L("预览已就绪，完整照片仍在准备。")).foregroundColor(.secondary)
                            Button(L("重新读取照片")) { if let trip = store.trip(photo.tripID) { store.scanPhotos(for: trip, force: true) } }
                        }
                        if photo.captureDateKnown { Text(photo.capturedAt, style: .date).font(.headline) }
                        else { Text(L("拍摄日期未知")).font(.headline) }
                        Button(action: { sheet = .placement(photo) }) { Label(photo.coordinate == nil ? L("还没有位置 · 放到地图上") : L("查看或修改照片位置"), systemImage: "mappin.and.ellipse") }
                        Button(action: { sheet = .diary(store.diaries(photo.tripID).first { $0.photoID == photo.id } ?? DiaryEntry(tripID: photo.tripID, photoID: photo.id, coordinate: photo.coordinate, createdAt: Date(), updatedAt: Date())) }) { Label(L("写照片日记"), systemImage: "square.and.pencil") }.disabled(photo.isPreview == true)
                        ForEach(store.diaries(photo.tripID).filter { $0.photoID == photo.id }) { entry in
                            Button(action: { sheet = .diary(entry) }) { VStack(alignment: .leading, spacing: 8) { Text(entry.title.isEmpty ? L("照片日记") : entry.title).font(.headline); Text(entry.text).foregroundColor(.primary).multilineTextAlignment(.leading) } }
                        }
                        Text(photo.isPreview == true ? L("完整照片保存成功后，可编辑照片位置与日记。") : L("照片与系统相册同步，旅迹不保存照片副本。原图删除或访问权限关闭后将无法显示。")).font(.caption).foregroundColor(.secondary)
                        Button(action: { deleting = true }) { Text(L("从旅程移除照片")).foregroundColor(.red) }.foregroundColor(.red)
                    }.padding(.horizontal)
                }.padding(.bottom)
            }
            .navigationTitle(L("旅途照片")).navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button(L("完成")) { presentation.wrappedValue.dismiss() })
            .sheet(item: $sheet) { TravelSheetContent(sheet: $0).environmentObject(store) }
            .alert(isPresented: $deleting) {
                Alert(title: Text(L("移除这张照片？")), message: Text(L("系统相册原图不受影响。已有日记会保留。")), primaryButton: .destructive(Text(L("移除"))) { if store.removePhoto(photo) { presentation.wrappedValue.dismiss() } }, secondaryButton: .cancel(Text(L("取消"))))
            }
        }.navigationViewStyle(StackNavigationViewStyle())
    }
}

/// The slot takes its width from the grid, never from the image's aspect ratio.
struct PhotoThumbnail: View {
    let file: URL
    let height: CGFloat
    var cornerRadius: CGFloat = 8
    var body: some View {
        LocalPhoto(file: file)
            .frame(height: max(0, height))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .contentShape(Rectangle())
    }
}

struct LocalPhoto: View {
    let file: URL
    var full = false
    @State private var image: UIImage?
    @State private var request = UUID()
    @State private var loadedPath: String?
    @State private var photoRequest: PhotoImageRequest?
    @State private var unavailable = false
    var body: some View {
        GeometryReader { geometry in
            Group {
                if let image = image {
                    if full { Image(uiImage: image).resizable().scaledToFit() }
                    else { Image(uiImage: image).resizable().scaledToFill() }
                } else { ZStack { Color(UIColor.secondarySystemBackground); VStack(spacing: 4) { Image(systemName: "photo").foregroundColor(.secondary); if unavailable { Text(L("原图不可用或未授权")).font(.caption2).foregroundColor(.secondary).multilineTextAlignment(.center) } } } }
            }
            .frame(width: max(0, geometry.size.width), height: max(0, geometry.size.height))
            .clipped()
            .contentShape(Rectangle())
        }
        .contentShape(Rectangle())
        .onAppear(perform: load).onChange(of: file) { _ in load() }
        .onReceive(NotificationCenter.default.publisher(for: .travelPhotoLibraryChanged)) { _ in loadedPath = nil; load() }
        .onDisappear { photoRequest?.cancel(); loadedPath = nil }
    }
    private func load() {
        let key = file.absoluteString + (full ? ":full" : ":thumb")
        if loadedPath == key && image != nil { return }
        photoRequest?.cancel()
        let token = UUID(); request = token; loadedPath = key
        image = nil; unavailable = false
        photoRequest = PhotoImageLoader.load(file, edge: full ? 2048 : 640) { loaded in
            guard request == token else { return }
            if let loaded = loaded { image = loaded; unavailable = false }
            else if image == nil { unavailable = true }
        }
    }
}
