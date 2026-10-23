import Foundation
import Combine

final class MessageCell: ObservableObject, Identifiable {
    let id: UUID
    @Published private(set) var message: Message
    init(_ message: Message) { id = message.id; self.message = message }
    func update(_ value: Message) { if message != value { message = value } }
}

/// Stable row objects: token snapshots notify only the current row, not the session list.
final class ChatPresentation: ObservableObject {
    @Published private(set) var rows: [MessageCell] = []
    @Published private(set) var sessionID: UUID?
    @Published private(set) var scrollRequest = 0
    private var cells: [UUID: MessageCell] = [:]
    private var ids: [UUID] = []
    func select(_ id: UUID?, messages: [Message]) {
        if sessionID != id { cells = [:]; ids = []; sessionID = id }
        reconcile(messages)
    }
    func receive(_ messages: [Message]) {
        if messages.count == ids.count, let last = messages.last, last.id == ids.last {
            cells[last.id]?.update(last)
        } else { reconcile(messages) }
    }
    func reconcile(_ messages: [Message]) {
        var next: [UUID: MessageCell] = [:]
        for message in messages where message.role != .tool {
            let cell = cells[message.id] ?? MessageCell(message)
            cell.update(message); next[message.id] = cell
        }
        let visible = messages.filter { $0.role != .tool }.compactMap { next[$0.id] }
        if rows.map(\.id) != visible.map(\.id) { rows = visible }
        cells = next; ids = messages.map(\.id)
    }
    func requestLatest() { scrollRequest += 1 }
}

/// Typing is deliberately independent from AppStore.objectWillChange.
final class ComposerState: ObservableObject {
    @Published var text = ""
    @Published var images: [Attachment] = []
    func load(_ conversation: Conversation?) {
        if text != (conversation?.draft ?? "") { text = conversation?.draft ?? "" }
        if images != (conversation?.draftImages ?? []) { images = conversation?.draftImages ?? [] }
    }
}

enum ProviderNaming {
    static let legacyFlashName = "DeepSeek V4.1 Flash 1017"
    static func normalize(_ value: Provider) -> Provider {
        var p = value
        if p.kind == .deepSeek {
            if p.name == legacyFlashName { p.name = "DeepSeek" }
            if p.displayName == legacyFlashName { p.displayName = p.modelID }
        }
        return p
    }
}
