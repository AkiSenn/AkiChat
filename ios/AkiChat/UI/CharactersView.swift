import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct CharacterIdentity: Equatable {
    let id: UUID
    let name: String
    let avatar: Data?
    init(_ record: CharacterRecord) { id = record.id; name = record.fields.name; avatar = record.avatarJPEG }
}
struct CharacterAvatar: View {
    let identity: CharacterIdentity
    private static let cache: NSCache<NSData, UIImage> = {
        let value = NSCache<NSData, UIImage>(); value.countLimit = 32; value.totalCostLimit = 8 * 1024 * 1024; return value
    }()
    private var image: UIImage? {
        guard let data = identity.avatar else { return nil }
        if let value = Self.cache.object(forKey: data as NSData) { return value }
        guard let value = UIImage(data: data) else { return nil }
        Self.cache.setObject(value, forKey: data as NSData, cost: 256 * 256 * 4); return value
    }
    var body: some View {
        Group {
            if let image = image { Image(uiImage: image).resizable().scaledToFill() }
            else { ZStack { Theme.accent.opacity(0.12); Text(String(identity.name.prefix(1))).font(.headline).foregroundColor(Theme.accent) } }
        }.clipShape(RoundedRectangle(cornerRadius: 12)).accessibilityLabel(identity.name + "头像")
    }
}

struct CharactersView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.presentationMode) private var presentation
    var onStarted: (() -> Void)?
    @State private var query = ""
    @State private var sheet: LibrarySheet?
    @State private var pending: CharacterImport?
    @State private var pickerClosed = true
    @State private var loading = false
    @State private var error = ""
    @State private var deleting: CharacterRecord?
    private enum LibrarySheet: Identifiable {
        case file, preview(CharacterImport)
        var id: String { switch self { case .file: return "file"; case .preview(let card): return card.record.id.uuidString } }
    }
    private var filtered: [CharacterRecord] {
        store.characters.filter { query.isEmpty || $0.fields.name.localizedCaseInsensitiveContains(query) || $0.fields.tags.contains { $0.localizedCaseInsensitiveContains(query) } }
    }
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    Text("用熟悉的模型，遇见不同的角色。").font(.subheadline).foregroundColor(.secondary)
                    TextField("搜索角色或标签", text: $query).padding(14).background(Theme.card).cornerRadius(14).accessibilityIdentifier("character-search")
                    Button { pickerClosed = false; sheet = .file } label: { Label("导入角色 · PNG / JSON", systemImage: "square.and.arrow.down").frame(minHeight: 44) }.disabled(loading).accessibilityIdentifier("import-character")
                    if loading { ProgressView("正在本地解析…") }
                    if !error.isEmpty { Text(error).font(.footnote).foregroundColor(.red) }
                    if filtered.isEmpty { Text("还没有匹配的角色。请从“文件”选择原始酒馆角色卡，预览后确认保存。").foregroundColor(.secondary).padding(.vertical, 30) }
                    ForEach(filtered) { card in
                        NavigationLink(destination: CharacterDetail(card: card, onStarted: finish).environmentObject(store)) {
                            Card {
                                HStack(spacing: 14) {
                                    CharacterAvatar(identity: CharacterIdentity(card)).frame(width: 60, height: 60)
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(card.fields.name).font(.headline).foregroundColor(.primary)
                                        Text(card.fields.tags.joined(separator: " · ")).font(.caption).foregroundColor(.secondary).lineLimit(2)
                                        Text(card.spec == "chara_card_v3" ? "Character Card V3" : "Character Card V2").font(.caption2).foregroundColor(.secondary)
                                    }
                                    Spacer(); Image(systemName: "chevron.right").foregroundColor(.secondary)
                                }
                            }
                        }.accessibilityIdentifier("character-" + card.id.uuidString)
                        .contextMenu { Button("删除角色") { deleting = card } }
                    }
                }.padding(18)
            }.background(Theme.background).navigationTitle("角色库")
                .navigationBarItems(trailing: Button("完成") { presentation.wrappedValue.dismiss() })
        }.navigationViewStyle(StackNavigationViewStyle())
            .sheet(item: $sheet, onDismiss: { pickerClosed = true; showPending() }) { value in
                switch value {
                case .file: CharacterDocumentPicker { url in
                    sheet = nil
                    guard let url = url else { return }
                    loading = true; error = ""
                    CharacterImportService.load(url) { result in
                        loading = false
                        switch result { case .success(let card): pending = card; showPending(); case .failure(let issue): error = issue.localizedDescription }
                    }
                }
                case .preview(let card): CharacterImportPreview(imported: card, onClose: { sheet = nil }).environmentObject(store)
                }
            }
            .alert(item: $deleting) { card in Alert(title: Text("删除“\(card.fields.name)”？"), message: Text("只从角色库移除。已有会话、设定快照和原始 PNG 资源会保留。"), primaryButton: .destructive(Text("删除")) { store.deleteCharacter(card.id) }, secondaryButton: .cancel(Text("取消"))) }
    }
    private func showPending() { if pickerClosed, let value = pending { pending = nil; sheet = .preview(value) } }
    private func finish() { if let action = onStarted { action() } else { presentation.wrappedValue.dismiss() } }
}

