import SwiftUI

struct ChatTimelineView: View {
    @ObservedObject var presentation: ChatPresentation
    let fontSize: Double
    var onRetry: (UUID) -> Void
    var onEdit: (Message) -> Void
    let welcome: AnyView
    var character: CharacterIdentity? = nil
    var greetingID: UUID? = nil
    @StateObject private var follow = ScrollFollowController()
    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        if presentation.rows.isEmpty { welcome }
                        ForEach(presentation.rows) { cell in
                            LiveMessageRow(cell: cell, fontSize: fontSize, onRetry: onRetry, onEdit: onEdit, character: character, greetingID: greetingID).id(cell.id)
                        }
                        Color.clear.frame(height: 1).id("latest")
                    }.padding(20).background(ScrollMetricsReader(controller: follow))
                }
                .onAppear { follow.resume(); DispatchQueue.main.async { proxy.scrollTo("latest", anchor: .bottom) } }
                .onChange(of: presentation.sessionID) { _ in follow.resume(); proxy.scrollTo("latest", anchor: .bottom) }
                .onChange(of: presentation.scrollRequest) { _ in follow.resume(); proxy.scrollTo("latest", anchor: .bottom) }
                if !follow.following {
                    IconButton(symbol: "arrow.down", label: "返回最新消息") {
                        follow.resume(); withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo("latest", anchor: .bottom) }
                    }.padding(16)
                }
            }
        }
    }
}

private struct LiveMessageRow: View {
    @ObservedObject var cell: MessageCell
    let fontSize: Double
    var onRetry: (UUID) -> Void
    var onEdit: (Message) -> Void
    var character: CharacterIdentity?
    var greetingID: UUID?
    var body: some View {
        MessageRow(message: cell.message, fontSize: fontSize, isActive: cell.message.state == .generating,
                   onRetry: { onRetry(cell.id) }, onEdit: { onEdit(cell.message) }, character: character, greetingID: greetingID).equatable()
    }
}
