import SwiftUI

@main
struct TravelRecorderApp: App {
    @UIApplicationDelegateAdaptor(TravelAppDelegate.self) private var appDelegate
    @StateObject private var store = TravelStore()
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = 0
    @State private var reminderNavigationID = UUID()
    @AppStorage(AppLanguage.key) private var language = ""
    @AppStorage(AppLanguage.completedKey) private var welcomeCompleted = false
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
            Group {
            if AppLanguage.needsWelcome(language: language, completed: welcomeCompleted) {
                WelcomeScreen { welcomeCompleted = true }
            } else {
            TravelTabs(selectedTab: $selectedTab).edgesIgnoringSafeArea(.all).id(reminderNavigationID)
            }
            }
            .environment(\.locale, Locale(identifier: language.isEmpty ? "zh-Hans" : language))
            .id(language)
            .environmentObject(store)
            .accentColor(.blue)
            .onReceive(ReminderRouter.shared.$tripID) { if $0 != nil { selectedTab = 0; reminderNavigationID = UUID() } }
            .onChange(of: scenePhase) { phase in if phase == .active { store.foreground() } }
            .overlay(Group {
                if let message = store.errorMessage {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L("需要处理一下")).font(.headline)
                        Text(L(message)).font(.subheadline)
                        Button(L("知道了")) { store.errorMessage = nil }
                    }.padding().frame(maxWidth: .infinity, alignment: .leading).background(Color(UIColor.secondarySystemBackground)).cornerRadius(12).shadow(radius: 8).padding()
                }
            }, alignment: .top)
        }
    }
}