private struct CharacterDocumentPicker: UIViewControllerRepresentable {
    let completion: (URL?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let controller = UIDocumentPickerViewController(forOpeningContentTypes: [.png, .json], asCopy: true)
        controller.delegate = context.coordinator; controller.allowsMultipleSelection = false; return controller
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let completion: (URL?) -> Void
        init(_ completion: @escaping (URL?) -> Void) { self.completion = completion }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { completion(urls.first) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { completion(nil) }
    }
}

private struct CharacterImportPreview: View {
    @EnvironmentObject var store: AppStore
    let imported: CharacterImport
    let onClose: () -> Void
    @State private var saving = false
    @State private var error = ""
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    CharacterInformation(card: imported.record)
                    ForEach(imported.warnings, id: \.self) { Text($0).font(.caption).foregroundColor(.orange) }
                    Text("导入在本地完成。开始角色对话后，设定与匹配的世界书内容会发给所选模型服务商。卡片不能读取设备或密钥，不会自动下载资源或执行代码。").font(.footnote).foregroundColor(.secondary)
                    if !error.isEmpty { Text(error).foregroundColor(.red) }
                    Button(saving ? "正在保存…" : "确认保存到角色库") {
                        saving = true
                        store.saveCharacter(imported) { result in
                            saving = false
                            switch result { case .success: onClose(); case .failure(let issue): error = issue.localizedDescription }
                        }
                    }.frame(minHeight: 44).disabled(saving).accessibilityIdentifier("confirm-character-import")
                }.padding(18)
            }.background(Theme.background).navigationTitle("导入预览").navigationBarTitleDisplayMode(.inline)
                .navigationBarItems(leading: Button("取消", action: onClose).disabled(saving))
        }.navigationViewStyle(StackNavigationViewStyle())
    }
}

