import SwiftUI

@main
struct TravelRecorderApp: App {
    @StateObject private var store = TravelStore()
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = 0
    init() {
        let navigation = UINavigationBarAppearance()
        navigation.configureWithDefaultBackground()
        navigation.shadowColor = .clear
        navigation.shadowImage = UIImage()
        UINavigationBar.appearance().standardAppearance = navigation
        UINavigationBar.appearance().compactAppearance = navigation
        UINavigationBar.appearance().scrollEdgeAppearance = navigation
        let tabs = UITabBarAppearance()
        tabs.configureWithDefaultBackground()
        tabs.shadowColor = .clear
        tabs.shadowImage = UIImage()
        UITabBar.appearance().standardAppearance = tabs
    }
    var body: some Scene {
        WindowGroup {
            TabView(selection: $selectedTab) {
                RecordingScreen(isVisible: selectedTab == 0).tabItem { Label("记录", systemImage: "map") }.tag(0)
                MemoriesScreen().tabItem { Label("回忆", systemImage: "book.closed") }.tag(1)
                SettingsScreen().tabItem { Label("设置", systemImage: "gearshape") }.tag(2)
            }
            .environmentObject(store)
            .accentColor(.blue)
            .onChange(of: scenePhase) { phase in if phase == .active { store.foreground() } }
            .overlay(Group {
                if let message = store.errorMessage {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("需要处理一下").font(.headline)
                        Text(message).font(.subheadline)
                        Button("知道了") { store.errorMessage = nil }
                    }.padding().frame(maxWidth: .infinity, alignment: .leading).background(Color(UIColor.secondarySystemBackground)).cornerRadius(12).shadow(radius: 8).padding()
                }
            }, alignment: .top)
        }
    }
}
