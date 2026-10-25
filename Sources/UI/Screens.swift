import SwiftUI
import Photos

enum TravelFormat {
    static func distance(_ meters: Double) -> String { meters < 1000 ? "\(Int(meters)) 米" : String(format: "%.2f 公里", meters/1000) }
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int(seconds)/60)
        return minutes >= 60 ? "\(minutes/60) 小时 \(minutes%60) 分" : "\(minutes) 分钟"
    }
    static func status(_ status: TripStatus) -> String {
        switch status { case .recording: return "记录中"; case .paused: return "已暂停"; case .interrupted: return "记录中断"; case .ended: return "已结束" }
    }
}
struct RecordingScreen: View {
    @Environment(\.displayScale) private var displayScale
    var isVisible = true
    @StateObject private var replay = RouteReplayController()
    @EnvironmentObject var store: TravelStore
    @State private var fitToken = 0
    @State private var recenterToken = 0
    @State private var follow = true
    @State private var showingFinish = false
    @State private var sheet: TravelSheet?
    @State private var clock = Date()
    @State private var mapReady = false
    private let timer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                GeometryReader { geometry in
                  ZStack(alignment: .bottomTrailing) {
                    if mapReady && store.ready && isVisible {
                    TravelMap(points: store.activeTrip.map { store.points($0.id) } ?? [], photos: store.activeTrip.map { store.attachments($0.id) } ?? [], photoDirectory: store.files?.directory, diaries: store.activeTrip.map { store.diaries($0.id) } ?? [], fallback: store.currentCoordinate, fitToken: fitToken, recenterToken: recenterToken, follow: follow, isInteractive: isVisible, replay: replay,
                              onCoordinate: { coordinate in
                        guard let trip = store.activeTrip else { return }
                        sheet = .diary(DiaryEntry(tripID: trip.id, coordinate: coordinate, createdAt: Date(), updatedAt: Date()))
                    }, onPhoto: { id in
                        if let trip = store.activeTrip, let value = store.attachments(trip.id).first(where: { $0.id == id }) { sheet = .photo(value) }
                    }, onDiary: { id in
                        if let trip = store.activeTrip, let value = store.diaries(trip.id).first(where: { $0.id == id }) { sheet = .diary(value) }
                    }, onPhotos: { ids in
                        if let trip = store.activeTrip { sheet = .photoGroup(store.attachments(trip.id).filter { ids.contains($0.id) }) }
                    }, onUserInteraction: { follow = false })
                    .frame(width: geometry.size.width, height: floor(geometry.size.height * displayScale) / displayScale)
                    } else { Color(UIColor.secondarySystemBackground).overlay(Text(store.ready ? "地图准备中…" : "正在读取本机旅程…").foregroundColor(.secondary)).allowsHitTesting(false) }
                    HStack(spacing: 14) {
                        MapCircleButton(symbol: follow ? "location.fill" : "location", label: "回到当前位置并跟随") { replay.stop(); follow = true; recenterToken += 1 }
                        MapCircleButton(symbol: "arrow.up.left.and.arrow.down.right", label: "查看整段路线") { replay.stop(); follow = false; fitToken += 1 }
                    }.padding()
                  }.frame(width: geometry.size.width, height: floor(geometry.size.height * displayScale) / displayScale)
                }.background(Color(UIColor.systemBackground))
                VStack(spacing: 14) {
                    if let trip = store.activeTrip {
                        ReplayControls(controller: replay, points: store.points(trip.id), recording: trip.status != .ended)
                        HStack {
                            stat(TravelFormat.distance(trip.distance), label: "已记录里程")
                            Spacer()
                            stat(TravelFormat.duration(trip.duration(at: clock)), label: "记录时长")
                            Spacer()
                            Text(TravelFormat.status(trip.status)).font(.caption).foregroundColor(trip.status == .recording ? .green : .orange)
                        }
                        Text(trip.status == .interrupted ? "上次记录已中断，已有路线已保留。可继续或结束旅程。" : store.locationMessage).font(.caption).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: 12) {
                            Button(action: { trip.status == .recording ? store.pause() : store.startOrResume() }) {
                                Label(trip.status == .recording ? "暂停" : "继续", systemImage: trip.status == .recording ? "pause.fill" : "play.fill").frame(maxWidth: .infinity).padding(.vertical, 13)
                            }.background(Color.blue).foregroundColor(.white).cornerRadius(12)
                            Button("结束旅程") { showingFinish = true }.padding(.vertical, 13).padding(.horizontal, 22).background(Color(UIColor.secondarySystemBackground)).cornerRadius(12)
                        }
                        HStack {
                            NavigationLink(destination: TripDetailScreen(tripID: trip.id)) { Label("照片与日记", systemImage: "book") }
                            Spacer()
                            TripActions(trip: trip, sheet: $sheet)
                        }.font(.subheadline)
                    } else {
                        VStack(spacing: 6) {
                            Text("把走过的路，留成回忆").font(.headline)
                            Text("开始后可锁屏、拍照；轻点地图记录沿途感受。").font(.caption).foregroundColor(.secondary)
                        }
                        Button(action: { clock = Date(); store.startOrResume() }) {
                            Label("开始记录", systemImage: "location.fill").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 15)
                        }.foregroundColor(.white).background(Color.blue).cornerRadius(12).disabled(!store.ready)
                    }
                    if store.importCount > 0 { HStack { ProgressView(); Text("正在保存 \(store.importCount) 张照片").font(.caption) } }
                }.padding().background(Color(UIColor.systemBackground)).fixedSize(horizontal: false, vertical: true)
            }
            .navigationTitle("旅迹").navigationBarTitleDisplayMode(.inline)
            .onAppear { DispatchQueue.main.asyncAfter(deadline: .now()+0.35) { mapReady = true } }
            .onReceive(timer) { clock = $0 }
            .onDisappear { replay.stop() }
            .onChange(of: isVisible) { visible in if !visible { replay.stop() } }
            .onChange(of: store.activeTrip?.id) { _ in replay.stop() }
            .sheet(item: $sheet) { TravelSheetContent(sheet: $0).environmentObject(store) }
            .alert(isPresented: $showingFinish) {
                Alert(title: Text("结束这段旅程？"), message: Text("路线将保存在回忆中，照片和日记以后还可以补充。"), primaryButton: .default(Text("结束并保存")) { store.finish() }, secondaryButton: .cancel(Text("继续旅程")))
            }
        }.navigationViewStyle(StackNavigationViewStyle())
    }
    private func stat(_ value: String, label: String) -> some View { VStack(alignment: .leading, spacing: 4) { Text(value).font(.headline); Text(label).font(.caption).foregroundColor(.secondary) } }
}

