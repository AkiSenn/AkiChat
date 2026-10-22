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
    @Published private(set) var catalogs: [ModelCatalog] = []
    @Published private(set) var refreshingModels: Set<UUID> = []
    @Published private(set) var modelErrors: [UUID: String] = [:]
    @Published private(set) var generationStatus = ""
    @Published var notice: String?
    private var database: LocalDatabase?
    private let disk = DispatchQueue(label: "app.akichat.persistence", qos: .utility)
    private var run: ChatRun?
    private var compression: Cancellable?
    private var modelRequests: [UUID: JSONHTTPClient] = [:]
    private var generationID: UUID?
    private var saveWork: DispatchWorkItem?
    private var lastCheckpoint = Date.distantPast
    private var lifecycle: AnyCancellable?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    var current: Conversation? { conversations.first { $0.id == selectedID } }
    var provider: Provider? {
        guard let base = providers.first(where: { $0.id == current?.providerID }) else { return nil }
        let id = current?.options.modelID ?? base.modelID
        return models(for: base.id).first(where: { $0.id == id })?.apply(to: base) ?? base
    }
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
    init(database suppliedDatabase: LocalDatabase? = nil) {
        do {
            let db = try suppliedDatabase ?? LocalDatabase()
            // Decode everything before enabling writes; never overwrite an unreadable store.
            providers = try db.load("providers.v1", as: [Provider].self) ?? [.deepSeek, .openAI]
            catalogs = try db.load("catalogs.v2", as: [ModelCatalog].self) ?? []
            settings = try db.load("settings.v1", as: AppSettings.self) ?? AppSettings()
            if settings.advanced == nil { settings.options = settings.options }
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
        persist()
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
    func updateConversationOption<T>(_ path: WritableKeyPath<ConversationOptions, T>, _ value: T) { mutate { $0.options[keyPath: path] = value }; persist() }
    func updateGlobalOption<T>(_ path: WritableKeyPath<GlobalOptions, T>, _ value: T) { settings.options[keyPath: path] = value; persist() }
    var contextPlan: ContextPlan? {
        guard let p = provider, let c = current else { return nil }
        return try? ContextManager.plan(provider: p, conversation: c, settings: settings, tools: c.options.toolsEnabled && p.options.supportsTools)
    }
    var effectivePrompt: String {
        guard let p = provider, let c = current else { return "" }
        return PromptResolver.effective(provider: p, conversation: c, settings: settings)
    }
    func updateSetting<T>(_ path: WritableKeyPath<AppSettings, T>, _ value: T) { settings[keyPath: path] = value; persist() }
    func newConversation() {
        stop()
        guard let p = providers.first else { return }
        let c = Conversation(providerID: provider?.id ?? p.id)
        conversations.insert(c, at: 0); selectedID = c.id; renderRevision += 1; persist(immediate: true)
    }
    func selectConversation(_ id: UUID) { stop(); selectedID = id; renderRevision += 1 }
    func selectProvider(_ id: UUID) { guard !isGenerating else { return }; mutate { $0.providerID = id; $0.options.modelID = nil }; persist() }
    func selectModel(providerID: UUID, modelID: String) {
        guard !isGenerating else { return }
        mutate { $0.providerID = providerID; $0.options.modelID = modelID; $0.options.context.calibration = nil }; persist()
    }
    func models(for providerID: UUID) -> [ModelRecord] {
        if let catalog = catalogs.first(where: { $0.id == providerID }), !catalog.models.isEmpty { return catalog.models }
        guard let p = providers.first(where: { $0.id == providerID }), !p.modelID.isEmpty else { return [] }
        var m = ModelRecord(id: p.modelID, name: p.displayName)
        m.discovered = ModelCapabilities(vision: p.supportsVision, thinking: p.supportsThinking, tools: p.options.supportsTools, streaming: p.supportsStreaming, systemPrompt: p.options.supportsSystem, prefix: p.options.supportsPrefix)
        return [m]
    }
    func saveModel(_ model: ModelRecord, providerID: UUID) {
        var catalog = catalogs.first(where: { $0.id == providerID }) ?? ModelCatalog(id: providerID, models: models(for: providerID))
        if let index = catalog.models.firstIndex(where: { $0.id == model.id }) { catalog.models[index] = model }
        else { catalog.models.append(model) }
        replaceCatalog(catalog)
    }
    func deleteModel(_ id: String, providerID: UUID) {
        guard var c = catalogs.first(where: { $0.id == providerID }), c.models.first(where: { $0.id == id })?.manual == true else { return }
        c.models.removeAll { $0.id == id }; replaceCatalog(c)
        for i in conversations.indices where conversations[i].providerID == providerID && conversations[i].options.modelID == id { conversations[i].options.modelID = c.models.first?.id }
        persist(immediate: true)
    }
    private func replaceCatalog(_ value: ModelCatalog) {
        if let i = catalogs.firstIndex(where: { $0.id == value.id }) { catalogs[i] = value } else { catalogs.append(value) }
        persist(immediate: true)
    }
    func cancelModelRefresh(_ id: UUID) { modelRequests.removeValue(forKey: id)?.cancel(); refreshingModels.remove(id) }
    func refreshModels(_ id: UUID, onlyIfNeeded: Bool = false) {
        guard let p = providers.first(where: { $0.id == id }), !refreshingModels.contains(id) else { return }
        if onlyIfNeeded && (catalogs.first(where: { $0.id == id })?.syncedAt != nil || (try? KeychainStore.read(p.apiKeyReference)) == nil) { return }
        do {
            let request = try JSONHTTPClient.request(url: Endpoint.url(p.baseURL, path: p.options.modelsPath), key: KeychainStore.read(p.apiKeyReference) ?? "", timeout: p.options.timeout, headers: p.customHeaders)
            let client = JSONHTTPClient(); modelRequests[id] = client; refreshingModels.insert(id); modelErrors[id] = nil
            client.start(request) { [weak self] result in
                guard let self = self, self.modelRequests[id] === client else { return }
                self.modelRequests[id] = nil; self.refreshingModels.remove(id)
                do {
                    let fetched = try ModelDiscovery.parse(result.get(), provider: p)
                    guard !fetched.isEmpty else { throw AppError.validation("模型列表为空，已保留本地配置。") }
                    self.replaceCatalog(ModelCatalog(id: id, models: ModelDiscovery.merge(fetched, cached: self.models(for: id)), syncedAt: Date()))
                } catch { self.modelErrors[id] = error.localizedDescription }
            }
        } catch { modelErrors[id] = error.localizedDescription }
    }
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
        do {
            guard let p = provider, !p.modelID.isEmpty else { throw AppError.validation("请先选择模型") }
            _ = try JSONHTTPClient.request(url: Endpoint.chatURL(p.baseURL, path: p.options.chatPath), key: KeychainStore.read(p.apiKeyReference) ?? "")
            if !draftImages.isEmpty && !p.supportsVision { throw AppError.validation("当前模型不支持图片，请切换模型或移除附件。") }
        } catch { notice = error.localizedDescription; return }
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
    private func beginGeneration() {
        guard let p = provider, let c = current else { return }
        let token = UUID(); generationID = token; isGenerating = true; lastCheckpoint = Date()
        persist(immediate: true)
        if ContextManager.shouldCompress(provider: p, conversation: c, settings: settings, tools: c.options.toolsEnabled && p.options.supportsTools) {
            summarize(token: token, continueChat: true)
        } else { startRun(token: token) }
    }
    private func startRun(token: UUID) {
        guard generationID == token, let p = provider, let c = current else { return }
        do {
            let key = try KeychainStore.read(p.apiKeyReference) ?? ""
            let needsSearch = c.options.toolsEnabled && c.options.searchMode != .off
            var search: SearchProviderService?
            if needsSearch {
                guard p.options.supportsTools else { throw AppError.validation("当前模型不支持工具调用") }
                guard settings.options.externalConsent else { throw AppError.validation("请先在会话高级设置中同意外部搜索与额外摘要请求。") }
                let selected = providers.first { $0.id == settings.options.searchProviderID } ?? providers.first { $0.kind == .deepSeek && URL(string: $0.baseURL)?.host == "api.deepseek.com" }
                guard let source = selected, source.kind == .deepSeek, URL(string: source.baseURL)?.host == "api.deepseek.com",
                      let searchKey = try KeychainStore.read(source.apiKeyReference), !searchKey.isEmpty else { throw AppError.validation("请配置官方 DeepSeek 服务商密钥，用于 Search / Fetch。") }
                search = DeepSeekSearchService(key: searchKey)
            }
            let executor = BuiltInToolExecutor(options: c.options, search: search, count: settings.options.searchCount)
            let run = ChatRun(provider: p, key: key, conversation: c, settings: settings, executor: executor, canSearch: search != nil, update: { [weak self] messages, status in
                guard let self = self, self.generationID == token else { return }
                self.mutate { $0.messages = messages; $0.updatedAt = Date() }; self.generationStatus = status
                if Date().timeIntervalSince(self.lastCheckpoint) >= 2 { self.lastCheckpoint = Date(); self.persist(immediate: true) }
            }, completion: { [weak self] result in
                guard let self = self, self.generationID == token else { return }
                if case .success(let messages) = result, let actual = messages.last?.usage?.prompt_tokens,
                   let estimate = self.run?.lastPromptEstimate, estimate > 0 {
                    self.mutate { c in c.options.context.calibration = min(2, max(0.5, (c.options.context.calibration ?? 1) * Double(actual) / Double(estimate))) }
                }
                if case .failure(let error) = result, (error as? URLError)?.code != .cancelled { self.generationStatus = error.localizedDescription }
                self.isGenerating = false; self.generationID = nil; self.run = nil; self.persist(immediate: true)
            })
            self.run = run; run.start()
        } catch {
            mutate { $0.messages.append(Message(role: .assistant, content: "", state: .failed, error: error.localizedDescription)) }
            generationStatus = error.localizedDescription; isGenerating = false; generationID = nil; persist(immediate: true)
        }
    }
    func compressNow() {
        guard !isGenerating else { return }
        let token = UUID(); generationID = token; isGenerating = true
        summarize(token: token, continueChat: false)
    }
    private func summarize(token: UUID, continueChat: Bool) {
        guard generationID == token, let c = current else { return }
        do {
            guard settings.options.externalConsent else { throw AppError.validation("摘要会额外发送历史内容到所选模型并产生费用，请先在高级设置中启用同意开关。") }
            let p: Provider
            if let selected = c.options.context.summaryProviderID, let explicit = providers.first(where: { $0.id == selected }) {
                p = models(for: selected).first(where: { $0.id == (c.options.context.summaryModelID ?? explicit.modelID) })?.apply(to: explicit) ?? explicit
            }
            else if let selected = provider { p = selected }
            else { throw AppError.validation("请选择摘要模型") }
            generationStatus = "正在压缩上下文（原始历史保留）"
            compression = try SummaryService.generate(provider: p, key: KeychainStore.read(p.apiKeyReference) ?? "", conversation: c) { [weak self] result in
                guard let self = self, self.generationID == token else { return }
                self.compression = nil
                switch result {
                case .success(let version):
                    self.mutate { c in
                        if c.summaries == nil { c.summaries = [] }
                        c.summaries?.append(version); c.activeSummaryID = version.id
                        if !continueChat { c.options.context.strategy = .summary }
                    }
                    self.generationStatus = "摘要已保存"; self.persist(immediate: true)
                case .failure(let error): self.notice = "压缩失败，旧摘要和原始历史已保留。\n" + error.localizedDescription
                }
                if continueChat { self.startRun(token: token) }
                else { self.isGenerating = false; self.generationID = nil }
            }
        } catch {
            notice = error.localizedDescription
            if continueChat { startRun(token: token) }
            else { isGenerating = false; generationID = nil }
        }
    }
    func activateSummary(_ id: UUID?) { mutate { $0.activeSummaryID = id }; persist(immediate: true) }
    func rollbackSummary() {
        guard let c = current, let versions = c.summaries, let index = versions.firstIndex(where: { $0.id == c.activeSummaryID }) else { return }
        activateSummary(index > 0 ? versions[index - 1].id : nil)
    }
    func savePreset(_ value: PromptPreset) {
        if let i = settings.options.presets.firstIndex(where: { $0.id == value.id }) { settings.options.presets[i] = value }
        else { settings.options.presets.append(value) }
        persist(immediate: true)
    }
    func deletePreset(_ id: UUID) { settings.options.presets.removeAll { $0.id == id }; persist(immediate: true) }
    func importPresets(_ data: Data) throws {
        guard data.count <= 1024 * 1024 else { throw AppError.validation("预设文件不得超过 1 MiB") }
        let values = try JSONDecoder().decode([PromptPreset].self, from: data)
        guard values.count <= 100, values.allSatisfy({ !$0.name.isEmpty && $0.text.count <= 32000 }) else { throw AppError.validation("预设数量或长度超限") }
        for var value in values { value.id = UUID(); settings.options.presets.append(value) }
        persist(immediate: true)
    }
    func stop() {
        guard isGenerating else { return }
        run?.cancel(); compression?.cancel(); run = nil; compression = nil
        generationID = nil; isGenerating = false; generationStatus = "已停止"
        mutate { c in for i in c.messages.indices where c.messages[i].state == .generating { c.messages[i].state = .stopped } }
        persist(immediate: true)
    }
    func saveProvider(_ value: Provider, newKey: String?, deleteKey: Bool = false) throws {
        _ = try Endpoint.chatURL(value.baseURL)
        guard !value.name.isEmpty, !value.displayName.isEmpty else { throw AppError.validation("请填写服务商名称与显示名称") }
        guard value.customHeaders.keys.allSatisfy(RequestBuilder.safeHeader) else { throw AppError.validation("自定义 Header 只能包含非敏感字段") }
        guard database != nil else { throw AppError.storage("数据库不可用，无法保存配置") }
        if deleteKey { try KeychainStore.delete(value.apiKeyReference) }
        else if let key = newKey, !key.isEmpty { try KeychainStore.write(key.trimmingCharacters(in: .whitespacesAndNewlines), reference: value.apiKeyReference) }
        var next = providers
        if let i = next.firstIndex(where: { $0.id == value.id }) { next[i] = value } else { next.append(value) }
        providers = next; persist(immediate: true)
        if newKey?.isEmpty == false && !deleteKey { refreshModels(value.id) }
    }
    func deleteProvider(_ id: UUID) throws {
        guard providers.count > 1 else { throw AppError.validation("请至少保留一个服务商") }
        stop()
        cancelModelRefresh(id)
        guard let value = providers.first(where: { $0.id == id }), database != nil else { return }
        let next = providers.filter { $0.id != id }
        try KeychainStore.delete(value.apiKeyReference)
        providers = next
        for i in conversations.indices where conversations[i].providerID == id { conversations[i].providerID = next[0].id }
        persist(immediate: true)
    }
    func importArchive(_ data: Data) throws {
        let incoming = try ExportService.decode(data)
        for c in incoming {
            for image in c.messages.flatMap(\.images) + c.draftImages { try ImageService.validateImported(image) }
        }
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
        let conversations = conversations, providers = providers, settings = settings, catalogs = catalogs
        let work = DispatchWorkItem { [weak self] in
            do {
                try database.save(conversations, key: "conversations.v1")
                try database.save(providers, key: "providers.v1")
                try database.save(settings, key: "settings.v1")
                try database.save(catalogs, key: "catalogs.v2")
            } catch { DispatchQueue.main.async { self?.notice = "本地保存失败，请及时导出备份。" } }
        }
        saveWork = work
        if immediate { disk.async(execute: work) } else { disk.asyncAfter(deadline: .now() + 0.7, execute: work) }
    }
}
