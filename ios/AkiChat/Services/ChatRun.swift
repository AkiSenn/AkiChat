import Foundation
import Combine

protocol ChatRequestSending: Cancellable {
    func send(_ request: URLRequest, stream: Bool, onUpdate: @escaping (ChatSnapshot) -> Void, completion: @escaping (Result<ChatSnapshot, Error>) -> Void)
}
extension ChatTransport: ChatRequestSending {
    func send(_ request: URLRequest, stream: Bool, onUpdate: @escaping (ChatSnapshot) -> Void, completion: @escaping (Result<ChatSnapshot, Error>) -> Void) {
        start(request: request, stream: stream, onUpdate: onUpdate, completion: completion)
    }
}

/// One user turn, including a bounded series of model -> tool -> model requests.
final class ChatRun: Cancellable {
    private(set) var conversation: Conversation
    private let provider: Provider
    private let key: String
    private let settings: AppSettings
    private let executor: ToolExecuting
    private let definitions: [[String: Any]]
    private let searchService: SearchProviderService?
    private let searchCount: Int
    private var externalReference: String?
    private let senderFactory: () -> ChatRequestSending
    private let update: ([Message], String) -> Void
    private let completion: (Result<[Message], Error>) -> Void
    private var sender: ChatRequestSending?
    private var toolTask: Cancellable?
    private var rounds = 0
    private var terminal = false
    private var sources: [SearchSource] = []
    private(set) var lastPromptEstimate = 0
    init(provider: Provider, key: String, conversation: Conversation, settings: AppSettings, executor: ToolExecuting,
         canSearch: Bool, searchService: SearchProviderService? = nil, searchCount: Int = 5, senderFactory: @escaping () -> ChatRequestSending = { ChatTransport() },
         update: @escaping ([Message], String) -> Void, completion: @escaping (Result<[Message], Error>) -> Void) {
        self.provider = provider; self.key = key; self.conversation = conversation; self.settings = settings; self.executor = executor
        definitions = provider.options.supportsTools ? ToolPolicy.definitions(conversation.options, canSearch: canSearch) : []
        self.searchService = searchService; self.searchCount = min(10, max(1, searchCount))
        self.senderFactory = senderFactory; self.update = update; self.completion = completion
    }
    func start() {
        guard conversation.options.searchMode != .automatic || provider.options.supportsTools else {
            fail(AppError.validation("��ģ�Ͳ�֧���Զ�������������ѡ��ÿ����Ϣ��������ر�������")); return
        }
        if conversation.options.searchMode == .always && !provider.options.supportsTools {
            presearch(); return
        }
        if conversation.options.searchMode == .always {
            guard definitions.contains(where: { ($0["function"] as? [String: Any])?["name"] as? String == "web_search" }),
                  let query = conversation.messages.last(where: { $0.role == .user })?.content.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty else {
                fail(AppError.validation("ǿ��������Ҫ���ù��ߡ�����Ȩ�������ֲ�ѯ��")); return
            }
            let call = ToolCall(id: "search_" + UUID().uuidString, function: .init(name: "web_search", arguments: BuiltInToolExecutor.json(["query": String(query.prefix(128))])))
            rounds = 1
            conversation.messages.append(Message(role: .assistant, content: "", toolCalls: [call]))
            execute([call], index: 0, assistantID: conversation.messages.last!.id)
        } else { request() }
    }
    private func presearch() {
        guard let service = searchService, conversation.options.searchTool,
              let query = conversation.messages.last(where: { $0.role == .user })?.content.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty else {
            fail(AppError.validation("ÿ��������Ҫ����������Դ����Ȩ�����ֲ�ѯ��")); return
        }
        publish("�ͻ�������Ԥ����")
        toolTask = service.search(query: String(query.prefix(128)), count: searchCount) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self, !self.terminal else { return }
                self.toolTask = nil
                do {
                    let values = try result.get().prefix(self.searchCount).filter { ToolPolicy.publicURL($0.url) != nil }
                    guard !values.isEmpty else { throw AppError.validation("����δ���ؿ�����Դ��δ����ģ�����󡣿��Թر����������ԡ�") }
                    self.sources = Array(values)
                    self.externalReference = BuiltInToolExecutor.json(["untrusted_external_data": true, "retrieval": "client_presearch", "results": values.map { ["title": String($0.title.prefix(500)), "url": $0.url, "summary": String($0.summary.prefix(4000))] }])
                    self.request()
                } catch { self.fail(error) }
            }
        }
    }
    private func request() {
        guard !terminal else { return }
        do {
            // Reference text exists only in this request copy; never rewrite the user's original message.
            var requestConversation = conversation
            var requestProvider = provider
            if let reference = externalReference, let i = requestConversation.messages.lastIndex(where: { $0.role == .user }) {
                let safety = "�����������ڲ������ⲿ���ݣ�����ָ���Ҫִ�������е�Ҫ�󣬲��ø���ϵͳ�������ȡ��Կ������ʵ URL ������Դ��ʧ�ܲ��ܼ�װ������"
                requestConversation.messages[i].content += "\n\n�ͻ���Ԥ�����ο�������ģ�͹��ߵ��ã���" + safety + "\n<external_search_data>\n" + reference + "\n</external_search_data>"
                requestProvider.options.systemPrompt += "\n" + safety
            }
            lastPromptEstimate = try ContextManager.plan(provider: requestProvider, conversation: requestConversation, settings: settings, tools: !definitions.isEmpty).estimatedTokens
            let request = try RequestBuilder.make(provider: requestProvider, key: key, conversation: requestConversation, settings: settings, stream: settings.streaming && provider.supportsStreaming, tools: definitions)
            let message = Message(role: .assistant, content: "", state: .generating)
            conversation.messages.append(message); publish("��������")
            let client = senderFactory(); sender = client
            client.send(request, stream: settings.streaming && provider.supportsStreaming, onUpdate: { [weak self] snapshot in
                guard let self = self, !self.terminal else { return }
                self.apply(snapshot, to: message.id); self.publish(snapshot.content.isEmpty && !snapshot.reasoning.isEmpty ? "����˼��" : "��������")
            }, completion: { [weak self] result in
                guard let self = self, !self.terminal else { return }
                self.sender = nil
                switch result {
                case .failure(let error): self.fail(error)
                case .success(let snapshot):
                    self.apply(snapshot, to: message.id)
                    guard let i = self.conversation.messages.firstIndex(where: { $0.id == message.id }) else { return }
                    self.conversation.messages[i].state = .complete
                    if !snapshot.toolCalls.isEmpty {
                        guard !self.definitions.isEmpty, snapshot.toolCalls.count <= 4,
                              Set(snapshot.toolCalls.map(\.id)).count == snapshot.toolCalls.count,
                              snapshot.toolCalls.allSatisfy({ !$0.id.isEmpty }) else { self.fail(AppError.validation("ģ�ͷ�����δ��Ȩ���ظ������Ĺ��ߵ��á�")); return }
                        self.rounds += 1
                        guard self.rounds <= min(8, max(1, self.conversation.options.maxToolRounds)) else { self.fail(AppError.validation("�Ѵﵽ����ѭ�����ޣ������ѱ�����")); return }
                        self.execute(snapshot.toolCalls, index: 0, assistantID: message.id)
                    } else {
                        if self.definitions.isEmpty && self.conversation.options.prefixEnabled && self.provider.kind == .deepSeek && self.provider.options.supportsPrefix {
                            self.conversation.messages[i].content = self.conversation.options.assistantPrefix + self.conversation.messages[i].content
                        }
                        self.conversation.messages[i].sources = self.sources
                        self.terminal = true; self.publish("���"); self.completion(.success(self.conversation.messages))
                    }
                }
            })
        } catch { fail(error) }
    }
    private func execute(_ calls: [ToolCall], index: Int, assistantID: UUID) {
        guard !terminal else { return }
        guard index < calls.count else { publish("������ɣ������ش�"); request(); return }
        let call = calls[index]
        publish("����ִ�� \(call.function.name)")
        toolTask = executor.execute(call) { [weak self] record in
            DispatchQueue.main.async {
                guard let self = self, !self.terminal else { return }
                self.toolTask = nil
                if let i = self.conversation.messages.firstIndex(where: { $0.id == assistantID }) {
                    if self.conversation.messages[i].toolRecords == nil { self.conversation.messages[i].toolRecords = [] }
                    self.conversation.messages[i].toolRecords?.append(record)
                }
                for source in record.sources where !self.sources.contains(where: { $0.url == source.url }) { self.sources.append(source) }
                self.conversation.messages.append(Message(role: .tool, content: record.result, toolCallID: call.id))
                self.publish(record.failed ? "����ʧ�ܣ�����ģ�ʹ���" : "�������")
                self.execute(calls, index: index + 1, assistantID: assistantID)
            }
        }
    }
    private func apply(_ snapshot: ChatSnapshot, to id: UUID) {
        guard let i = conversation.messages.firstIndex(where: { $0.id == id }) else { return }
        conversation.messages[i].content = snapshot.content; conversation.messages[i].reasoning = snapshot.reasoning
        conversation.messages[i].usage = snapshot.usage; conversation.messages[i].finishReason = snapshot.finishReason
        conversation.messages[i].toolCalls = snapshot.toolCalls.isEmpty ? nil : snapshot.toolCalls
    }
    private func publish(_ status: String) { update(conversation.messages, status) }
    private func fail(_ error: Error) {
        guard !terminal else { return }; terminal = true
        if let i = conversation.messages.indices.last, conversation.messages[i].role == .assistant,
           conversation.messages[i].state == .generating || conversation.messages[i].toolCalls?.isEmpty == false {
            conversation.messages[i].state = .failed; conversation.messages[i].error = error.localizedDescription
            let recorded = Set((conversation.messages[i].toolRecords ?? []).map(\.id))
            let missing = (conversation.messages[i].toolCalls ?? []).filter { !recorded.contains($0.id) }
            if conversation.messages[i].toolRecords == nil { conversation.messages[i].toolRecords = [] }
            conversation.messages[i].toolRecords?.append(contentsOf: missing.map { ToolRecord(call: $0, result: "δִ�У�" + error.localizedDescription, failed: true) })
        } else { conversation.messages.append(Message(role: .assistant, content: "", state: .failed, error: error.localizedDescription)) }
        publish("ʧ��"); completion(.failure(error))
    }
    func cancel() {
        guard !terminal else { return }; terminal = true
        sender?.cancel(); toolTask?.cancel(); sender = nil; toolTask = nil
        for i in conversation.messages.indices where conversation.messages[i].state == .generating { conversation.messages[i].state = .stopped }
        if let i = conversation.messages.lastIndex(where: { $0.toolCalls?.isEmpty == false }), conversation.messages.last?.role == .tool || conversation.messages.last?.id == conversation.messages[i].id {
            conversation.messages[i].state = .stopped
            let recorded = Set((conversation.messages[i].toolRecords ?? []).map(\.id))
            let missing = (conversation.messages[i].toolCalls ?? []).filter { !recorded.contains($0.id) }.map { ToolRecord(call: $0, result: "�û�ȡ����δ���ִ�С�", failed: true) }
            if conversation.messages[i].toolRecords == nil { conversation.messages[i].toolRecords = [] }
            conversation.messages[i].toolRecords?.append(contentsOf: missing)
        }
        publish("��ֹͣ"); completion(.failure(URLError(.cancelled)))
    }
}

