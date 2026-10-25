import SwiftUI

struct ProvidersView: View {
    @EnvironmentObject var store: AppStore
    var onConfigured: (() -> Void)?
    @State private var editing: Provider?
    @State private var deleting: Provider?
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                NoticeBanner()
                Button { editing = Provider.newCompatible } label: {
                    Label("添加 API 服务商", systemImage: "plus.circle.fill").padding()
                }
                .accessibilityIdentifier("add-api-provider")
                ForEach(store.providers) { p in
                    NavigationLink(destination: ModelsView(providerID: p.id).environmentObject(store)) {
                        Label("\(p.name) 模型库", systemImage: "square.stack")
                    }.frame(minHeight: 44)
                    Button { editing = p } label: {
                        Card {
                            HStack {
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(p.name).font(.headline)
                                    Text(p.modelID.isEmpty ? "尚未选择默认模型" : "默认模型 · " + p.modelID).font(.caption).foregroundColor(.secondary)
                                }
                                Spacer(); Image(systemName: "chevron.right")
                            }.foregroundColor(.primary)
                        }
                    }.contextMenu { Button { deleting = p } label: { Label("删除服务商", systemImage: "trash") } }
                }
                Button("添加 OpenAI 预设") { var p = Provider.openAI; p.id = UUID(); p.apiKeyReference = UUID().uuidString; editing = p }
                Button("添加 WorkBuddy2API Hub") {
                    var p = Provider.workBuddy; p.id = UUID(); p.apiKeyReference = UUID().uuidString
                    editing = p
                }
                Text("每个服务商拥有独立模型目录；顶部面板可跨服务商切换。密钥仅保存到 Keychain。自定义 Header 只用于非敏感元数据。")
                    .font(.caption).foregroundColor(.secondary)
            }.padding(18)
        }.background(Theme.background).navigationTitle("API 服务商")
            .sheet(item: $editing) { ProviderEditor(provider: $0, onConfigured: onConfigured).environmentObject(store) }
            .alert(item: $deleting) { p in
                Alert(title: Text("删除 \(p.name)？"), message: Text("对应密钥也会删除，相关会话将切换至另一个配置。"), primaryButton: .destructive(Text("删除")) {
                    do { try store.deleteProvider(p.id) } catch { store.notice = error.localizedDescription }
                }, secondaryButton: .cancel(Text("取消")))
            }
    }
}

