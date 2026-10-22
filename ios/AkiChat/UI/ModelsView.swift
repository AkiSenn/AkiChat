import SwiftUI

struct ModelsView: View {
    @EnvironmentObject var store: AppStore
    let providerID: UUID
    var selecting = false
    var onSelect: (() -> Void)?
    @State private var query = ""
    @State private var editing: ModelRecord?
    @State private var deleting: ModelRecord?
    var sorted: [ModelRecord] {
        store.models(for: providerID).filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.id.localizedCaseInsensitiveContains(query) }
            .sorted { a, b in a.favorite != b.favorite ? a.favorite : (a.order != b.order ? a.order < b.order : a.name.localizedStandardCompare(b.name) == .orderedAscending) }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                TextField("搜索模型名称或 ID", text: $query).padding(14).background(Theme.card).cornerRadius(14)
                HStack {
                    Button(store.refreshingModels.contains(providerID) ? "取消刷新" : "刷新 /models") {
                        if store.refreshingModels.contains(providerID) { store.cancelModelRefresh(providerID) } else { store.refreshModels(providerID) }
                    }.frame(minHeight: 44)
                    Spacer()
                    Button { var m = ModelRecord(id: "", name: ""); m.manual = true; editing = m } label: { Label("手动添加", systemImage: "plus") }.frame(minHeight: 44)
                }
                if let date = store.catalogs.first(where: { $0.id == providerID })?.syncedAt {
                    HStack { Text("上次同步"); Text(date, style: .date); Text(date, style: .time) }.font(.caption).foregroundColor(.secondary)
                } else { Text("尚未同步；接口不可用时仍可使用本地模型。").font(.caption).foregroundColor(.secondary) }
                if let error = store.modelErrors[providerID] { Text(error).font(.footnote).foregroundColor(.red) }
                ForEach(sorted) { model in
                    Card {
                        HStack(alignment: .top) {
                            Button {
                                if selecting { store.selectModel(providerID: providerID, modelID: model.id); onSelect?() } else { editing = model }
                            } label: {
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(model.name).font(.headline).foregroundColor(.primary)
                                    Text(model.id).font(.caption).foregroundColor(.secondary)
                                    Text(model.contextWindow.map { "上下文 \($0) tokens" } ?? "上下文容量未声明，可手动覆盖")
                                        .font(.caption2).foregroundColor(.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }.disabled(store.isGenerating && selecting)
                            Button { var m = model; m.favorite.toggle(); store.saveModel(m, providerID: providerID) } label: {
                                Image(systemName: model.favorite ? "star.fill" : "star").frame(width: 44, height: 44)
                            }.accessibilityLabel(model.favorite ? "取消收藏" : "收藏模型")
                        }
                    }.contextMenu {
                        Button("编辑能力与提示词") { editing = model }
                        if model.manual { Button("删除自定义模型") { deleting = model } }
                    }
                }
                Text("未知能力保持未声明，不推断图片、思考或工具支持。长按模型可覆盖能力、排序与提示词。").font(.caption).foregroundColor(.secondary)
            }.padding(18)
        }.background(Theme.background).navigationTitle("模型库")
            .onAppear { store.refreshModels(providerID, onlyIfNeeded: true) }
            .sheet(item: $editing) { ModelEditor(model: $0, providerID: providerID).environmentObject(store) }
            .alert(item: $deleting) { model in
                Alert(title: Text("删除自定义模型？"), message: Text(model.id), primaryButton: .destructive(Text("删除")) { store.deleteModel(model.id, providerID: providerID) }, secondaryButton: .cancel(Text("取消")))
            }
    }
}

struct ModelEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.presentationMode) var presentation
    @State var model: ModelRecord
    let providerID: UUID
    @State private var error = ""
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    Card {
                        TextField("模型 ID", text: $model.id).autocapitalization(.none).disableAutocorrection(true).disabled(!model.manual)
                        TextField("显示名称", text: $model.name)
                        Stepper("排序权重：\(model.order)", value: $model.order, in: -100...100)
                        Toggle("收藏", isOn: $model.favorite)
                        numeric("上下文 Token 容量（0 = 未知）", value: $model.contextWindow)
                        numeric("最大输出 Tokens（0 = 未知）", value: $model.outputLimit)
                    }
                    Card {
                        Text("能力覆盖：自动 / 开启 / 关闭").font(.headline)
                        capability("图片", path: \.vision)
                        capability("思考", path: \.thinking)
                        capability("工具调用", path: \.tools)
                        capability("流式", path: \.streaming)
                        capability("System Prompt", path: \.systemPrompt)
                        capability("Assistant Prefix", path: \.prefix)
                        Text("思考和前缀的特殊协议目前仅由 DeepSeek 适配层发送。").font(.caption).foregroundColor(.secondary)
                    }
                    Card {
                        Text("模型级 System Prompt").font(.headline)
                        TextEditor(text: $model.systemPrompt).frame(height: 100)
                        PresetSelection(selected: $model.presetIDs, presets: store.settings.options.presets)
                        if !model.effort.isEmpty { Text("推理强度：" + model.effort.joined(separator: ", ")).font(.caption) }
                        Text("原始协议元数据").font(.caption)
                        Text(model.metadata).font(.system(.caption, design: .monospaced)).foregroundColor(.secondary)
                    }
                    if !error.isEmpty { Text(error).foregroundColor(.red) }
                }.padding(18)
            }.background(Theme.background).navigationTitle("编辑模型").navigationBarTitleDisplayMode(.inline)
                .navigationBarItems(leading: Button("取消") { presentation.wrappedValue.dismiss() }, trailing: Button("保存") {
                    model.id = model.id.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !model.id.isEmpty, model.id.count <= 256 else { error = "请输入有效模型 ID"; return }
                    if model.name.isEmpty { model.name = model.id }
                    store.saveModel(model, providerID: providerID); presentation.wrappedValue.dismiss()
                })
        }.navigationViewStyle(StackNavigationViewStyle())
    }
    private func numeric(_ title: String, value: Binding<Int?>) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption).foregroundColor(.secondary)
            TextField(title, text: Binding(get: { value.wrappedValue.map(String.init) ?? "" }, set: { value.wrappedValue = Int($0).flatMap { $0 > 0 && $0 <= 4000000 ? $0 : nil } })).keyboardType(.numberPad)
        }
    }
    private func capability(_ title: String, path: WritableKeyPath<ModelCapabilities, Bool?>) -> some View {
        HStack {
            Text(title).font(.subheadline).frame(width: 100, alignment: .leading)
            Picker(title, selection: Binding(get: { model.overrides[keyPath: path].map { $0 ? 1 : 2 } ?? 0 }, set: { model.overrides[keyPath: path] = $0 == 0 ? nil : $0 == 1 })) {
                Text("自动").tag(0); Text("开").tag(1); Text("关").tag(2)
            }.pickerStyle(SegmentedPickerStyle())
        }
    }
}

struct PresetSelection: View {
    @Binding var selected: [UUID]
    let presets: [PromptPreset]
    var body: some View {
        ForEach(presets) { p in
            Toggle(p.name + (p.enabled ? "" : "（全局已关闭）"), isOn: Binding(get: { selected.contains(p.id) }, set: { enabled in
                if enabled { if !selected.contains(p.id) { selected.append(p.id) } } else { selected.removeAll { $0 == p.id } }
            })).font(.subheadline)
        }
    }
}