struct MemoriesScreen: View {
    @EnvironmentObject var store: TravelStore
    @State private var query = ""
    @State private var deletingTrip: Trip?
    @State private var favoritesOnly = false
    @State private var sheet: TravelSheet?
    var filtered: [Trip] {
        store.trips.filter { (!favoritesOnly || $0.isFavorite) && (query.isEmpty || ($0.title + $0.features + $0.reflection + ($0.favoriteReason ?? "")).localizedCaseInsensitiveContains(query)) }
            .sorted { favoritesOnly ? ($0.favoritedAt ?? .distantPast) > ($1.favoritedAt ?? .distantPast) : $0.startedAt > $1.startedAt }
    }
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    HStack { Image(systemName: "magnifyingglass").foregroundColor(.secondary); TextField("搜索旅程、特点或收藏理由", text: $query) }.padding(12).background(Color(UIColor.secondarySystemGroupedBackground)).cornerRadius(12)
                    Picker("回忆范围", selection: $favoritesOnly) {
                        Text("全部").tag(false); Text("★ 收藏").tag(true)
                    }.pickerStyle(SegmentedPickerStyle())
                    if !store.ready { ProgressView("正在读取本机旅程…") }
                    if store.ready && filtered.isEmpty {
                        VStack(spacing: 16) { Image(systemName: "map").font(.system(size: 48)).foregroundColor(.blue); Text(query.isEmpty ? (favoritesOnly ? "还没有收藏的旅程" : "你的旅行故事，从这里开始") : "没有找到这段回忆").font(.headline); Text("记录路线，留下照片与心情。").foregroundColor(.secondary) }.padding(.vertical, 70)
                    }
                    LazyVStack(spacing: 16) {
                        ForEach(filtered) { trip in
                            VStack(alignment: .trailing, spacing: 0) {
                                NavigationLink(destination: TripDetailScreen(tripID: trip.id)) {
                                    MemoryCard(trip: trip, points: store.points(trip.id), photos: store.attachments(trip.id), files: store.files, places: store.placeNames)
                                }.buttonStyle(PlainButtonStyle())
                                HStack {
                                    TripActions(trip: trip, sheet: $sheet).padding(.leading, 14)
                                    Spacer()
                                if trip.status == .ended {
                                    Button(action: { deletingTrip = trip }) { Image(systemName: "trash").font(.system(size: 22)).foregroundColor(.red).frame(width: 44, height: 44).accessibilityLabel("删除回忆") }
                                        .buttonStyle(PlainButtonStyle())
                                }
                                }.padding(.bottom, 10)
                            }.background(Color(UIColor.secondarySystemGroupedBackground)).cornerRadius(16)
                        }
                    }
                }.padding()
            }.background(Color(UIColor.systemGroupedBackground).edgesIgnoringSafeArea(.bottom))
            .navigationTitle("回忆")
            .sheet(item: $sheet) { TravelSheetContent(sheet: $0).environmentObject(store) }
            .alert(item: $deletingTrip) { trip in
                Alert(title: Text("删除“\(trip.title)”？"), message: Text("这段路线、日记和 App 内的照片副本将被删除，无法恢复。系统相册原图保留。"), primaryButton: .destructive(Text("删除回忆")) { store.deleteTrip(trip.id) }, secondaryButton: .cancel(Text("取消")))
            }
        }.navigationViewStyle(StackNavigationViewStyle())
    }
}

