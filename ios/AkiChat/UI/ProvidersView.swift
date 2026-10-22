import SwiftUI

struct ProvidersView: View {
    @EnvironmentObject var store: AppStore
    @State private var editing: Provider?
    @State private var deleting: Provider?
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                NoticeBanner()
                ForEach(store.providers) { p in
                    Button { editing = p } label: {
                        Card {
                            HStack {
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(p.name).font(.headline)
                                    Text(p.displayName).font(.subheadline)
                                    Text(p.modelID).font(.caption).foregroundColor(.secondary)
                                }
                                Spacer(); Image(systemName: "chevron.right")
                            }.foregroundColor(.primary)
                        }
                    }.contextMenu { Button { deleting = p } label: { Label("删除服务商", systemImage: "trash") } }
                }
                Button { editing = Provider(name: "", baseURL: "https://", modelID: "", displayName: "") } label: {
                    Label("添加 OpenAI 兼容服务商 / 模型", systemImage: "plus.circle.fill").padding()
                }
                Text("每个配置代表一个服务商与模型组合；同一地址可配置多个模型。密钥仅保存到 Keychain。自定义 Header 只用于非敏感元数据。")
                    .font(.caption).foregroundColor(.secondary)
            }.padding(18)
        }.background(Theme.background).navigationTitle("模型与 API Key")
            .sheet(item: $editing) { ProviderEditor(provider: $0).environmentObject(store) }
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
    @State private var key = ""
    @State private var deleteKey = false
    @State private var headers = ""
    @State private var status = ""
    @State private var testing = false
    @State private var client: ChatTransport?
    @State private var testID: UUID?
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    Card {
                        field("服务商名称", text: $provider.name)
                        field("显示名称", text: $provider.displayName)
                        field("Base URL（HTTPS）", text: $provider.baseURL)
                        field("API 模型 ID", text: $provider.modelID)
                        Picker("适配方式", selection: $provider.kind) {
                            Text("OpenAI 兼容").tag(ProviderKind.openAI)
                            Text("DeepSeek 官方格式").tag(ProviderKind.deepSeek)
                        }.pickerStyle(SegmentedPickerStyle())
                        Text("支持填写根地址、/v1 或完整 /chat/completions 路径。").font(.caption).foregroundColor(.secondary)
                    }
                    Card {
                        Text("API Key").font(.headline)
                        SecureField("留空保留已存密钥", text: $key).autocapitalization(.none).disableAutocorrection(true)
                        Toggle("删除已保存密钥", isOn: $deleteKey)
                        Text("密钥不会显示、导出或写入日志。API 测试将发送一条简短请求，可能产生少量费用。")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Card {
                        Text("模型能力").font(.headline)
                        Toggle("支持图片理解", isOn: $provider.supportsVision)
                        Toggle("支持深度思考（DeepSeek 适配）", isOn: $provider.supportsThinking)
                        Toggle("支持流式响应", isOn: $provider.supportsStreaming)
                        Toggle("请求流式 Token usage 扩展", isOn: $provider.requestsStreamingUsage)
                        Text("非 DeepSeek 适配不会发送 thinking 与 reasoning_effort 字段。").font(.caption).foregroundColor(.secondary)
                        Text("自定义非敏感 Headers（JSON 对象）").font(.caption)
                        TextEditor(text: $headers).frame(height: 80).font(.system(size: 12, design: .monospaced))
                    }
                    Card {
                        Button(testing ? "取消测试" : "测试连接和密钥") { if testing { cancelTest() } else { test() } }
                        if testing { ProgressView() }
                        if !status.isEmpty { Text(status).font(.footnote).foregroundColor(.secondary) }
                    }
                }.padding(18)
            }.background(Theme.background).navigationTitle("配置模型").navigationBarTitleDisplayMode(.inline)
                .navigationBarItems(leading: Button("取消") { cancelTest(); presentation.wrappedValue.dismiss() }, trailing: Button("保存") { save() }.disabled(testing))
        }.navigationViewStyle(StackNavigationViewStyle())
            .onAppear {
                if let data = try? JSONSerialization.data(withJSONObject: provider.customHeaders, options: [.prettyPrinted, .sortedKeys]) { headers = String(data: data, encoding: .utf8) ?? "{}" }
            }
            .onDisappear { cancelTest() }
    }
    private func field(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundColor(.secondary)
            TextField(title, text: text).autocapitalization(.none).disableAutocorrection(true)
            Divider()
        }
    }
    private func validated() throws -> Provider {
        var result = provider
        result.name = result.name.trimmingCharacters(in: .whitespacesAndNewlines)
        result.modelID = result.modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        result.displayName = result.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try Endpoint.chatURL(result.baseURL)
        let data = Data((headers.isEmpty ? "{}" : headers).utf8)
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: String], value.keys.allSatisfy(RequestBuilder.safeHeader) else {
            throw AppError.validation("Header 必须是字符串 JSON 对象，且不得包含认证、Cookie、Key、Token 或 Secret。")
        }
        result.customHeaders = value
        return result
    }
    private func save() {
        do { try store.saveProvider(validated(), newKey: key, deleteKey: deleteKey); presentation.wrappedValue.dismiss() }
        catch { status = error.localizedDescription }
    }
    private func cancelTest() { testID = nil; client?.cancel(); client = nil; testing = false }
    private func test() {
        do {
            guard !deleteKey else { throw AppError.validation("取消删除密钥后再测试") }
            let p = try validated()
            let apiKey = key.isEmpty ? try KeychainStore.read(p.apiKeyReference) ?? "" : key
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
