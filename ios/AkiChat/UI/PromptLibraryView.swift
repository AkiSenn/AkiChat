import SwiftUI
import UniformTypeIdentifiers

struct PromptLibraryView: View {
    @EnvironmentObject var store: AppStore
    @State private var sheet: Destination?
    @State private var deleting: PromptPreset?
    @State private var importing = false
    private enum Destination: Identifiable {
        case edit(PromptPreset), share(ShareFile)
        var id: UUID { switch self { case .edit(let p): return p.id; case .share(let f): return f.id } }
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                NoticeBanner()
                Card {
                    Toggle("启用多层 System Prompt", isOn: Binding(get: { store.settings.options.promptEnabled }, set: { store.updateGlobalOption(\.promptEnabled, $0) }))
                    Text("勾选的应用级预设会与应用默认提示词一起作用于每次请求。各层级按选择顺序合并，后级优先。").font(.caption).foregroundColor(.secondary)
                    PresetSelection(selected: Binding(get: { store.settings.options.presetIDs }, set: { store.updateGlobalOption(\.presetIDs, $0) }), presets: store.settings.options.presets)
                }
                ForEach(store.settings.options.presets) { preset in
                    Card {
                        Button { sheet = .edit(preset) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(preset.name).font(.headline)
                                Text(preset.text).font(.footnote).foregroundColor(.secondary).lineLimit(3)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.foregroundColor(.primary)
                        HStack {
                            Toggle("启用", isOn: Binding(get: { preset.enabled }, set: { var p = preset; p.enabled = $0; store.savePreset(p) }))
                            Button("复制") { var p = preset; p.id = UUID(); p.name += " 副本"; store.savePreset(p) }.frame(minWidth: 44, minHeight: 44)
                            Button("删除") { deleting = preset }.foregroundColor(.red).frame(minWidth: 44, minHeight: 44)
                        }.font(.footnote)
                    }
                }
                Button("创建提示词预设") { sheet = .edit(PromptPreset(name: "新预设", text: "")) }.frame(minHeight: 44)
                HStack {
                    Button("导入 JSON") { importing = true }.frame(minHeight: 44)
                    Spacer()
                    Button("导出 JSON") {
                        do { sheet = .share(try ShareFile.make(data: JSONEncoder().encode(store.settings.options.presets), ext: "json")) }
                        catch { store.notice = error.localizedDescription }
                    }.frame(minHeight: 44)
                }
            }.padding(18)
        }.background(Theme.background).navigationTitle("提示词预设")
            .sheet(item: $sheet) { destination in
                switch destination {
                case .edit(let p): PresetEditor(preset: p).environmentObject(store)
                case .share(let file): ShareSheet(url: file.url)
                }
            }
            .alert(item: $deleting) { p in Alert(title: Text("删除预设？"), message: Text(p.name), primaryButton: .destructive(Text("删除")) { store.deletePreset(p.id) }, secondaryButton: .cancel(Text("取消"))) }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get(); let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    try store.importPresets(Data(contentsOf: url, options: .mappedIfSafe))
                } catch { store.notice = error.localizedDescription }
            }
    }
}
struct PresetEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.presentationMode) var presentation
    @State var preset: PromptPreset
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 18) {
                TextField("名称", text: $preset.name).textFieldStyle(RoundedBorderTextFieldStyle())
                TextEditor(text: $preset.text).padding(8).background(Theme.card).cornerRadius(14)
                Toggle("启用此预设", isOn: $preset.enabled)
            }.padding(18).navigationTitle("编辑预设").navigationBarTitleDisplayMode(.inline)
                .navigationBarItems(leading: Button("取消") { presentation.wrappedValue.dismiss() }, trailing: Button("保存") {
                    store.savePreset(preset); presentation.wrappedValue.dismiss()
                }.disabled(preset.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || preset.text.count > 32000))
        }.navigationViewStyle(StackNavigationViewStyle())
    }
}
