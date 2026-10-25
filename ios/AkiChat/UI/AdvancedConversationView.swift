import SwiftUI

struct AdvancedConversationView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.presentationMode) var presentation
    @State private var showSummary = false
    @State private var showVersions = false
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 18) {
                    NoticeBanner()
                    contextCard
                    summaryCard
                    promptCard
                    toolsCard
                    imageCard
                    prefixCard
                }.padding(18)
            }.background(Theme.background).navigationTitle("会话控制台").navigationBarTitleDisplayMode(.inline)
                .navigationBarItems(trailing: Button("完成") { presentation.wrappedValue.dismiss() })
        }.navigationViewStyle(StackNavigationViewStyle()).accessibilityIdentifier("conversation-settings")
    }
    private var contextCard: some View {
        Card {
            Label("上下文预算", systemImage: "chart.bar").font(.headline)
            if let plan = store.contextPlan {
                ProgressView(value: Double(plan.estimatedTokens + plan.outputBudget), total: Double(plan.totalBudget))
                Text("约 \(plan.estimatedTokens) 输入 + \(plan.outputBudget) 输出预留 / \(plan.totalBudget) tokens").font(.caption)
                Text("估算值，按返回的实际 usage 校准；本次省略 \(plan.omittedTurns) 轮，原始记录仍保存在本机。").font(.caption).foregroundColor(.secondary)
            } else { Text("当前内容可能超出预算；调整预算或策略后重试。").font(.caption).foregroundColor(.secondary) }
            NumberField(title: "总上下文 Token 预算", value: option(\.context.inputBudget), range: 1024...4000000)
            NumberField(title: "最大输出 Token 预算", value: option(\.context.outputBudget), range: 256...393216)
            Text("模型容量 \(store.provider?.options.contextWindow ?? 0)，模型输出上限 \(store.provider?.options.outputLimit ?? 0)；实际请求会取安全交集。").font(.caption).foregroundColor(.secondary)
            Picker("历史策略", selection: option(\.context.strategy)) {
                Text("自动").tag(ContextStrategy.automatic); Text("全量").tag(ContextStrategy.full)
                Text("窗口").tag(ContextStrategy.window); Text("摘要+近期").tag(ContextStrategy.summary)
            }.pickerStyle(SegmentedPickerStyle())
            Stepper("保留最近 \(store.current?.options.context.recentTurns ?? 8) 轮完整对话", value: option(\.context.recentTurns), in: 1...32)
        }
    }
    private var summaryCard: some View {
        Card {
            Label("自动压缩", systemImage: "arrow.down.right.and.arrow.up.left").font(.headline)
            Toggle("同意额外摘要请求及费用", isOn: global(\.externalConsent))
            Text("整理历史会额外调用模型并产生费用；联网授权独立在联网面板管理。").font(.caption).foregroundColor(.secondary)
            Toggle("允许自动生成摘要", isOn: Binding(get: { store.current?.options.context.autoCompress ?? false }, set: { enabled in
                store.updateConversationOption(\.context.autoCompress, enabled)
                if !enabled { store.updateConversationOption(\.context.strategy, ContextStrategy.window) }
            }))
            Text("触发阈值 \(Int((store.current?.options.context.threshold ?? 0.75) * 100))%").font(.subheadline)
            Slider(value: option(\.context.threshold), in: 0.5...0.9, step: 0.05)
            Picker("摘要服务商 / 默认模型", selection: option(\.context.summaryProviderID)) {
                Text("跟随当前模型").tag(nil as UUID?)
                ForEach(store.providers) { Text($0.name + " / " + $0.displayName).tag(Optional($0.id)) }
            }
            if let id = store.current?.options.context.summaryProviderID {
                Picker("摘要模型", selection: option(\.context.summaryModelID)) {
                    Text("使用服务商默认模型").tag(nil as String?)
                    ForEach(store.models(for: id)) { Text($0.name).tag(Optional($0.id)) }
                }
            }
            Button("立即压缩旧历史") { store.compressNow() }.frame(minHeight: 44).disabled(store.isGenerating)
            if store.isGenerating { Button("停止当前任务") { store.stop() }.frame(minHeight: 44) }
            DisclosureGroup("当前摘要", isExpanded: $showSummary) {
                NativeRichText(text: store.current?.activeSummary?.text ?? "尚无摘要", size: 13)
            }
            DisclosureGroup("摘要版本（\(store.current?.summaries?.count ?? 0)）", isExpanded: $showVersions) {
                ForEach((store.current?.summaries ?? []).reversed()) { version in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack { Text(version.createdAt, style: .time); Text("覆盖 \(version.coveredMessageIDs.count) 条原始消息") }.font(.caption)
                        Text("\(version.modelID) · 摘要额外用量 \(version.usage?.total_tokens.map(String.init) ?? "未返回") tokens").font(.caption2).foregroundColor(.secondary)
                        Button(store.current?.activeSummaryID == version.id ? "当前版本" : "恢复这个版本") { store.activateSummary(version.id) }.disabled(store.isGenerating)
                    }.padding(.vertical, 8)
                }
            }
            HStack {
                Button("恢复上一版本") { store.rollbackSummary() }
                Spacer()
                Button("清除当前摘要") { store.activateSummary(nil) }.foregroundColor(.red)
            }.font(.footnote).frame(minHeight: 44).disabled(store.isGenerating)
            Text("摘要是额外模型请求，可能产生费用。失败时保留旧版本；任何压缩都不修改或删除原始消息。").font(.caption).foregroundColor(.secondary)
        }
    }
    private var promptCard: some View {
        Card {
            Label("会话 System Prompt", systemImage: "text.alignleft").font(.headline)
            if store.provider?.options.supportsSystem == false { Text("当前模型关闭了 System Prompt 能力，本次不会发送此字段。").font(.caption).foregroundColor(.orange) }
            TextEditor(text: option(\.systemPrompt)).frame(height: 100)
            PresetSelection(selected: option(\.presetIDs), presets: store.settings.options.presets)
            NavigationLink("管理提示词预设", destination: PromptLibraryView().environmentObject(store)).frame(minHeight: 44)
            DisclosureGroup("预览本次有效 System Prompt") { NativeRichText(text: store.effectivePrompt.isEmpty ? "未启用或为空" : store.effectivePrompt, size: 13) }
            Text("应用 → Provider → 模型 → 会话，后面的具体设置优先；每次请求重新组装。").font(.caption).foregroundColor(.secondary)
        }
    }
    private var toolsCard: some View {
        Card {
            Label("内置工具", systemImage: "wrench.and.screwdriver").font(.headline)
            Toggle("启用工具调用", isOn: option(\.toolsEnabled)).disabled(store.provider?.options.supportsTools != true)
            if store.provider?.options.supportsTools != true { Text("模型未声明工具支持，可在模型库中核实并手动覆盖。").font(.caption).foregroundColor(.secondary) }
            Group {
                Toggle("日期时间工具", isOn: option(\.dateTool))
                Toggle("安全计算工具", isOn: option(\.calculatorTool))
                Stepper("最多 \(store.current?.options.maxToolRounds ?? 4) 轮工具循环", value: option(\.maxToolRounds), in: 1...8)
            }.disabled(store.provider?.options.supportsTools != true || store.current?.options.toolsEnabled != true)
            Text("每轮最多 4 个调用。工具失败会作为错误结果交回模型；不执行终端、任意代码、文件或私有数据操作。").font(.caption).foregroundColor(.secondary)
        }
    }
    private var imageCard: some View {
        Card {
            Label("图片发送", systemImage: "photo").font(.headline)
            Picker("最长边", selection: global(\.imageDimension)) {
                Text("512 px").tag(512); Text("1024 px").tag(1024); Text("2048 px").tag(2048)
            }.pickerStyle(SegmentedPickerStyle())
            Text("JPEG 质量 \(Int(store.settings.options.imageQuality * 100))%").font(.subheadline)
            Slider(value: global(\.imageQuality), in: 0.4...0.95, step: 0.05)
            Text("应用于新选择的图片；每条最多 4 张，每张最多 4 MiB。").font(.caption).foregroundColor(.secondary)
        }
    }
    private var prefixCard: some View {
        Card {
            Text("Assistant Prefix · Beta").font(.headline)
            if store.provider?.kind == .deepSeek && store.provider?.options.supportsPrefix == true {
                Toggle("启用输出前缀补全", isOn: Binding(get: { store.current?.options.prefixEnabled ?? false }, set: { enabled in
                    store.updateConversationOption(\.prefixEnabled, enabled)
                    if enabled { store.updateConversationOption(\.toolsEnabled, false); store.setSearchMode(.off) }
                }))
                TextEditor(text: option(\.assistantPrefix)).frame(height: 80)
                Text("使用 /beta，并在最后一条 assistant 消息设置 prefix:true。前缀不是 System Prompt，本版与工具调用互斥。").font(.caption).foregroundColor(.secondary)
            } else { Text("当前模型未启用 DeepSeek Prefix Beta 能力。").font(.caption).foregroundColor(.secondary) }
        }
    }
    private func option<T>(_ path: WritableKeyPath<ConversationOptions, T>) -> Binding<T> {
        Binding(get: { (store.current?.options ?? ConversationOptions())[keyPath: path] }, set: { store.updateConversationOption(path, $0) })
    }
    private func global<T>(_ path: WritableKeyPath<GlobalOptions, T>) -> Binding<T> {
        Binding(get: { store.settings.options[keyPath: path] }, set: { store.updateGlobalOption(path, $0) })
    }
}

struct NumberField: View {
    let title: String
    @Binding var value: Int
    var range: ClosedRange<Int>
    @State private var text = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundColor(.secondary)
            TextField(title, text: $text, onCommit: commit).keyboardType(.numberPad)
                .onChange(of: text) { new in if let number = Int(new), range.contains(number) { value = number } }
        }.onAppear { text = String(value) }.onChange(of: value) { text = String($0) }.onDisappear(perform: commit)
    }
    private func commit() { if let number = Int(text) { value = min(range.upperBound, max(range.lowerBound, number)) }; text = String(value) }
}
