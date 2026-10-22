import SwiftUI

@main
struct AkiChatApp: App {
    @StateObject private var store = AppStore()
    var body: some Scene {
        WindowGroup {
            ChatView().environmentObject(store).accentColor(Theme.accent)
                .preferredColorScheme(store.settings.appearance == .automatic ? nil :
                    (store.settings.appearance == .dark ? .dark : .light))
        }
    }
}
