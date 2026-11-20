import SwiftUI
import UIKit

/// UIKit owns selection and hit testing on iOS 14. Stable hosting controllers
/// preserve each tab's state without conditional TabView item reconstruction.
struct TravelTabs: UIViewControllerRepresentable {
    @Binding var selectedTab: Int
    @EnvironmentObject private var store: TravelStore
    @Environment(\.locale) private var locale

    func makeUIViewController(context: Context) -> TravelTabController {
        TravelTabController(store: store, locale: locale, selection: selectedTab) { selectedTab = $0 }
    }
    func updateUIViewController(_ controller: TravelTabController, context: Context) {
        controller.onSelection = { selectedTab = $0 }
        controller.select(selectedTab)
    }
}

final class TravelTabController: UITabBarController, UITabBarControllerDelegate {
    var onSelection: (Int) -> Void
    private let store: TravelStore
    private let locale: Locale
    private let recording: UIHostingController<AnyView>
    private var recordingVisible: Bool

    init(store: TravelStore, locale: Locale, selection: Int, onSelection: @escaping (Int) -> Void) {
        self.store = store
        self.locale = locale
        self.onSelection = onSelection
        recordingVisible = selection == 0
        recording = UIHostingController(rootView: AnyView(RecordingScreen(isVisible: selection == 0)
            .environmentObject(store).environment(\.locale, locale)))
        super.init(nibName: nil, bundle: nil)
        let memories = UIHostingController(rootView: MemoriesScreen().environmentObject(store).environment(\.locale, locale))
        let settings = UIHostingController(rootView: SettingsScreen().environmentObject(store).environment(\.locale, locale))
        let screens: [UIViewController] = [recording, memories, settings]
        for (index, item) in [(L("记录"), "map"), (L("回忆"), "book.closed"), (L("设置"), "gearshape")].enumerated() {
            screens[index].tabBarItem = UITabBarItem(title: item.0, image: UIImage(systemName: item.1), tag: index)
            screens[index].tabBarItem.accessibilityIdentifier = "travel.tab.\(index)"
        }
        setViewControllers(screens, animated: false)
        delegate = self
        select(selection)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func select(_ index: Int) {
        guard (0..<3).contains(index) else { return }
        if selectedIndex != index { selectedIndex = index }
        updateRecordingVisibility(index == 0)
    }
    private func updateRecordingVisibility(_ visible: Bool) {
        guard recordingVisible != visible else { return }
        recordingVisible = visible
        recording.rootView = AnyView(RecordingScreen(isVisible: visible)
            .environmentObject(store).environment(\.locale, locale))
    }
    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        updateRecordingVisibility(selectedIndex == 0)
        onSelection(selectedIndex)
    }
}
