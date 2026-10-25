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
            }.background(Theme.background).navigationTitle("�Ự����̨").navigationBarTitleDisplayMode(.inline)
                .navigationBarItems(trailing: Button("���") { presentation.wrappedValue.dismiss() })
        }.navigationViewStyle(StackNavigationViewStyle()).accessibilityIdentifier("conversation-settings")
    }
    private var contextCard: some View {
        Card {
            Label("������Ԥ��", systemImage: "chart.bar").font(.headline)
            if let plan = store.contextPlan {
                ProgressView(value: Double(plan.estimatedTokens + plan.outputBudget), total: Double(plan.totalBudget))
                Text("Լ \(plan.estimatedTokens) ���� + \(plan.outputBudget) ���Ԥ�� / \(plan.totalBudget) tokens").font(.caption)
                Text("����ֵ�������ص�ʵ�� usage У׼������ʡ�� \(plan.omittedTurns) �֣�ԭʼ��¼�Ա����ڱ�����").font(.caption).foregroundColor(.secondary)
            } else { Text("��ǰ���ݿ��ܳ���Ԥ�㣻����Ԥ�����Ժ����ԡ�").font(.caption).foregroundColor(.secondary) }
            NumberField(title: "�������� Token Ԥ��", value: option(\.context.inputBudget), range: 1024...4000000)
            NumberField(title: "������ Token Ԥ��", value: option(\.context.outputBudget), range: 256...393216)
            Text("ģ������ \(store.provider?.options.contextWindow ?? 0)��ģ��������� \(store.provider?.options.outputLimit ?? 0)��ʵ�������ȡ��ȫ������").font(.caption).foregroundColor(.secondary)
            Picker("��ʷ����", selection: option(\.context.strategy)) {
                Text("�Զ�").tag(ContextStrategy.automatic); Text("ȫ��").tag(ContextStrategy.full)
                Text("����").tag(ContextStrategy.window); Text("ժҪ+����").tag(ContextStrategy.summary)
            }.pickerStyle(SegmentedPickerStyle())
            Stepper("������� \(store.current?.options.context.recentTurns ?? 8) �������Ի�", value: option(\.context.recentTurns), in: 1...32)
        }
    }
    private var summaryCard: some View {
        Card {
            Label("�Զ�ѹ��", systemImage: "arrow.down.right.and.arrow.up.left").font(.headline)
            Toggle("ͬ�����ժҪ���󼰷���", isOn: global(\.externalConsent))
            Text("������ʷ��������ģ�Ͳ��������ã�������Ȩ������������������").font(.caption).foregroundColor(.secondary)
            Toggle("�����Զ�����ժҪ", isOn: Binding(get: { store.current?.options.context.autoCompress ?? false }, set: { enabled in
                store.updateConversationOption(\.context.autoCompress, enabled)
                if !enabled { store.updateConversationOption(\.context.strategy, ContextStrategy.window) }
            }))
            Text("������ֵ \(Int((store.current?.options.context.threshold ?? 0.75) * 100))%").font(.subheadline)
            Slider(value: option(\.context.threshold), in: 0.5...0.9, step: 0.05)
            Picker("ժҪ������ / Ĭ��ģ��", selection: option(\.context.summaryProviderID)) {
                Text("���浱ǰģ��").tag(nil as UUID?)
                ForEach(store.providers) { Text($0.name + " / " + $0.displayName).tag(Optional($0.id)) }
            }
            if let id = store.current?.options.context.summaryProviderID {
                Picker("ժҪģ��", selection: option(\.context.summaryModelID)) {
                    Text("ʹ�÷�����Ĭ��ģ��").tag(nil as String?)
                    ForEach(store.models(for: id)) { Text($0.name).tag(Optional($0.id)) }
                }
            }
            Button("����ѹ������ʷ") { store.compressNow() }.frame(minHeight: 44).disabled(store.isGenerating)
            if store.isGenerating { Button("ֹͣ��ǰ����") { store.stop() }.frame(minHeight: 44) }
            DisclosureGroup("��ǰժҪ", isExpanded: $showSummary) {
                NativeRichText(text: store.current?.activeSummary?.text ?? "����ժҪ", size: 13)
            }
            DisclosureGroup("ժҪ�汾��\(store.current?.summaries?.count ?? 0)��", isExpanded: $showVersions) {
                ForEach((store.current?.summaries ?? []).reversed()) { version in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack { Text(version.createdAt, style: .time); Text("���� \(version.coveredMessageIDs.count) ��ԭʼ��Ϣ") }.font(.caption)
                        Text("\(version.modelID) �� ժҪ�������� \(version.usage?.total_tokens.map(String.init) ?? "δ����") tokens").font(.caption2).foregroundColor(.secondary)
                        Button(store.current?.activeSummaryID == version.id ? "��ǰ�汾" : "�ָ�����汾") { store.activateSummary(version.id) }.disabled(store.isGenerating)
                    }.padding(.vertical, 8)
                }
            }
            HStack {
                Button("�ָ���һ�汾") { store.rollbackSummary() }
                Spacer()
                Button("�����ǰժҪ") { store.activateSummary(nil) }.foregroundColor(.red)
            }.font(.footnote).frame(minHeight: 44).disabled(store.isGenerating)
            Text("ժҪ�Ƕ���ģ�����󣬿��ܲ������á�ʧ��ʱ�����ɰ汾���κ�ѹ�������޸Ļ�ɾ��ԭʼ��Ϣ��").font(.caption).foregroundColor(.secondary)
        }
    }
    private var promptCard: some View {
        Card {
            Label("�Ự System Prompt", systemImage: "text.alignleft").font(.headline)
            if store.provider?.options.supportsSystem == false { Text("��ǰģ�͹ر��� System Prompt ���������β��ᷢ�ʹ��ֶΡ�").font(.caption).foregroundColor(.orange) }
            TextEditor(text: option(\.systemPrompt)).frame(height: 100)
            PresetSelection(selected: option(\.presetIDs), presets: store.settings.options.presets)
            NavigationLink("������ʾ��Ԥ��", destination: PromptLibraryView().environmentObject(store)).frame(minHeight: 44)
            DisclosureGroup("Ԥ��������Ч System Prompt") { NativeRichText(text: store.effectivePrompt.isEmpty ? "δ���û�Ϊ��" : store.effectivePrompt, size: 13) }
            Text("Ӧ�� �� Provider �� ģ�� �� �Ự������ľ����������ȣ�ÿ������������װ��").font(.caption).foregroundColor(.secondary)
        }
    }
    private var toolsCard: some View {
        Card {
            Label("���ù���", systemImage: "wrench.and.screwdriver").font(.headline)
            Toggle("���ù��ߵ���", isOn: option(\.toolsEnabled)).disabled(store.provider?.options.supportsTools != true)
            if store.provider?.options.supportsTools != true { Text("ģ��δ��������֧�֣�����ģ�Ϳ��к�ʵ���ֶ����ǡ�").font(.caption).foregroundColor(.secondary) }
            Group {
                Toggle("����ʱ�乤��", isOn: option(\.dateTool))
                Toggle("��ȫ���㹤��", isOn: option(\.calculatorTool))
                Stepper("��� \(store.current?.options.maxToolRounds ?? 4) �ֹ���ѭ��", value: option(\.maxToolRounds), in: 1...8)
            }.disabled(store.provider?.options.supportsTools != true || store.current?.options.toolsEnabled != true)
            Text("ÿ����� 4 �����á�����ʧ�ܻ���Ϊ����������ģ�ͣ���ִ���նˡ�������롢�ļ���˽�����ݲ�����").font(.caption).foregroundColor(.secondary)
        }
    }
    private var imageCard: some View {
        Card {
            Label("ͼƬ����", systemImage: "photo").font(.headline)
            Picker("���", selection: global(\.imageDimension)) {
                Text("512 px").tag(512); Text("1024 px").tag(1024); Text("2048 px").tag(2048)
            }.pickerStyle(SegmentedPickerStyle())
            Text("JPEG ���� \(Int(store.settings.options.imageQuality * 100))%").font(.subheadline)
            Slider(value: global(\.imageQuality), in: 0.4...0.95, step: 0.05)
            Text("Ӧ������ѡ���ͼƬ��ÿ����� 4 �ţ�ÿ����� 4 MiB��").font(.caption).foregroundColor(.secondary)
        }
    }
    private var prefixCard: some View {
        Card {
            Text("Assistant Prefix �� Beta").font(.headline)
            if store.provider?.kind == .deepSeek && store.provider?.options.supportsPrefix == true {
                Toggle("�������ǰ׺��ȫ", isOn: Binding(get: { store.current?.options.prefixEnabled ?? false }, set: { enabled in
                    store.updateConversationOption(\.prefixEnabled, enabled)
                    if enabled { store.updateConversationOption(\.toolsEnabled, false); store.setSearchMode(.off) }
                }))
                TextEditor(text: option(\.assistantPrefix)).frame(height: 80)
                Text("ʹ�� /beta���������һ�� assistant ��Ϣ���� prefix:true��ǰ׺���� System Prompt�������빤�ߵ��û��⡣").font(.caption).foregroundColor(.secondary)
            } else { Text("��ǰģ��δ���� DeepSeek Prefix Beta ������").font(.caption).foregroundColor(.secondary) }
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
