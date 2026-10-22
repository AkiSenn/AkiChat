import SwiftUI

enum Theme {
    static let accent = Color(red: 0.22, green: 0.38, blue: 0.91)
    static let background = Color(UIColor.systemGroupedBackground)
    static let card = Color(UIColor.secondarySystemGroupedBackground)
}
struct Card<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) { content }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card).cornerRadius(20)
            .shadow(color: Color.black.opacity(0.025), radius: 10, y: 4)
    }
}
struct IconButton: View {
    var symbol: String
    var label: String
    var action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 19, weight: .medium))
            .frame(width: 44, height: 44).background(Theme.card).clipShape(Circle()) }
            .accessibilityLabel(label)
    }
}