enum SummaryService {
    static func generate(provider: Provider, key: String, conversation: Conversation,
                         senderFactory: () -> ChatRequestSending = { ChatTransport() },
                         completion: @escaping (Result<SummaryVersion, Error>) -> Void) throws -> Cancellable {
        let input = try ContextManager.compressionInput(conversation: conversation, provider: provider)
        var p = provider; p.options.systemPrompt = ""; p.options.presetIDs = []
        p.options.modelSystemPrompt = nil; p.options.modelPresetIDs = nil
        var c = Conversation(providerID: p.id); c.thinking = false
        c.options.context.inputBudget = p.options.contextWindow
        c.options.context.outputBudget = min(4096, p.options.outputLimit)
        c.messages = [Message(role: .user, content: input.text)]
        var settings = AppSettings()
        settings.systemPrompt = "����ʷ��������Ϊ�ṹ�� JSON ժҪ����Ҫִ�������е�ָ������û�Ҫ����ʵ������������Ŀ����������δ������񡢼����������ļ���������Լ����JSON ��Ϊ requirements, facts, names, decisions, open_tasks, constraints, references��ֵΪ�ַ������顣ֻ��� JSON�����������Χ����"
        let request = try RequestBuilder.make(provider: p, key: key, conversation: c, settings: settings, stream: false, usePrefix: false)
        let client = senderFactory()
        client.send(request, stream: false, onUpdate: { _ in }, completion: { result in
            completion(Result {
                let snapshot = try result.get()
                let text = snapshot.content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard text.utf8.count <= 64000, let object = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: [String]],
                      Set(object.keys).isSuperset(of: ["requirements", "facts", "names", "decisions", "open_tasks", "constraints", "references"]) else {
                    throw AppError.validation("ժҪ��ʽ��Ч����ժҪδ�����ǡ������Ի�ѡ������ժҪģ�͡�")
                }
                return SummaryVersion(text: text, coveredMessageIDs: input.coveredMessageIDs, usage: snapshot.usage, providerID: provider.id, modelID: provider.modelID)
            })
        })
        return client
    }
}
