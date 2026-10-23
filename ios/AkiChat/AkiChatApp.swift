import SwiftUI

@main
struct AkiChatApp: App {
    @StateObject private var store = AppStore()
    init() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor { $0.userInterfaceStyle == .dark ? .black : .systemGroupedBackground }
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
    }
    var body: some Scene {
        WindowGroup {
            ChatView().environmentObject(store).accentColor(Theme.accent)
                .preferredColorScheme(store.settings.appearance == .automatic ? nil :
                    (store.settings.appearance == .dark ? .dark : .light))
        }
    }
}