struct TripDetailScreen: View {
    @StateObject private var replay = RouteReplayController()
    @EnvironmentObject var store: TravelStore
    @Environment(\.presentationMode) var presentation
    let tripID: UUID
    @State private var sheet: TravelSheet?
    @State private var deleting = false
    @State private var fitToken = 0
    var body: some View {
        Group {
            if let trip = store.trip(tripID) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        ZStack(alignment: .bottomTrailing) {
                            TravelMap(points: store.points(tripID), photos: store.attachments(tripID), photoDirectory: store.files.directory, diaries: store.diaries(tripID), fitToken: fitToken, replay: replay, onCoordinate: { sheet = .diary(DiaryEntry(tripID: tripID, coordinate: $0, createdAt: Date(), updatedAt: Date())) }, onPhoto: { id in if let value = store.attachments(tripID).first(where: { $0.id == id }) { sheet = .photo(value) } }, onDiary: { id in if let value = store.diaries(tripID).first(where: { $0.id == id }) { sheet = .diary(value) } }, onPhotos: { ids in sheet = .photoGroup(store.attachments(tripID).filter { ids.contains($0.id) }) }).frame(height: 340)
                            MapCircleButton(symbol: "arrow.up.left.and.arrow.down.right", label: "查看整段路线") { replay.stop(); fitToken += 1 }.padding()
                        }
                        VStack(alignment: .leading, spacing: 22) {
                            TripActions(trip: trip, sheet: $sheet)
                            ReplayControls(controller: replay, points: store.points(tripID), recording: trip.status != .ended)
                            HStack { Label(TravelFormat.distance(trip.distance), systemImage: "location"); Spacer(); Label(TravelFormat.duration(trip.duration(at: Date())), systemImage: "clock") }.font(.subheadline).foregroundColor(.secondary)
                            Text("轻点地图任意地点，即可写日记。").font(.caption).foregroundColor(.secondary)
                            Button(action: { sheet = .trip(trip) }) {
                                VStack(alignment: .leading, spacing: 10) {
                                    Label("旅程特点与总体感受", systemImage: "square.and.pencil").font(.headline)
                                    if !trip.features.isEmpty { Text(trip.features).foregroundColor(.blue) }
                                    Text(trip.reflection.isEmpty ? "这段旅程，给你留下了什么？" : trip.reflection).foregroundColor(trip.reflection.isEmpty ? .secondary : .primary).multilineTextAlignment(.leading)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding().background(Color(UIColor.secondarySystemBackground)).cornerRadius(12)
                            }.buttonStyle(PlainButtonStyle())
                            HStack { Text("旅途照片").font(.title3).bold(); Spacer(); Button(action: { sheet = .picker(tripID) }) { Label("添加", systemImage: "plus") } }
                            Text(store.photoAccessDescription).font(.caption).foregroundColor(.secondary)
                            if !store.photoMessage.isEmpty { Text(store.photoMessage).font(.caption).foregroundColor(.secondary) }
                            if store.attachments(tripID).isEmpty { Text("添加沿途照片，或从相册挑选以前的回忆。").foregroundColor(.secondary).padding(.vertical, 12) }
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 95), spacing: 10)], spacing: 10) {
                                ForEach(store.attachments(tripID)) { attachment in
                                    Button(action: { sheet = .photo(attachment) }) {
                                        ZStack(alignment: .bottom) {
                                            LocalPhoto(file: store.files.url(attachment.thumbnailFile)).frame(height: 110).clipped()
                                            if attachment.coordinate == nil { Text("待放置").font(.caption).foregroundColor(.white).padding(5).frame(maxWidth: .infinity).background(Color.black.opacity(0.55)) }
                                        }.cornerRadius(9)
                                    }.buttonStyle(PlainButtonStyle()).accessibilityLabel(attachment.coordinate == nil ? "照片，待放置到地图" : "查看照片")
                                }
                            }
                            Button("检查旅程中的新照片") { store.scanPhotos(for: trip, force: true) }.font(.subheadline)
                            HStack { Text("旅途日记").font(.title3).bold(); Spacer(); Button("写一篇") { sheet = .diary(DiaryEntry(tripID: tripID, createdAt: Date(), updatedAt: Date())) } }
                            ForEach(store.diaries(tripID)) { entry in
                                Button(action: { sheet = .diary(entry) }) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack { Image(systemName: entry.photoID != nil ? "photo" : entry.coordinate != nil ? "mappin.and.ellipse" : "book.closed").foregroundColor(.blue); Text(entry.title.isEmpty ? "一段旅行日记" : entry.title).font(.headline); Spacer() }
                                        Text(entry.text).lineLimit(4).foregroundColor(.secondary).multilineTextAlignment(.leading)
                                        Text(entry.updatedAt, style: .date).font(.caption).foregroundColor(.secondary)
                                    }.frame(maxWidth: .infinity, alignment: .leading).padding().background(Color(UIColor.secondarySystemBackground)).cornerRadius(12)
                                }.buttonStyle(PlainButtonStyle())
                            }
                            if trip.status == .ended { Button("删除这段旅程") { deleting = true }.foregroundColor(.red).padding(.top, 15) }
                        }.padding(.horizontal).padding(.bottom, 30)
                    }
                }
                .navigationTitle(trip.title).navigationBarTitleDisplayMode(.inline)
                .navigationBarItems(trailing: Button(action: { sheet = .trip(trip) }) { Image(systemName: "square.and.pencil") }.accessibilityLabel("编辑旅程"))
            } else { Text("这段旅程已不存在").foregroundColor(.secondary) }
        }
        .onDisappear { replay.stop() }
        .sheet(item: $sheet) { TravelSheetContent(sheet: $0, onPickerFinished: { sheet = nil }).environmentObject(store) }
        .alert(isPresented: $deleting) {
            Alert(title: Text("删除整段旅程？"), message: Text("这段路线、App 内的照片副本和日记将一并删除，无法恢复。系统相册原图不受影响。"), primaryButton: .destructive(Text("删除")) { if store.deleteTrip(tripID) { presentation.wrappedValue.dismiss() } }, secondaryButton: .cancel(Text("取消")))
        }
    }
}