struct CharacterDetail: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.presentationMode) private var presentation
    let card: CharacterRecord
    let onStarted: () -> Void
    @State private var providerID: UUID?
    @State private var modelID = ""
    @State private var greeting = 0
    @State private var deleting = false
    @State private var error = ""
    private var availableModels: [ModelRecord] {
        guard let id = providerID else { return [] }
        return store.models(for: id)
    }
    private var greetings: [String] { [card.fields.firstMessage] + card.fields.alternateGreetings }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                CharacterInformation(card: card)
                modelCard
                if !error.isEmpty { Text(error).foregroundColor(.red) }
                Button("删除角色") { deleting = true }.foregroundColor(.red).frame(minHeight: 44)
            }.padding(18)
        }.background(Theme.background).navigationTitle("角色详情").navigationBarTitleDisplayMode(.inline)
            .onAppear(perform: initializeSelection)
            .onChange(of: providerID, perform: selectDefaultModel)
            .alert(isPresented: $deleting) { deletionAlert }
    }
    private var providerPicker: some View {
        Picker("服务商", selection: $providerID) {
            Text("请选择").tag(nil as UUID?)
            ForEach(store.providers) { p in Text(p.name).tag(Optional(p.id)) }
        }
    }
    private var modelPicker: some View {
        Picker("模型", selection: $modelID) {
            Text("请选择模型").tag("")
            ForEach(availableModels) { model in Text(model.name).tag(model.id) }
        }
    }
    private var greetingPicker: some View {
        Picker("开场白", selection: $greeting) {
            Text("默认开场白").tag(0)
            ForEach(card.fields.alternateGreetings.indices, id: \.self) { index in
                Text("开场白 " + String(index + 2) + " · " + String(card.fields.alternateGreetings[index].prefix(30))).tag(index + 1)
            }
        }.accessibilityIdentifier("character-greeting-picker")
    }
    private var modelCard: some View {
        Card {
            Text("开始角色对话").font(.headline)
            providerPicker
            modelPicker
            if let id = providerID { NavigationLink("管理该服务商模型", destination: ModelsView(providerID: id).environmentObject(store)) }
            greetingPicker
            Text(greetings.indices.contains(greeting) ? greetings[greeting] : "").font(.footnote).foregroundColor(.secondary)
            Button("开始对话", action: start).frame(minHeight: 44).disabled(store.isGenerating || modelID.isEmpty).accessibilityIdentifier("start-character-chat")
            Text("开场白直接显示，不调用 API。角色与模型相互独立，不会修改全局提示词或其他会话。").font(.caption).foregroundColor(.secondary)
        }
    }
    private var deletionAlert: Alert {
        Alert(title: Text("删除角色？"), message: Text("只从角色库移除；已有会话、设定和原始 PNG 会保留。"),
              primaryButton: .destructive(Text("删除")) { store.deleteCharacter(card.id); presentation.wrappedValue.dismiss() }, secondaryButton: .cancel(Text("取消")))
    }
    private func start() {
        guard let id = providerID else { error = "请选择服务商和模型"; return }
        do { try store.newCharacterConversation(card, greeting: greeting, providerID: id, modelID: modelID); onStarted() }
        catch { self.error = error.localizedDescription }
    }
    private func initializeSelection() {
        if providerID == nil { providerID = store.provider?.id ?? store.providers.first?.id }
        if !availableModels.contains(where: { $0.id == modelID }) { selectDefaultModel(providerID) }
    }
    private func selectDefaultModel(_ id: UUID?) {
        let preferred: String?
        if id == store.provider?.id { preferred = store.provider?.modelID }
        else { preferred = store.providers.first(where: { Optional($0.id) == id })?.modelID }
        modelID = availableModels.first(where: { Optional($0.id) == preferred })?.id ?? availableModels.first?.id ?? ""
    }
}

private struct CharacterInformation: View {
    let card: CharacterRecord
    var body: some View {
        Card {
            CharacterAvatar(identity: CharacterIdentity(card)).frame(width: 110, height: 110)
            Text(card.fields.name).font(.title2).bold()
            Text(card.fields.tags.joined(separator: " · ")).font(.caption).foregroundColor(.secondary)
            Text("性格：" + card.fields.personality).font(.subheadline)
            Text("背景：" + String(card.fields.description.prefix(1200))).font(.subheadline)
            Text("场景：" + String(card.fields.scenario.prefix(1200))).font(.subheadline)
            DisclosureGroup("完整人物设定与示例") {
                NativeRichText(text: [card.fields.description, card.fields.personality, card.fields.scenario, card.fields.systemPrompt, card.fields.examples, card.fields.postHistory].joined(separator: "\n\n"), size: 13)
            }
            DisclosureGroup("作者说明与兼容范围") {
                Text(card.fields.creatorNotes).font(.footnote)
                Text("作者：\(card.fields.creator) · 版本：\(card.fields.version)").font(.caption)
                Text("原始 JSON、未知扩展、V3 nickname/assets/group_only_greetings 保留。群聊、外部资源、脚本及复杂扩展不执行，不宣称完整酒馆兼容。").font(.caption).foregroundColor(.secondary)
            }
            if let book = card.fields.book {
                DisclosureGroup("世界书 · \(book.entries.count) 条") {
                    Text("启用的基础条目支持常驻、字面关键词与次要关键词匹配，按插入顺序放在角色设定前/后。最多扫描最近 \(book.scanDepth) 条消息、约 \(book.budget) tokens；预算外条目不注入。带扩展、正则或装饰器的条目只保存，不执行；不递归触发。").font(.caption).foregroundColor(.secondary)
                    ForEach(book.entries) { entry in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("#\(entry.id + 1) · " + (!entry.enabled ? "已禁用" : (entry.supported ? "可触发" : "仅保存"))).font(.caption).bold()
                            Text(entry.keys.joined(separator: " · ")).font(.caption)
                            Text(String(entry.content.prefix(1200))).font(.footnote)
                        }.padding(.vertical, 8)
                    }
                }
            }
        }
    }
}
