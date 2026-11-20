import SwiftUI

struct SharedFile: Identifiable { let id = UUID(); let url: URL }

struct TripShareScreen: View {
    let snapshot: TripShareSnapshot
    @Environment(\.presentationMode) private var presentation
    @StateObject private var exporter = TripShareExporter()
    @State private var showingPreview = false
    @State private var selected: Set<UUID>
    @State private var title: String
    @State private var text: String
    @State private var activity: SharedFile?
    init(snapshot: TripShareSnapshot) {
        self.snapshot = snapshot
        _selected = State(initialValue: Set(ShareSelection.representative(snapshot.photos)))
        _title = State(initialValue: "")
        _text = State(initialValue: "")
    }
    private let limit = 3
    private var selectedPhotos: [PhotoAttachment] {
        snapshot.photos.filter { selected.contains($0.id) }.sorted { $0.capturedAt < $1.capturedAt }
    }
    private var editedSnapshot: TripShareSnapshot {
        var trip = snapshot.trip
        trip.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return TripShareSnapshot(trip: trip, points: snapshot.points, photos: snapshot.photos, diaries: snapshot.diaries,
            photoDirectory: snapshot.photoDirectory, endpoints: SharePosterLayout.limited(trip.title, title: true),
            capturedAt: snapshot.capturedAt, alignment: snapshot.alignment)
    }
    var body: some View {
        VStack(spacing: 0) {
            ShareNavigationBar(showingPreview: showingPreview, canShare: exporter.output != nil, onLeft: {
                if showingPreview {
                    exporter.invalidate()
                    showingPreview = false
                } else {
                    exporter.cancel()
                    presentation.wrappedValue.dismiss()
                }
            }, onRight: {
                if showingPreview {
                    if let output = exporter.output { activity = SharedFile(url: output) }
                } else {
                    generate()
                }
            }).frame(height: 52)
            ScrollView {
                if showingPreview { previewContent.padding() }
                else { editorContent.padding() }
            }
            .onDisappear { exporter.cancel() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                if exporter.busy { exporter.cancel(message: L("生成已中断，请回到应用后重新生成。")) }
            }
            .sheet(item: $activity) { ShareActivity(url: $0.url) }
        }.background(Color(UIColor.systemBackground))
    }
    private var editorContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            if snapshot.trip.status != .ended { Text(L("本次内容截至 ") + snapshot.capturedAt.formattedShareTime).font(.caption).foregroundColor(.secondary) }
            HStack {
                Text(AppLanguage.english ? "Share title" : "分享标题").font(.headline)
                Spacer()
                Text("\(title.count)/\(SharePosterLayout.titleLimit)").font(.caption).foregroundColor(.secondary)
            }
            ShareTextEditor(text: $title, title: true).frame(height: 64)
            Text(AppLanguage.english ? "Only changes this shared image" : "只修改这张分享图片的标题").font(.caption).foregroundColor(.secondary)
            Text((AppLanguage.english ? "Photos · \(selected.count)/\(limit) selected" : "照片 · 已选 \(selected.count)/\(limit)")).font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 85), spacing: 10)], spacing: 10) {
                ForEach(snapshot.photos) { photo in
                    Button(action: {
                        if selected.contains(photo.id) { selected.remove(photo.id) }
                        else if selected.count < limit { selected.insert(photo.id) }
                    }) {
                        ZStack(alignment: .topTrailing) {
                            PhotoThumbnail(file: photo.sourceURL(in: snapshot.photoDirectory), height: 90)
                            Image(systemName: selected.contains(photo.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(selected.contains(photo.id) ? .blue : .white).background(Color.white.opacity(0.65)).clipShape(Circle()).padding(5)
                        }.frame(height: 90).contentShape(Rectangle())
                    }.buttonStyle(PlainButtonStyle())
                        .accessibilityLabel(AppLanguage.english ? "Select photo" : "选择照片")
                        .accessibilityValue(selected.contains(photo.id) ? (AppLanguage.english ? "Selected" : "已选择") : (AppLanguage.english ? "Not selected" : "未选择"))
                }
            }
            Text(L("在地图上呈现路线，包含你选择的照片与文字。")).font(.caption).foregroundColor(.secondary)
            HStack {
                Text(L("分享文字")).font(.headline)
                Spacer()
                Text("\(text.count)/\(SharePosterLayout.bodyLimit)").font(.caption).foregroundColor(.secondary)
            }
            ShareTextEditor(text: $text).frame(height: 120)
            Text(AppLanguage.english ? "Up to 120 characters and 5 poster lines. Extra text is not added." : "最多120字、海报中最多5行，超出部分不再加入。").font(.caption).foregroundColor(.secondary)
            if let reason = snapshot.trip.favoriteReason, !reason.isEmpty {
                Button(L("使用收藏理由")) { text = SharePosterLayout.limited(reason) }
            }
            if !snapshot.trip.reflection.isEmpty {
                Button(L("加入总体感受")) { appendText(snapshot.trip.reflection) }
            }
            if !snapshot.diaries.isEmpty {
                Button(L("加入日记正文")) { appendText(snapshot.diaries.map { $0.title + "\n" + $0.text }.joined(separator: "\n")) }
            }
        }
    }
    private var previewContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            if exporter.busy {
                ProgressView(value: exporter.progress)
                HStack {
                    Text(exporter.message).font(.subheadline)
                    Spacer()
                    Button(L("取消生成")) { exporter.cancel() }
                }
            } else if let image = exporter.preview {
                Image(uiImage: image).resizable().scaledToFit().cornerRadius(12)
            } else {
                Text(exporter.message).font(.subheadline)
                Button(L("重试"), action: generate)
            }
        }
    }
    private func appendText(_ value: String) {
        text = SharePosterLayout.limited([text, value].filter { !$0.isEmpty }.joined(separator: "\n"))
    }
    private func generate() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        showingPreview = true
        exporter.generate(snapshot: editedSnapshot, photos: selectedPhotos, text: text, useMap: true)
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