struct SettingsScreen: View {
    @AppStorage("mapAlignment") private var alignmentRaw = MapAlignment.automatic.rawValue
    @EnvironmentObject var store: TravelStore
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("照片"), footer: Text("自动关联按照旅程的起止时间查找可访问的照片。无定位照片可以手动放到地图上。")) {
                    Toggle("自动关联旅途照片", isOn: Binding(get: { store.automaticPhotos }, set: { store.setAutomaticPhotos($0) }))
                    Text(store.photoAccessDescription).font(.caption).foregroundColor(.secondary)
                    if store.photos.authorization == .limited { Button("调整允许访问的照片") { manageLimitedPhotos() } }
                    Button("打开系统权限设置") { store.openSettings() }
                }
                Section(header: Text("地图对齐"), footer: Text("默认按地点自动对齐。若路线与蓝色定位点整体错位，可切换模式比较；沿海、边境或不同地图服务下可能需要手动选择。已有路线会随设置重新显示。")) {
                    Picker("对齐方式", selection: $alignmentRaw) {
                        Text("自动").tag(MapAlignment.automatic.rawValue)
                        Text("大陆地图").tag(MapAlignment.mainland.rawValue)
                        Text("原始坐标").tag(MapAlignment.original.rawValue)
                    }
                }
                Section(header: Text("记录与离线使用")) {
                    Label("记录时支持锁屏和切换 App", systemImage: "location.fill")
                    Text("暂停会停止定位。强制关闭 App 或重启手机会中断记录，重新打开后可以继续。").font(.footnote).foregroundColor(.secondary)
                    Text("没有网络也能记录、写日记和查看已保存照片。地图底图需要网络或系统已有缓存。").font(.footnote).foregroundColor(.secondary)
                }
                Section(header: Text("本机保存")) {
                    Text("已保存 \(store.trips.count) 段旅程")
                    Text("路线、日记和照片副本保存在这台手机的应用数据中。删除系统相册原图不会删除已导入的照片副本。").font(.footnote).foregroundColor(.secondary)
                    Text("更新时保留应用数据。卸载 App 或清除其数据会失去这些回忆。").font(.footnote).foregroundColor(.secondary)
                }
                Section(header: Text("关于")) {
                    HStack { Text("旅迹"); Spacer(); Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "").foregroundColor(.secondary) }
                    Text("走过的路，看过的风景，写下的心情。").foregroundColor(.secondary)
                }
            }.navigationTitle("设置")
        }.navigationViewStyle(StackNavigationViewStyle())
    }
    private func manageLimitedPhotos() {
        guard var controller = UIApplication.shared.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return }
        while let presented = controller.presentedViewController { controller = presented }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: controller)
    }
}
