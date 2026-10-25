import SwiftUI

struct SearchPanel: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.presentationMode) private var presentation
    @State private var adding = false
    @State private var sourceName = "DeepSeek 搜索"
    @State private var key = ""
    @State private var status = ""
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 18) {
                    modeCard
                    sourceCard
                    privacyCard
                }.padding(18)
            }.background(Theme.background.edgesIgnoringSafeArea(.all))
                .navigationTitle("联网搜索").navigationBarTitleDisplayMode(.inline)
                .navigationBarItems(leading: Button("关闭") { presentation.wrappedValue.dismiss() }.accessibilityIdentifier("search-panel-close"), trailing: Button("完成") { presentation.wrappedValue.dismiss() })
        }.navigationViewStyle(StackNavigationViewStyle()).accessibilityIdentifier("search-panel")
    }
    private var modeCard: some View {
        Card {
            Text("搜索模式").font(.headline)
            Picker("搜索模式", selection: Binding(get: { store.current?.options.searchMode ?? .off }, set: { store.setSearchMode($0) })) {
                Text("关闭").tag(SearchMode.off)
                Text("自动搜索").tag(SearchMode.automatic).disabled(store.provider?.options.supportsTools != true)
                Text("每次搜索").tag(SearchMode.always)
            }.pickerStyle(SegmentedPickerStyle()).disabled(store.isGenerating).accessibilityIdentifier("search-mode-picker")
            Text("每次消息都搜索：发送前执行真实搜索，再把带链接的参考资料交给当前模型。").font(.caption).foregroundColor(.secondary)
            if store.provider?.options.supportsTools != true {
                Text("当前模型不支持自动工具搜索；可选择每次搜索。客户端预搜索不会伪装成模型主动调用工具。").font(.footnote).foregroundColor(.secondary).accessibilityIdentifier("search-auto-unavailable")
            }
            if store.isGenerating { Text("正在生成，设置只读；请停止后修改。").font(.caption).foregroundColor(.secondary) }
        }
    }
    private var sourceCard: some View {
        Card {
            Text("搜索来源").font(.headline)
            Picker("DeepSeek 官方搜索", selection: Binding(get: { store.settings.options.searchProviderID }, set: { store.selectSearchProvider($0) })) {
                Text("首个 DeepSeek 官方配置").tag(nil as UUID?)
                ForEach(store.searchProviders) { Text($0.name).tag(Optional($0.id)) }
            }.accessibilityIdentifier("search-provider-picker").disabled(store.isGenerating)
            Text(store.searchCredentialAvailable ? "搜索使用此来源独立保存的密钥；聊天继续使用当前聊天模型的密钥。" : "尚无可用的搜索密钥，请添加搜索来源。")
                .font(.caption).foregroundColor(.secondary)
            DisclosureGroup("添加搜索来源", isExpanded: $adding) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("DeepSeek 官方 Search / Fetch · https://api.deepseek.com").font(.caption).foregroundColor(.secondary)
                    TextField("来源名称", text: $sourceName)
                    SecureField("DeepSeek 官方 API Key", text: $key).autocapitalization(.none).disableAutocorrection(true).accessibilityIdentifier("search-api-key")
                    Button("保存搜索密钥") {
                        do {
                            try store.saveSearchCredential(name: sourceName, key: key)
                            key = ""; adding = false; status = "搜索来源已保存，密钥仅存于 Keychain。"
                        } catch { status = error.localizedDescription }
                    }.frame(minHeight: 44)
                }.padding(.top, 12)
            }.disabled(store.isGenerating).accessibilityIdentifier("add-search-provider")
            if !status.isEmpty { Text(status).font(.caption).foregroundColor(.secondary) }
            Stepper("每次最多 \(store.settings.options.searchCount) 个结果", value: Binding(get: { store.settings.options.searchCount }, set: { store.updateGlobalOption(\.searchCount, $0) }), in: 1...10).disabled(store.isGenerating)
            Toggle("允许读取来源网页", isOn: Binding(get: { store.current?.options.fetchTool ?? true }, set: { store.updateConversationOption(\.fetchTool, $0) })).disabled(store.isGenerating)
            if store.current?.options.searchTool == false {
                Button("恢复搜索查询能力") { store.updateConversationOption(\.searchTool, true) }.disabled(store.isGenerating)
            }
        }
    }
    private var privacyCard: some View {
        Card {
            Text("隐私与费用").font(.headline)
            Text("联网搜索可能将你的查询发送给搜索服务商，并产生额外费用。网页读取还会发送所选 URL。密钥不会提供给模型或网页。").font(.footnote).foregroundColor(.secondary)
            Toggle("同意外部搜索", isOn: Binding(get: { store.searchConsent }, set: { store.updateGlobalOption(\.searchConsent, Optional($0)) }))
                .disabled(store.isGenerating).accessibilityIdentifier("search-consent-toggle")
            if !store.searchConsent { Text("尚未授权：不会发起搜索。可在此直接同意或拒绝。").font(.caption).foregroundColor(.secondary) }
            Text("自动模式由支持工具调用的模型决定是否查询；每次模式先搜索。关闭联网或拒绝授权后不发起新的搜索，已进行的任务请用停止按钮取消。").font(.caption).foregroundColor(.secondary)
        }
    }
}
