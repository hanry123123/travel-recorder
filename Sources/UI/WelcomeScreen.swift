import SwiftUI

/// Choosing a language is the only first-run step. Tips live on real controls.
struct WelcomeScreen: View {
    @AppStorage(AppLanguage.key) private var language = ""
    let onFinish: () -> Void
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Spacer(minLength: 70)
                Image(systemName: "map.fill").font(.system(size: 54)).foregroundColor(.blue).padding(.bottom, 14)
                VStack(spacing: 8) {
                    Text("选择语言").font(.title).bold()
                    Text("Choose language").font(.title2).foregroundColor(.secondary)
                }
                Text("旅迹 · Travel Recorder").font(.subheadline).foregroundColor(.secondary).padding(.bottom, 22)
                languageButton("中文", value: "zh-Hans")
                languageButton("English", value: "en")
                VStack(spacing: 4) {
                    Text("稍后可在设置中更改")
                    Text("You can change this later in Settings.")
                }.font(.caption).foregroundColor(.secondary).padding(.top, 14)
                Spacer(minLength: 40)
            }.padding(28).frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
        }.background(Color(UIColor.systemBackground).edgesIgnoringSafeArea(.all))
    }
    private func languageButton(_ title: String, value: String) -> some View {
        Button(action: { language = value; onFinish() }) {
            Text(title).font(.headline).frame(maxWidth: .infinity, minHeight: 54)
                .background(Color.blue.opacity(0.08)).cornerRadius(12)
        }
    }
}