struct ProviderEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.presentationMode) var presentation
    @State var provider: Provider
    var onConfigured: (() -> Void)?
    @State private var saved = false
    @State private var advanced = false
    @State private var key = ""
    @State private var deleteKey = false
    @State private var headers = ""
    @State private var status = ""
    @State private var testing = false
    @State private var client: ChatTransport?
    @State private var testID: UUID?
    var body: some View {
        NavigationView {
            Group {
                if saved {
                    ModelsView(providerID: provider.id, selecting: true, choosingDefault: true, onSelect: {
                        presentation.wrappedValue.dismiss(); onConfigured?()
                    })
                    .navigationTitle("选择默认模型")
                    .navigationBarItems(leading: Button("稍后选择") { presentation.wrappedValue.dismiss() })
                } else { editor }
            }
        }.navigationViewStyle(StackNavigationViewStyle())
            .onAppear {
                if let data = try? JSONSerialization.data(withJSONObject: provider.customHeaders, options: [.prettyPrinted, .sortedKeys]) { headers = String(data: data, encoding: .utf8) ?? "{}" }
            }
            .onDisappear { cancelTest() }
    }
    private var editor: some View {
            ScrollView {
                VStack(spacing: 16) {
                    Card {
                        field("服务商名称", text: $provider.name, id: "provider-name")
                        field("API Base URL", text: $provider.baseURL, id: "provider-url")
                        Text("填写名称、地址和密钥，保存后即可获取模型。支持根地址、/v1 或完整聊天路径。").font(.caption).foregroundColor(.secondary)
                        Text("API Key").font(.caption).foregroundColor(.secondary)
                        SecureField("填写密钥；编辑时留空保留", text: $key).autocapitalization(.none).disableAutocorrection(true).accessibilityIdentifier("provider-key")
                        Text("密钥仅保存在设备 Keychain，不会显示、导出或写入日志。").font(.caption).foregroundColor(.secondary)
                    }
                    Button(action: save) {
                        Text("保存并获取模型").fontWeight(.semibold).frame(maxWidth: .infinity).padding(14).foregroundColor(.white).background(Theme.accent).cornerRadius(14)
                    }.disabled(testing).accessibilityIdentifier("save-discover-models")
                    if !status.isEmpty { Text(status).font(.footnote).foregroundColor(.red).accessibilityIdentifier("provider-status") }
                    DisclosureGroup("高级兼容设置", isExpanded: $advanced) { advancedOptions }.padding(.vertical, 8)
                }.padding(18)
            }.background(Theme.background).navigationTitle("配置 API 服务商").navigationBarTitleDisplayMode(.inline)
                .navigationBarItems(leading: Button("取消") { cancelTest(); presentation.wrappedValue.dismiss() })
    }
    private var advancedOptions: some View {
        VStack(spacing: 16) {
        Card {
            Text("模型可在保存后选择；以下默认值仅用于兼容旧配置。").font(.caption).foregroundColor(.secondary)
            field("默认模型 ID（可选）", text: $provider.modelID)
            field("默认模型显示名称（可选）", text: $provider.displayName)
            field("Chat Completions 路径", text: $provider.options.chatPath)
            field("Models 路径", text: $provider.options.modelsPath)
            Picker("适配方式", selection: $provider.kind) {
                Text("OpenAI 兼容").tag(ProviderKind.openAI)
                Text("DeepSeek 官方格式").tag(ProviderKind.deepSeek)
                Text("WorkBuddy2API Hub").tag(ProviderKind.workBuddy)
            }.pickerStyle(SegmentedPickerStyle())
            Text("支持填写根地址、/v1 或完整 /chat/completions 路径。").font(.caption).foregroundColor(.secondary)
            if provider.kind == .workBuddy {
                Toggle("允许本地 HTTP（仅局域网）", isOn: Binding(
                    get: { provider.options.workBuddy?.allowLANHTTP ?? false },
                    set: { var options = provider.options; var hub = options.workBuddy ?? WorkBuddyOptions(); hub.allowLANHTTP = $0; options.workBuddy = hub; provider.options = options }
                ))
                Text("开启后 Key、聊天和图片会以明文发送，仅用于你主动信任的私有 IP 或 .local 地址。使用系统 TLS 验证，未开放公网 HTTP。iOS 首次连接可能询问本地网络权限。").font(.caption).foregroundColor(.secondary)
            }
        }
        Card {
            if provider.kind == .workBuddy { Text("填写 Hub 管理面板生成的网关 API Key；不是面板密码或上游 OAuth 凭据。").font(.caption).foregroundColor(.secondary) }
            Toggle("删除已保存密钥", isOn: $deleteKey)
            Text("密钥不会显示、导出或写入日志。API 测试将发送一条简短请求，可能产生少量费用。")
                .font(.caption).foregroundColor(.secondary)
        }
        Card {
            Text("模型能力").font(.headline)
            Toggle("支持图片理解", isOn: $provider.supportsVision)
            Toggle("支持深度思考", isOn: $provider.supportsThinking)
            Toggle("支持流式响应", isOn: $provider.supportsStreaming)
            Toggle("请求流式 Token usage 扩展", isOn: $provider.requestsStreamingUsage)
            Toggle("支持 Function Calling", isOn: $provider.options.supportsTools)
            Toggle("支持 System Prompt", isOn: $provider.options.supportsSystem)
            Toggle("支持 Prefix Beta", isOn: $provider.options.supportsPrefix)
            Picker("输出预算字段", selection: $provider.options.tokenLimitField) {
                Text("自动适配").tag(nil as OutputTokenField?)
                Text("max_tokens").tag(Optional(OutputTokenField.maxTokens))
                Text("max_completion_tokens").tag(Optional(OutputTokenField.maxCompletionTokens))
            }
            Toggle("发送采样参数", isOn: Binding(get: { provider.options.sendSamplingParameters ?? (provider.kind != .workBuddy && URL(string: provider.baseURL)?.host != "api.openai.com") }, set: { provider.options.sendSamplingParameters = $0 }))
            Stepper("超时：\(Int(provider.options.timeout)) 秒", value: $provider.options.timeout, in: 10...300, step: 10)
            Stepper("上下文：\(provider.options.contextWindow) tokens", value: $provider.options.contextWindow, in: 4096...1048576, step: 4096)
            Stepper("最大输出：\(provider.options.outputLimit) tokens", value: $provider.options.outputLimit, in: 256...131072, step: 256)
            Text("Hub 发送标准 reasoning_effort，不发送 DeepSeek 私有 thinking；其他 OpenAI 兼容服务商默认不发送两者。").font(.caption).foregroundColor(.secondary)
            Text("自定义非敏感 Headers（JSON 对象）").font(.caption)
            TextEditor(text: $headers).frame(height: 80).font(.system(size: 12, design: .monospaced))
        }
        Card {
            Text("Provider 默认提示词").font(.headline)
            TextEditor(text: $provider.options.systemPrompt).frame(height: 90)
            PresetSelection(selected: $provider.options.presetIDs, presets: store.settings.options.presets)
        }
        Card {
            Button(testing ? "取消测试" : "测试连接和密钥") { if testing { cancelTest() } else { test() } }
            if testing { ProgressView() }
        }
        }
    }
    private func field(_ title: String, text: Binding<String>, id: String = "") -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundColor(.secondary)
            TextField(title, text: text).autocapitalization(.none).disableAutocorrection(true).accessibilityIdentifier(id)
            Divider()
        }
    }
    private func validated() throws -> Provider {
        var result = provider
        result.name = result.name.trimmingCharacters(in: .whitespacesAndNewlines)
        result.modelID = result.modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        result.displayName = result.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try Endpoint.chatURL(result.baseURL, path: result.options.chatPath, allowLANHTTP: result.kind == .workBuddy && (result.options.workBuddy?.allowLANHTTP ?? false))
        let data = Data((headers.isEmpty ? "{}" : headers).utf8)
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: String], value.keys.allSatisfy(RequestBuilder.safeHeader) else {
            throw AppError.validation("Header 必须是字符串 JSON 对象，且不得包含认证、Cookie、Key、Token 或 Secret。")
        }
        result.customHeaders = value
        return result
    }
    private func save() {
        do {
            let value = try validated()
            try store.saveProvider(value, newKey: key, deleteKey: deleteKey)
            key = ""; status = ""
            if deleteKey { presentation.wrappedValue.dismiss() } else { saved = true }
        }
        catch { status = error.localizedDescription }
    }
    private func cancelTest() { testID = nil; client?.cancel(); client = nil; testing = false }
    private func test() {
        do {
            guard !deleteKey else { throw AppError.validation("取消删除密钥后再测试") }
            var p = try validated()
            let models = store.models(for: p.id)
            let selectedID = store.current?.providerID == p.id ? store.current?.options.modelID : nil
            let testModel = p.modelID.isEmpty ? (models.first(where: { $0.id == selectedID }) ?? models.first) : models.first(where: { $0.id == p.modelID })
            if let model = testModel { p = model.apply(to: p) }
            let apiKey: String
            if key.isEmpty { apiKey = try KeychainStore.read(p.apiKeyReference) ?? "" }
            else { apiKey = key }
            guard !p.modelID.isEmpty else { status = "请先保存地址和密钥以发现模型，再选择模型测试。"; return }
            var c = Conversation(providerID: p.id); c.thinking = false
            c.messages = [Message(role: .user, content: "Reply with OK.")]
            var settings = AppSettings(); settings.systemPrompt = ""; settings.maxTokens = 256
            let request = try RequestBuilder.make(provider: p, key: apiKey, conversation: c, settings: settings, stream: false)
            let token = UUID(); testID = token; testing = true; status = "正在测试…"
            let client = ChatTransport(); self.client = client
            client.start(request: request, stream: false, onUpdate: { _ in }, completion: { result in
                guard testID == token else { return }
                testing = false; self.client = nil; testID = nil
                switch result {
                case .success: status = "连接成功，密钥与模型可用。请点击保存。"
                case .failure(let error): status = error.localizedDescription
                }
            })
        } catch { status = error.localizedDescription }
    }
}
