import SwiftUI
import AVKit
import Photos

struct SharedFile: Identifiable { let id = UUID(); let url: URL }

struct TripShareScreen: View {
    let snapshot: TripShareSnapshot
    @EnvironmentObject private var store: TravelStore
    @Environment(\.presentationMode) private var presentation
    @StateObject private var exporter = TripShareExporter()
    @State private var video = false
    @State private var selected: Set<UUID>
    @State private var text: String
    @State private var includeReflection = false
    @State private var includeDiaries = false
    @State private var activity: SharedFile?
    @State private var player: AVPlayer?
    @State private var saveMessage = ""
    init(snapshot: TripShareSnapshot) {
        self.snapshot = snapshot
        _selected = State(initialValue: Set(ShareSelection.representative(snapshot.photos)))
        _text = State(initialValue: snapshot.trip.features)
    }
    private var limit: Int { video ? 9 : 3 }
    private var selectedPhotos: [PhotoAttachment] {
        snapshot.photos.filter { selected.contains($0.id) }.sorted { $0.capturedAt < $1.capturedAt }
    }
    private var shareText: String {
        ([text] + (includeReflection ? [snapshot.trip.reflection] : []) + (includeDiaries ? snapshot.diaries.map { $0.title + "\n" + $0.text } : []))
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: "\n\n")
    }
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if snapshot.trip.status != .ended { Text("本次内容截至 " + snapshot.capturedAt.formattedShareTime).font(.caption).foregroundColor(.secondary) }
                    Picker("分享形式", selection: $video) { Text("旅程图片").tag(false); Text("重现视频").tag(true) }.pickerStyle(SegmentedPickerStyle())
                    Text("照片 · 已选 \(selected.count)/\(limit)").font(.headline)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 85))]) {
                        ForEach(snapshot.photos) { photo in
                            Button(action: {
                                if selected.contains(photo.id) { selected.remove(photo.id) }
                                else if selected.count < limit { selected.insert(photo.id) }
                            }) {
                                ZStack(alignment: .topTrailing) {
                                    LocalPhoto(file: snapshot.photoDirectory.appendingPathComponent(photo.thumbnailFile)).frame(height: 90).clipped().cornerRadius(8)
                                    Image(systemName: selected.contains(photo.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(selected.contains(photo.id) ? .blue : .white).background(Color.white.opacity(0.65)).clipShape(Circle()).padding(5)
                                }
                            }.buttonStyle(PlainButtonStyle())
                        }
                    }
                    Text("以路线形状呈现旅程，包含你选择的照片与文字。").font(.caption).foregroundColor(.secondary)
                    Text("分享文字").font(.headline)
                    if video { Text("视频展示文字摘要；长篇日记建议使用旅程图片。").font(.caption).foregroundColor(.secondary) }
                    TextEditor(text: $text).frame(height: 100).padding(6).background(Color(UIColor.secondarySystemBackground)).cornerRadius(8)
                    if let reason = snapshot.trip.favoriteReason, !reason.isEmpty { Button("使用收藏理由") { text = reason } }
                    if !snapshot.trip.reflection.isEmpty { Toggle("加入总体感受", isOn: $includeReflection) }
                    if !snapshot.diaries.isEmpty { Toggle("加入日记正文", isOn: $includeDiaries) }
                    if !exporter.busy {
                        Button(action: generate) { Label(exporter.output == nil ? "生成预览" : "重新生成", systemImage: video ? "film" : "photo").frame(maxWidth: .infinity).padding() }
                            .background(Color.blue).foregroundColor(.white).cornerRadius(12)
                    } else {
                        ProgressView(value: exporter.progress)
                        HStack { Text(exporter.message).font(.caption); Spacer(); Button("取消生成") { exporter.cancel() } }
                    }
                    if !exporter.message.isEmpty && !exporter.busy { Text(exporter.message).font(.caption).foregroundColor(.secondary) }
                    if let image = exporter.preview { Image(uiImage: image).resizable().scaledToFit().cornerRadius(12) }
                    if let player = player { VideoPlayer(player: player).frame(height: 380).cornerRadius(12) }
                    if let output = exporter.output {
                        HStack {
                            Button("分享…") { player?.pause(); activity = SharedFile(url: output) }
                            Spacer()
                            Button("保存到相册") { save(output) }
                        }.padding().background(Color(UIColor.secondarySystemBackground)).cornerRadius(12)
                        Text("在分享面板选择微信；若未显示，可先保存到相册，再从微信发送或发布朋友圈。").font(.caption).foregroundColor(.secondary)
                    }
                    if !saveMessage.isEmpty { Text(saveMessage).font(.caption) }
                }.padding()
            }
            .navigationTitle("分享旅程").navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("完成") { exporter.cancel(); player?.pause(); presentation.wrappedValue.dismiss() })
            .onChange(of: video) { _ in
                selected = Set(selectedPhotos.prefix(limit).map { $0.id }); invalidate()
            }
            .onChange(of: selected) { _ in invalidate() }
            .onChange(of: text) { _ in invalidate() }
            .onChange(of: includeReflection) { _ in invalidate() }
            .onChange(of: includeDiaries) { _ in invalidate() }
            .onChange(of: exporter.output) { url in
                if let url = url, url.pathExtension == "mp4" { player = AVPlayer(url: url) } else { player = nil }
            }
            .onDisappear { exporter.cancel(); player?.pause() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                if exporter.busy { exporter.cancel(message: "生成已中断，请回到应用后重新生成。") }; player?.pause()
            }
            .sheet(item: $activity) { ShareActivity(url: $0.url) }
        }.navigationViewStyle(StackNavigationViewStyle())
    }
    private func invalidate() { player?.pause(); player = nil; exporter.invalidate(); saveMessage = "" }
    private func generate() { player?.pause(); player = nil; saveMessage = ""; exporter.generate(snapshot: snapshot, photos: selectedPhotos, text: shareText, video: video) }
    private func save(_ url: URL) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { DispatchQueue.main.async { saveMessage = "请在设置中允许保存到相册。" }; return }
            PHPhotoLibrary.shared().performChanges({
                if url.pathExtension == "mp4" { PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url) }
                else {
                    let date = Date()
                    let request = PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
                    request?.creationDate = date
                    if let id = request?.placeholderForCreatedAsset?.localIdentifier {
                        let exclude = { store.excludeSharedPhoto(id, capturedAt: date) }
                        if Thread.isMainThread { exclude() } else { DispatchQueue.main.sync(execute: exclude) }
                    }
                }
            }) { success, error in DispatchQueue.main.async { saveMessage = success ? "已保存到相册" : "保存失败：\(error?.localizedDescription ?? "请重试")" } }
        }
    }
}

struct ShareActivity: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

extension Date {
    var formattedShareTime: String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_CN"); formatter.dateFormat = "MM-dd HH:mm:ss"
        return formatter.string(from: self)
    }
}

extension TravelStore {
    func shareSnapshot(_ id: UUID) -> TripShareSnapshot {
        let value = trip(id) ?? Trip(now: Date())
        let route = points(id)
        return TripShareSnapshot(trip: value, points: route, photos: attachments(id).filter { $0.isPreview != true }, diaries: diaries(id), photoDirectory: files.directory,
                                 endpoints: value.title, capturedAt: Date(),
                                 alignment: MapAlignment(rawValue: UserDefaults.standard.string(forKey: "mapAlignment") ?? "") ?? .automatic)
    }
}
