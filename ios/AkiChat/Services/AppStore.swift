import Foundation
import Combine
import UIKit

/// All published state is mutated on main; database work runs serially off main.
final class AppStore: ObservableObject {
    @Published private(set) var conversations: [Conversation] = [] { didSet { dirtyRecords.insert(.conversations) } }
    @Published private(set) var providers: [Provider] = [] { didSet { dirtyRecords.insert(.providers); modelListCache.invalidate() } }
    @Published private(set) var settings = AppSettings() { didSet { dirtyRecords.insert(.settings) } }
    @Published private(set) var selectedID: UUID?
    @Published private(set) var isGenerating = false
    @Published private(set) var renderRevision = 0
    @Published private(set) var catalogs: [ModelCatalog] = [] { didSet { dirtyRecords.insert(.catalogs); modelListCache.invalidate() } }
    @Published private(set) var refreshingModels: Set<UUID> = []
    @Published private(set) var modelIssues: [UUID: ModelDiscoveryIssue] = [:]
    var modelErrors: [UUID: String] { modelIssues.mapValues(\.message) }
    @Published private(set) var searchCredentialAvailable = false
    @Published private(set) var generationStatus = ""
    @Published var notice: String?
    let chat = ChatPresentation()
    let composer = ComposerState()
    @Published private(set) var provider: Provider?
    var providerName: String { providers.first { $0.id == current?.providerID }?.name ?? "ѡ�������" }
    var selectedModelLabel: String {
        let id = current?.options.modelID ?? providers.first { $0.id == current?.providerID }?.modelID ?? ""
        return id.isEmpty ? "ѡ��ģ��" : id
    }
    private enum RecordKey: String, CaseIterable {
        case conversations = "conversations.v1", providers = "providers.v1", settings = "settings.v1", catalogs = "catalogs.v2"
    }
    private var dirtyRecords = Set(RecordKey.allCases)
    private var database: RecordDatabase?
    private let modelListCache = ModelListCache()
    private let disk = DispatchQueue(label: "app.akichat.persistence", qos: .utility)
    private var run: ChatRun?
    private var compression: Cancellable?
    private var modelRequests: [UUID: JSONHTTPClient] = [:]
    private var modelOperations: [UUID: BlockOperation] = [:]
    private var catalogVersions: [UUID: Int] = [:]
    private let catalogWorker: CatalogWorker
    private let modelConfiguration: () -> URLSessionConfiguration
    private let searchFactory: (String) -> SearchProviderService
    private let senderFactory: () -> ChatRequestSending
    private var generationID: UUID?
    private var saveWork: DispatchWorkItem?
    private var lastCheckpoint = Date.distantPast
    private var lifecycle: AnyCancellable?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    var current: Conversation? { conversations.first { $0.id == selectedID } }
    private func resolveProvider() {
        guard let base = providers.first(where: { $0.id == current?.providerID }) else { provider = nil; return }
        let id = current?.options.modelID ?? base.modelID
        provider = models(for: base.id).first(where: { $0.id == id })?.apply(to: base)
    }
    var messages: [Message] { current?.messages ?? [] }
    var draft: String { composer.text }
    var draftImages: [Attachment] { composer.images }
    var thinking: Bool { current?.thinking ?? true }
    var effort: ReasoningEffort { current?.effort ?? .high }
    init(database suppliedDatabase: RecordDatabase? = nil, modelConfiguration: @escaping () -> URLSessionConfiguration = { .ephemeral }, senderFactory: @escaping () -> ChatRequestSending = { ChatTransport() }, searchFactory: @escaping (String) -> SearchProviderService = { DeepSeekSearchService(key: $0) }, catalogWorker: CatalogWorker = CatalogWorker()) {
        self.modelConfiguration = modelConfiguration; self.senderFactory = senderFactory; self.searchFactory = searchFactory; self.catalogWorker = catalogWorker
        do {
            let db: RecordDatabase
            if let supplied = suppliedDatabase { db = supplied }
            else {
            #if DEBUG
                db = try Self.uiFixtureDatabase() ?? LocalDatabase()
            #else
                db = try LocalDatabase()
            #endif
            }
            // Decode everything before enabling writes; never overwrite an unreadable store.
            providers = (try db.load("providers.v1", as: [Provider].self) ?? [.deepSeek, .openAI]).map(ProviderNaming.normalize)
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
            notice = "�������ݶ�ȡʧ�ܣ�����ͣ�־û��Ա���ԭ��¼���뵼����ǰ���ݺ�����������\n\(error.localizedDescription)"
            providers = [.deepSeek]; conversations = [Conversation(providerID: providers[0].id)]; selectedID = conversations[0].id
        }
        composer.load(current); chat.select(selectedID, messages: messages); resolveProvider(); refreshSearchCredential()
        lifecycle = NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification).sink { [weak self] _ in
            guard let self = self else { return }
            self.backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Save conversation") { [weak self] in self?.endBackgroundTask() }
            self.stop(); self.flushPersistence { self.endBackgroundTask() }
        }
        persist()
    }
    private func endBackgroundTask() {
        if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask); backgroundTask = .invalid }
    }
    private func mutate(messagesChanged: Bool = true, _ action: (inout Conversation) -> Void) {
        guard let i = conversations.firstIndex(where: { $0.id == selectedID }) else { return }
        let oldProvider = conversations[i].providerID, oldModel = conversations[i].options.modelID
        action(&conversations[i]); renderRevision += 1
        if messagesChanged { chat.reconcile(conversations[i].messages) }
        if conversations[i].providerID != oldProvider || conversations[i].options.modelID != oldModel { resolveProvider() }
    }
    func setDraft(_ value: String) {
        composer.text = value; dirtyRecords.insert(.conversations); persist()
    }
    private func commitDraft() {
        guard let i = conversations.firstIndex(where: { $0.id == selectedID }),
              conversations[i].draft != composer.text || conversations[i].draftImages != composer.images else { return }
        conversations[i].draft = composer.text; conversations[i].draftImages = composer.images
    }
    func exportConversations() -> [Conversation] { commitDraft(); return conversations }
    private func loadSelection() {
        composer.load(current); chat.select(selectedID, messages: messages); resolveProvider(); refreshSearchCredential()
    }
    func setThinking(_ value: Bool) {
        guard !isGenerating, let p = provider, p.supportsThinking, value || ThinkingPolicy.canDisable(p) else { return }
        mutate(messagesChanged: false) { $0.thinking = value }; persist()
    }
    func setEffort(_ value: ReasoningEffort) { guard !isGenerating else { return }; mutate(messagesChanged: false) { $0.effort = value }; persist() }
    func setReasoningLevel(_ value: String) {
        guard !isGenerating, let p = provider, p.supportsThinking, value == "default" || ThinkingPolicy.levels(p).contains(value) else { return }
        mutate(messagesChanged: false) { $0.options.hubReasoningEffort = value }; persist()
    }
    func setSearchMode(_ value: SearchMode) {
        guard !isGenerating else { return }
        guard value != .automatic || provider?.options.supportsTools == true else { return }
        mutate(messagesChanged: false) {
            $0.options.searchMode = value
            if value != .off { $0.options.prefixEnabled = false }
        }; persist()
    }
    var searchConsent: Bool { settings.options.searchConsent ?? settings.options.externalConsent }
    var searchProviders: [Provider] { providers.filter { $0.kind == .deepSeek && URL(string: $0.baseURL)?.scheme == "https" && URL(string: $0.baseURL)?.host == "api.deepseek.com" } }
    var searchProvider: Provider? {
        if let id = settings.options.searchProviderID { return searchProviders.first { $0.id == id } }
        return searchProviders.first
    }
    private func refreshSearchCredential() {
        let ready = searchProvider.map { !((try? KeychainStore.read($0.apiKeyReference)) ?? "").isEmpty } ?? false
        if searchCredentialAvailable != ready { searchCredentialAvailable = ready }
    }
    func selectSearchProvider(_ id: UUID?) {
        guard !isGenerating else { return }
        updateGlobalOption(\.searchProviderID, id); refreshSearchCredential()
    }
    func saveSearchCredential(name: String, key: String) throws {
        guard !isGenerating else { throw AppError.validation("����ֹͣ���ɣ����޸�������Դ��") }
        var p = Provider.deepSeek; p.id = UUID(); p.apiKeyReference = UUID().uuidString
        p.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "DeepSeek ����" : name
        try saveProvider(p, newKey: key)
        selectSearchProvider(p.id)
    }
    func updateConversationOption<T>(_ path: WritableKeyPath<ConversationOptions, T>, _ value: T) { mutate(messagesChanged: false) { $0.options[keyPath: path] = value }; persist() }
    func updateGlobalOption<T>(_ path: WritableKeyPath<GlobalOptions, T>, _ value: T) { settings.options[keyPath: path] = value; persist() }
    var contextPlan: ContextPlan? {
        guard let p = provider, let c = current else { return nil }
        return try? ContextManager.plan(provider: p, conversation: c, settings: settings, tools: (c.options.toolsEnabled || c.options.searchMode != .off) && p.options.supportsTools)
    }
    var effectivePrompt: String {
        guard let p = provider, let c = current else { return "" }
        return PromptResolver.effective(provider: p, conversation: c, settings: settings)
    }
    func updateSetting<T>(_ path: WritableKeyPath<AppSettings, T>, _ value: T) { settings[keyPath: path] = value; persist() }
    func newConversation() {
        stop(); commitDraft()
        guard let p = providers.first else { return }
        let selected = provider
        var c = Conversation(providerID: selected?.id ?? p.id)
        if let modelID = selected?.modelID { c.options.modelID = modelID }
        conversations.insert(c, at: 0); selectedID = c.id; loadSelection(); renderRevision += 1; persist(immediate: true)
    }
    func selectConversation(_ id: UUID) { stop(); commitDraft(); selectedID = id; loadSelection(); renderRevision += 1; persist(immediate: true) }
    func selectProvider(_ id: UUID) { guard !isGenerating else { return }; mutate(messagesChanged: false) { $0.providerID = id; $0.options.modelID = nil }; persist() }
    func selectModel(providerID: UUID, modelID: String) {
        guard !isGenerating, let base = providers.first(where: { $0.id == providerID }), let model = models(for: providerID).first(where: { $0.id == modelID }) else { return }
        let resolved = model.apply(to: base)
        mutate(messagesChanged: false) {
            $0.providerID = providerID; $0.options.modelID = modelID; $0.options.context.calibration = nil
            if !resolved.options.supportsTools { $0.options.toolsEnabled = false }
        }
        if !resolved.supportsVision && !draftImages.isEmpty { notice = "�����ѱ�������ǰģ�Ͳ�֧��ͼƬ�����Ƴ��������л�֧��ͼƬ��ģ�͡�" }
        persist()
    }
    func models(for providerID: UUID) -> [ModelRecord] {
        if let catalog = catalogs.first(where: { $0.id == providerID }), !catalog.models.isEmpty { return catalog.models }
        guard let p = providers.first(where: { $0.id == providerID }), !p.modelID.isEmpty else { return [] }
        var m = ModelRecord(id: p.modelID, name: p.displayName)
        m.discovered = ModelCapabilities(vision: p.supportsVision, thinking: p.supportsThinking, tools: p.options.supportsTools, streaming: p.supportsStreaming, systemPrompt: p.options.supportsSystem, prefix: p.options.supportsPrefix)
        return [m]
    }
    func filteredModels(for id: UUID, query: String, favoritesOnly: Bool = false) -> [ModelRecord] {
        modelListCache.models(for: id, source: { self.models(for: id) }, query: query, favoritesOnly: favoritesOnly)
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
        resolveProvider(); persist(immediate: true)
    }
    private func replaceCatalog(_ value: ModelCatalog) {
        catalogVersions[value.id, default: 0] += 1
        if let i = catalogs.firstIndex(where: { $0.id == value.id }) { catalogs[i] = value } else { catalogs.append(value) }
        resolveProvider(); persist(immediate: true)
    }
    func cancelModelRefresh(_ id: UUID) {
        modelRequests.removeValue(forKey: id)?.cancel()
        modelOperations.removeValue(forKey: id)?.cancel()
        refreshingModels.remove(id)
    }
    private func finishModelRefresh(_ id: UUID, client: JSONHTTPClient, error: Error? = nil) {
        guard modelRequests[id] === client else { return }
        modelRequests[id] = nil; modelOperations[id] = nil; refreshingModels.remove(id)
        if let error = error { modelIssues[id] = ModelDiscoveryIssue(error) }
    }
    private func mergeFetchedModels(_ fetched: [ModelRecord], id: UUID, client: JSONHTTPClient, attempt: Int = 0) {
        guard modelRequests[id] === client else { return }
        let cached = models(for: id), version = catalogVersions[id, default: 0]
        modelOperations[id] = catalogWorker.submit({ ModelDiscovery.merge(fetched, cached: cached) }) { [weak self] merged in
            guard let self = self, self.modelRequests[id] === client else { return }
            if self.catalogVersions[id, default: 0] != version {
                guard attempt < 3 else {
                    self.finishModelRefresh(id, client: client, error: AppError.validation("����ģ�����ó����仯���ѱ�����ǰ���ã����Ժ�����ˢ�¡�")); return
                }
                self.mergeFetchedModels(fetched, id: id, client: client, attempt: attempt + 1)
                return
            }
            self.finishModelRefresh(id, client: client)
            self.replaceCatalog(ModelCatalog(id: id, models: merged, syncedAt: Date()))
        }
    }
    func refreshModels(_ id: UUID, onlyIfNeeded: Bool = false) {
        guard let p = providers.first(where: { $0.id == id }), !refreshingModels.contains(id) else { return }
        if onlyIfNeeded && (catalogs.first(where: { $0.id == id })?.syncedAt != nil || (try? KeychainStore.read(p.apiKeyReference)) == nil) { return }
        do {
            let request = try JSONHTTPClient.request(url: Endpoint.url(p.baseURL, path: p.options.modelsPath, allowLANHTTP: p.kind == .workBuddy && (p.options.workBuddy?.allowLANHTTP ?? false)), key: KeychainStore.read(p.apiKeyReference) ?? "", timeout: p.options.timeout, headers: p.customHeaders)
            let client = JSONHTTPClient(); modelRequests[id] = client; refreshingModels.insert(id); modelIssues[id] = nil
            client.start(request, configuration: modelConfiguration()) { [weak self] result in
                guard let self = self, self.modelRequests[id] === client else { return }
                do {
                    let data = try result.get()
                    self.modelOperations[id] = self.catalogWorker.submit({ Result { try ModelDiscovery.parse(data, provider: p) } }) { [weak self] parsed in
                        guard let self = self, self.modelRequests[id] === client else { return }
                        do {
                            let fetched = try parsed.get()
                            guard !fetched.isEmpty else { throw AppError.validation("ģ���б�Ϊ�գ��ѱ����������á�") }
                            self.mergeFetchedModels(fetched, id: id, client: client)
                        } catch { self.finishModelRefresh(id, client: client, error: error) }
                    }
                } catch { self.finishModelRefresh(id, client: client, error: error) }
            }
        } catch { modelIssues[id] = ModelDiscoveryIssue(error) }
    }
    func rename(_ id: UUID, title: String) {
        guard let i = conversations.firstIndex(where: { $0.id == id }) else { return }
        let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty { conversations[i].title = String(value.prefix(100)); persist() }
    }
    func deleteConversation(_ id: UUID) {
        commitDraft()
        if id == selectedID { stop() }
        conversations.removeAll { $0.id == id }
        if id == selectedID { selectedID = conversations.first?.id }
        if conversations.isEmpty { newConversation() }
        loadSelection(); persist(immediate: true)
    }
    func clearCurrent() {
        stop()
        mutate { $0.messages = []; $0.draft = ""; $0.draftImages = []; $0.summaries = []; $0.activeSummaryID = nil; $0.updatedAt = Date() }
        composer.load(current); persist(immediate: true)
    }
    func clearAll() { stop(); conversations = []; newConversation(); persist(immediate: true) }
    func addImage(_ image: Attachment) {
        guard draftImages.count < 4 else { notice = "ÿ����Ϣ������� 4 ��ͼƬ"; return }
        composer.images.append(image); dirtyRecords.insert(.conversations); persist()
    }
    func removeImage(_ id: UUID) { composer.images.removeAll { $0.id == id }; dirtyRecords.insert(.conversations); persist() }
    func send() {
        guard !isGenerating else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !draftImages.isEmpty else { return }
        // Validate configuration before clearing the persisted draft.
        do {
            guard let p = provider, !p.modelID.isEmpty else { throw AppError.validation("����ѡ��ģ��") }
            _ = try JSONHTTPClient.request(url: Endpoint.chatURL(p.baseURL, path: p.options.chatPath, allowLANHTTP: p.kind == .workBuddy && (p.options.workBuddy?.allowLANHTTP ?? false)), key: KeychainStore.read(p.apiKeyReference) ?? "")
            if !draftImages.isEmpty && !p.supportsVision { throw AppError.validation("��ǰģ�Ͳ�֧��ͼƬ�����л�ģ�ͻ��Ƴ�������") }
        } catch { notice = error.localizedDescription; return }
        let user = Message(role: .user, content: text, images: draftImages)
        mutate {
            if $0.messages.isEmpty { $0.title = String((text.isEmpty ? "ͼƬ�Ի�" : text).prefix(30)) }
            $0.messages.append(user); $0.draft = ""; $0.draftImages = []; $0.updatedAt = Date()
        }
        composer.load(current); chat.requestLatest(); beginGeneration()
    }
    func editAndResend(_ id: UUID, text: String) {
        stop()
        guard let index = messages.firstIndex(where: { $0.id == id && $0.role == .user }) else { return }
        mutate {
            if $0.activeSummary != nil { $0.activeSummaryID = nil }
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
        mutate { c in
            let removed = Set(c.messages[(userIndex + 1)...].map(\.id))
            if c.activeSummary?.coveredMessageIDs.contains(where: { removed.contains($0) }) == true { c.activeSummaryID = nil }
            c.messages.removeSubrange((userIndex + 1)..<c.messages.count)
        }
        beginGeneration()
    }
    private func beginGeneration() {
        guard let p = provider, let c = current else { return }
        let token = UUID(); generationID = token; isGenerating = true; lastCheckpoint = Date()
        persist(immediate: true)
        if ContextManager.shouldCompress(provider: p, conversation: c, settings: settings, tools: (c.options.toolsEnabled || c.options.searchMode != .off) && p.options.supportsTools) {
            summarize(token: token, continueChat: true)
        } else { startRun(token: token) }
    }
    private func startRun(token: UUID) {
        guard generationID == token, let p = provider, let c = current else { return }
        do {
            let key = try KeychainStore.read(p.apiKeyReference) ?? ""
            let needsSearch = c.options.searchMode != .off
            var search: SearchProviderService?
            if needsSearch {
                guard c.options.searchMode != .automatic || p.options.supportsTools else { throw AppError.validation("��ǰģ�Ͳ�֧���Զ������������������ѡ��ÿ����Ϣ����������ر�������") }
                guard searchConsent else { throw AppError.validation("�����������ͬ���ⲿ������δ������������") }
                guard c.options.searchTool else { throw AppError.validation("����������忪��������ѯ��") }
                guard let source = searchProvider,
                      let searchKey = try KeychainStore.read(source.apiKeyReference), !searchKey.isEmpty else { throw AppError.validation("��������������� DeepSeek ������Կ������ģ�Ϳ�ʹ�����������̡�") }
                search = searchFactory(searchKey)
            }
            let executor = BuiltInToolExecutor(options: c.options, search: search, count: settings.options.searchCount)
            let run = ChatRun(provider: p, key: key, conversation: c, settings: settings, executor: executor, canSearch: search != nil, searchService: search, searchCount: settings.options.searchCount, senderFactory: senderFactory, update: { [weak self] messages, status in
                guard let self = self, self.generationID == token else { return }
                self.chat.receive(messages)
                if self.generationStatus != status { self.generationStatus = status }
                if Date().timeIntervalSince(self.lastCheckpoint) >= 2 {
                    self.mutate { $0.messages = messages; $0.updatedAt = Date() }
                    self.lastCheckpoint = Date(); self.persist(immediate: true)
                }
            }, completion: { [weak self] result in
                guard let self = self, self.generationID == token else { return }
                if let latest = self.run?.conversation.messages { self.mutate { $0.messages = latest; $0.updatedAt = Date() } }
                if case .success(let messages) = result, let actual = messages.last?.usage?.prompt_tokens,
                   let estimate = self.run?.lastPromptEstimate, estimate > 0 {
                    self.mutate(messagesChanged: false) { c in c.options.context.calibration = min(2, max(0.5, (c.options.context.calibration ?? 1) * Double(actual) / Double(estimate))) }
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
            guard settings.options.externalConsent else { throw AppError.validation("ժҪ����ⷢ����ʷ���ݵ���ѡģ�Ͳ��������ã������ڸ߼�����������ͬ�⿪�ء�") }
            let p: Provider
            if let selected = c.options.context.summaryProviderID, let explicit = providers.first(where: { $0.id == selected }) {
                p = models(for: selected).first(where: { $0.id == (c.options.context.summaryModelID ?? explicit.modelID) })?.apply(to: explicit) ?? explicit
            }
            else if let selected = provider { p = selected }
            else { throw AppError.validation("��ѡ��ժҪģ��") }
            generationStatus = "����ѹ�������ģ�ԭʼ��ʷ������"
            compression = try SummaryService.generate(provider: p, key: KeychainStore.read(p.apiKeyReference) ?? "", conversation: c) { [weak self] result in
                guard let self = self, self.generationID == token else { return }
                self.compression = nil
                switch result {
                case .success(let version):
                    self.mutate(messagesChanged: false) { c in
                        if c.summaries == nil { c.summaries = [] }
                        c.summaries?.append(version); c.activeSummaryID = version.id
                        if !continueChat { c.options.context.strategy = .summary }
                    }
                    self.generationStatus = "ժҪ�ѱ���"; self.persist(immediate: true)
                case .failure(let error): self.notice = "ѹ��ʧ�ܣ���ժҪ��ԭʼ��ʷ�ѱ�����\n" + error.localizedDescription
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
    func activateSummary(_ id: UUID?) { mutate(messagesChanged: false) { $0.activeSummaryID = id }; persist(immediate: true) }
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
        guard data.count <= 1024 * 1024 else { throw AppError.validation("Ԥ���ļ����ó��� 1 MiB") }
        let values = try JSONDecoder().decode([PromptPreset].self, from: data)
        guard values.count <= 100, values.allSatisfy({ !$0.name.isEmpty && $0.text.count <= 32000 }) else { throw AppError.validation("Ԥ�������򳤶ȳ���") }
        for var value in values { value.id = UUID(); settings.options.presets.append(value) }
        persist(immediate: true)
    }
    func stop() {
        guard isGenerating else { return }
        run?.cancel(); compression?.cancel(); run = nil; compression = nil
        generationID = nil; isGenerating = false; generationStatus = "��ֹͣ"
        mutate { c in for i in c.messages.indices where c.messages[i].state == .generating { c.messages[i].state = .stopped } }
        persist(immediate: true)
    }
    /// Name, address and a Keychain credential are sufficient; a model is chosen after discovery.
    func saveProvider(_ input: Provider, newKey: String?, deleteKey: Bool = false) throws {
        var value = input
        value.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
        value.baseURL = value.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        value.modelID = value.modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        value.displayName = value.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.displayName.isEmpty { value.displayName = value.modelID }
        let allowLAN = value.kind == .workBuddy && (value.options.workBuddy?.allowLANHTTP ?? false)
        _ = try Endpoint.chatURL(value.baseURL, path: value.options.chatPath, allowLANHTTP: allowLAN)
        _ = try Endpoint.url(value.baseURL, path: value.options.modelsPath, allowLANHTTP: allowLAN)
        guard !value.name.isEmpty else { throw AppError.validation("����д����������") }
        guard value.customHeaders.allSatisfy({ RequestBuilder.safeHeader($0.key) && !$0.value.contains("\r") && !$0.value.contains("\n") }) else { throw AppError.validation("�Զ��� Header ֻ�ܰ����������ֶΣ��Ҳ��ܻ���") }
        guard database != nil else { throw AppError.storage("���ݿⲻ���ã��޷���������") }
        if deleteKey { try KeychainStore.delete(value.apiKeyReference) }
        else {
            let key = (newKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let effectiveKey = key.isEmpty ? (try KeychainStore.read(value.apiKeyReference) ?? "") : key
            guard !effectiveKey.isEmpty, !effectiveKey.contains("\r"), !effectiveKey.contains("\n") else { throw AppError.validation("����д��Ч�� API Key���༭ʱ���ջᱣ���Ѵ���Կ��") }
            if !key.isEmpty { try KeychainStore.write(key, reference: value.apiKeyReference) }
        }
        var next = providers
        if let i = next.firstIndex(where: { $0.id == value.id }) { next[i] = value } else { next.append(value) }
        cancelModelRefresh(value.id)
        providers = next; resolveProvider(); refreshSearchCredential(); persist(immediate: true)
        if !deleteKey { refreshModels(value.id) }
    }
    func chooseDefaultModel(providerID: UUID, modelID: String) throws {
        guard !isGenerating else { throw AppError.validation("����ֹͣ���ɣ���ѡ��Ĭ��ģ�͡�") }
        guard let index = providers.firstIndex(where: { $0.id == providerID }),
              let model = models(for: providerID).first(where: { $0.id == modelID }) else { throw AppError.validation("ģ�Ͳ����ڣ���ˢ��ģ���б���") }
        // Older conversations may inherit the provider default. Pin their former model before
        // changing that default, so choosing during onboarding cannot switch other histories.
        let previous = providers[index].modelID
        if !previous.isEmpty {
            for i in conversations.indices where conversations[i].providerID == providerID && conversations[i].options.modelID == nil {
                conversations[i].options.modelID = previous
            }
        }
        providers[index].modelID = model.id; providers[index].displayName = model.name
        selectModel(providerID: providerID, modelID: modelID)
        resolveProvider(); persist(immediate: true)
    }
    func deleteProvider(_ id: UUID) throws {
        guard providers.count > 1 else { throw AppError.validation("�����ٱ���һ��������") }
        stop()
        cancelModelRefresh(id)
        guard let value = providers.first(where: { $0.id == id }), database != nil else { return }
        let next = providers.filter { $0.id != id }
        try KeychainStore.delete(value.apiKeyReference)
        providers = next; modelIssues[id] = nil; refreshSearchCredential()
        for i in conversations.indices where conversations[i].providerID == id {
            conversations[i].providerID = next[0].id; conversations[i].options.modelID = nil
            conversations[i].options.context.calibration = nil
        }
        resolveProvider(); persist(immediate: true)
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
        notice = "�ѵ��� \(incoming.count) ���Ự����Կ�ͷ����̲���������ļ����롣"
    }
    private func persist(immediate: Bool = false) {
        saveWork?.cancel()
        if immediate { saveNow() }
        else {
            let work = DispatchWorkItem { [weak self] in self?.saveNow() }
            saveWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
        }
    }
    private func saveNow() {
        guard let database = database else { return }
        commitDraft()
        let keys = dirtyRecords
        guard !keys.isEmpty else { return }
        dirtyRecords.subtract(keys)
        let conversationSnapshot: [Conversation]? = keys.contains(.conversations) ? conversations : nil
        let providerSnapshot: [Provider]? = keys.contains(.providers) ? providers : nil
        let settingSnapshot: AppSettings? = keys.contains(.settings) ? settings : nil
        let catalogSnapshot: [ModelCatalog]? = keys.contains(.catalogs) ? catalogs : nil
        disk.async { [weak self] in
            var remaining = keys
            do {
                for key in RecordKey.allCases where keys.contains(key) {
                    switch key {
                    case .conversations: try database.save(conversationSnapshot!, key: key.rawValue)
                    case .providers: try database.save(providerSnapshot!, key: key.rawValue)
                    case .settings: try database.save(settingSnapshot!, key: key.rawValue)
                    case .catalogs: try database.save(catalogSnapshot!, key: key.rawValue)
                    }
                    remaining.remove(key)
                }
            } catch {
                let retry = remaining
                DispatchQueue.main.async {
                    self?.dirtyRecords.formUnion(retry)
                    self?.notice = "���ر���ʧ�ܣ��뼰ʱ�������ݡ�"
                }
            }
        }
    }
    /// Flush the current buffer and wait behind all already-enqueued serial writes.
    func flushPersistence(completion: @escaping () -> Void = {}) {
        persist(immediate: true)
        disk.async { DispatchQueue.main.async(execute: completion) }
    }
}
