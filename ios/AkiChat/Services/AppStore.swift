import Foundation
import Combine
import UIKit

/// All published state is mutated on main; database work runs serially off main.
final class AppStore: ObservableObject {
    @Published private(set) var conversations: [Conversation] = []
    @Published private(set) var providers: [Provider] = []
    @Published private(set) var settings = AppSettings()
    @Published private(set) var selectedID: UUID?
    @Published private(set) var isGenerating = false
    @Published private(set) var renderRevision = 0
    @Published var notice: String?
    private var database: LocalDatabase?
    private let disk = DispatchQueue(label: "app.akichat.persistence", qos: .utility)
    private var transport: ChatTransport?
    private var generationID: UUID?
    private var saveWork: DispatchWorkItem?
    private var lastCheckpoint = Date.distantPast
    private var lifecycle: AnyCancellable?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    var current: Conversation? { conversations.first { $0.id == selectedID } }
    var provider: Provider? { providers.first { $0.id == current?.providerID } }
    var messages: [Message] { current?.messages ?? [] }
    var draft: String { current?.draft ?? "" }
    var draftImages: [Attachment] { current?.draftImages ?? [] }
    var thinking: Bool { current?.thinking ?? true }
    var effort: ReasoningEffort { current?.effort ?? .high }
    var composerHeight: CGFloat {
        let width = max(180, UIScreen.main.bounds.width - 114)
        let rect = ((draft.isEmpty ? " " : draft) as NSString).boundingRect(with: CGSize(width: width, height: 1000), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: UIFont.systemFont(ofSize: 16)], context: nil)
        return min(140, max(42, ceil(rect.height) + 20))
    }
    init() {
        do {
            let db = try LocalDatabase()
            // Decode everything before enabling writes; never overwrite an unreadable store.
            providers = try db.load("providers.v1", as: [Provider].self) ?? [.deepSeek]
            settings = try db.load("settings.v1", as: AppSettings.self) ?? AppSettings()
            conversations = try db.load("conversations.v1", as: [Conversation].self) ?? []
            for i in conversations.indices {
                for j in conversations[i].messages.indices where conversations[i].messages[j].state == .generating {
                    conversations[i].messages[j].state = .stopped
                }
            }
            database = db
            if providers.isEmpty { providers = [.deepSeek] }
            selectedID = conversations.sorted { $0.updatedAt > $1.updatedAt }.first?.id
            if conversations.isEmpty { newConversation() }
        } catch {
            notice = "本地数据读取失败，已暂停持久化以保护原记录。请导出当前内容后重新启动。\n\(error.localizedDescription)"
            providers = [.deepSeek]; conversations = [Conversation(providerID: providers[0].id)]; selectedID = conversations[0].id
        }
        lifecycle = NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification).sink { [weak self] _ in
            guard let self = self else { return }
            self.backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Save conversation") { [weak self] in self?.endBackgroundTask() }
            self.stop(); self.persist(immediate: true)
            self.disk.async { DispatchQueue.main.async { self.endBackgroundTask() } }
        }
    }
    private func endBackgroundTask() {
        if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask); backgroundTask = .invalid }
    }
    private func mutate(_ action: (inout Conversation) -> Void) {
        guard let i = conversations.firstIndex(where: { $0.id == selectedID }) else { return }
        action(&conversations[i]); renderRevision += 1
    }
    func setDraft(_ value: String) { mutate { $0.draft = value }; persist() }
    func setThinking(_ value: Bool) { mutate { $0.thinking = value }; persist() }
    func setEffort(_ value: ReasoningEffort) { mutate { $0.effort = value }; persist() }
    func updateSetting<T>(_ path: WritableKeyPath<AppSettings, T>, _ value: T) { settings[keyPath: path] = value; persist() }
    func newConversation() {
        stop()
        guard let p = providers.first else { return }
        let c = Conversation(providerID: provider?.id ?? p.id)
        conversations.insert(c, at: 0); selectedID = c.id; renderRevision += 1; persist(immediate: true)
    }
    func selectConversation(_ id: UUID) { stop(); selectedID = id; renderRevision += 1 }
    func selectProvider(_ id: UUID) { guard !isGenerating else { return }; mutate { $0.providerID = id }; persist() }
    func rename(_ id: UUID, title: String) {
        guard let i = conversations.firstIndex(where: { $0.id == id }) else { return }
        let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty { conversations[i].title = String(value.prefix(100)); persist() }
    }
    func deleteConversation(_ id: UUID) {
        if id == selectedID { stop() }
        conversations.removeAll { $0.id == id }
        if id == selectedID { selectedID = conversations.first?.id }
        if conversations.isEmpty { newConversation() }
        persist(immediate: true)
    }
    func clearCurrent() { stop(); mutate { $0.messages = []; $0.draft = ""; $0.draftImages = [] }; persist(immediate: true) }
    func clearAll() { stop(); conversations = []; newConversation(); persist(immediate: true) }
    func addImage(_ image: Attachment) {
        guard draftImages.count < 4 else { notice = "每条消息最多添加 4 张图片"; return }
        mutate { $0.draftImages.append(image) }; persist()
    }
    func removeImage(_ id: UUID) { mutate { $0.draftImages.removeAll { $0.id == id } }; persist() }
    func send() {
        guard !isGenerating else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !draftImages.isEmpty else { return }
        // Validate configuration before clearing the persisted draft.
        do { _ = try configuredRequest(probe: true) } catch { notice = error.localizedDescription; return }
        let user = Message(role: .user, content: text, images: draftImages)
        mutate {
            if $0.messages.isEmpty { $0.title = String((text.isEmpty ? "图片对话" : text).prefix(30)) }
            $0.messages.append(user); $0.draft = ""; $0.draftImages = []; $0.updatedAt = Date()
        }
        beginGeneration()
    }
    func editAndResend(_ id: UUID, text: String) {
        stop()
        guard let index = messages.firstIndex(where: { $0.id == id && $0.role == .user }) else { return }
        mutate {
            $0.messages[index].content = text
            $0.messages.removeSubrange((index + 1)..<$0.messages.count)
            $0.updatedAt = Date()
        }
        beginGeneration()
    }
    func regenerate(from id: UUID) {
        stop()
        guard let index = messages.firstIndex(where: { $0.id == id }),
              let userIndex = messages[...index].lastIndex(where: { $0.role == .user }) else { return }
        mutate { $0.messages.removeSubrange((userIndex + 1)..<$0.messages.count) }
        beginGeneration()
    }
    private func configuredRequest(probe: Bool = false) throws -> URLRequest {
        guard let p = provider, var c = current else { throw AppError.validation("请先选择模型") }
        if probe { c.messages.append(Message(role: .user, content: draft, images: draftImages)) }
        return try RequestBuilder.make(provider: p, key: try KeychainStore.read(p.apiKeyReference) ?? "", conversation: c, settings: settings, stream: settings.streaming && p.supportsStreaming)
    }
    private func beginGeneration() {
        let answer = Message(role: .assistant, content: "", state: .generating)
        mutate { $0.messages.append(answer) }
        persist(immediate: true)
        lastCheckpoint = Date()
        do {
            let request = try configuredRequest()
            let stream = settings.streaming && provider?.supportsStreaming == true
            let token = UUID(); generationID = token; isGenerating = true
            let transport = ChatTransport(); self.transport = transport
            transport.start(request: request, stream: stream, onUpdate: { [weak self] snapshot in
                guard let self = self, self.generationID == token else { return }
                self.updateAnswer(answer.id, snapshot: snapshot)
                if Date().timeIntervalSince(self.lastCheckpoint) >= 2 {
                    self.lastCheckpoint = Date(); self.persist(immediate: true)
                }
            }, completion: { [weak self] result in
                guard let self = self, self.generationID == token else { return }
                switch result {
                case .success(let snapshot): self.updateAnswer(answer.id, snapshot: snapshot)
                    self.mutate { c in if let i = c.messages.firstIndex(where: { $0.id == answer.id }) { c.messages[i].state = .complete } }
                case .failure(let error):
                    self.mutate { c in
                        if let i = c.messages.firstIndex(where: { $0.id == answer.id }) {
                            c.messages[i].state = .failed
                            c.messages[i].error = (error as? URLError)?.code == .timedOut ? "请求超时，已保留消息，请重试。" : error.localizedDescription
                        }
                    }
                }
                self.generationID = nil; self.isGenerating = false; self.transport = nil; self.persist(immediate: true)
            })
        } catch {
            mutate { c in if let i = c.messages.firstIndex(where: { $0.id == answer.id }) { c.messages[i].state = .failed; c.messages[i].error = error.localizedDescription } }
            persist(immediate: true)
        }
    }
    private func updateAnswer(_ id: UUID, snapshot: ChatSnapshot) {
        mutate { c in
            if let i = c.messages.firstIndex(where: { $0.id == id }) {
                c.messages[i].content = snapshot.content; c.messages[i].reasoning = snapshot.reasoning; c.messages[i].usage = snapshot.usage
            }
        }
    }
    func stop() {
        guard isGenerating else { return }
        generationID = nil; transport?.cancel(); transport = nil; isGenerating = false
        mutate { c in if let i = c.messages.lastIndex(where: { $0.state == .generating }) { c.messages[i].state = .stopped } }
        persist(immediate: true)
    }
    func saveProvider(_ value: Provider, newKey: String?, deleteKey: Bool = false) throws {
        _ = try Endpoint.chatURL(value.baseURL)
        guard !value.name.isEmpty, !value.modelID.isEmpty, !value.displayName.isEmpty else { throw AppError.validation("请填写名称与模型 ID") }
        guard value.customHeaders.keys.allSatisfy(RequestBuilder.safeHeader) else { throw AppError.validation("自定义 Header 只能包含非敏感字段") }
        guard database != nil else { throw AppError.storage("数据库不可用，无法保存配置") }
        if deleteKey { try KeychainStore.delete(value.apiKeyReference) }
        else if let key = newKey, !key.isEmpty { try KeychainStore.write(key.trimmingCharacters(in: .whitespacesAndNewlines), reference: value.apiKeyReference) }
        var next = providers
        if let i = next.firstIndex(where: { $0.id == value.id }) { next[i] = value } else { next.append(value) }
        providers = next; persist(immediate: true)
    }
    func deleteProvider(_ id: UUID) throws {
        guard providers.count > 1 else { throw AppError.validation("请至少保留一个服务商") }
        stop()
        guard let value = providers.first(where: { $0.id == id }), database != nil else { return }
        let next = providers.filter { $0.id != id }
        try KeychainStore.delete(value.apiKeyReference)
        providers = next
        for i in conversations.indices where conversations[i].providerID == id { conversations[i].providerID = next[0].id }
        persist(immediate: true)
    }
    func importArchive(_ data: Data) throws {
        let incoming = try ExportService.decode(data)
        guard let p = providers.first else { return }
        for var c in incoming {
            // Import as copies, preserving local records and binding unknown providers locally.
            c.id = UUID()
            if !providers.contains(where: { $0.id == c.providerID }) { c.providerID = p.id }
            for j in c.messages.indices where c.messages[j].state == .generating { c.messages[j].state = .stopped }
            conversations.append(c)
        }
        persist(immediate: true)
        notice = "已导入 \(incoming.count) 个会话。密钥和服务商不会从聊天文件导入。"
    }
    private func persist(immediate: Bool = false) {
        saveWork?.cancel()
        guard let database = database else { return }
        let conversations = conversations, providers = providers, settings = settings
        let work = DispatchWorkItem { [weak self] in
            do {
                try database.save(conversations, key: "conversations.v1")
                try database.save(providers, key: "providers.v1")
                try database.save(settings, key: "settings.v1")
            } catch { DispatchQueue.main.async { self?.notice = "本地保存失败，请及时导出备份。" } }
        }
        saveWork = work
        if immediate { disk.async(execute: work) } else { disk.asyncAfter(deadline: .now() + 0.7, execute: work) }
    }
}
