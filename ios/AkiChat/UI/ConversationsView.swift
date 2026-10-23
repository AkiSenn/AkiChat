import SwiftUI
import UniformTypeIdentifiers

struct ConversationsView: View {
    var onSelect: (() -> Void)? = nil
    var onSettings: (() -> Void)? = nil
    @EnvironmentObject var store: AppStore
    @Environment(\.presentationMode) var presentation
    @State private var query = ""
    @State private var deleting: Conversation?
    @State private var title = ""
    @State private var sheet: ConversationSheet?
    @State private var importing = false
    private enum ConversationSheet: Identifiable {
        case rename(Conversation), share(ShareFile)
        var id: UUID {
            switch self { case .rename(let c): return c.id; case .share(let file): return file.id }
        }
    }
    var filtered: [Conversation] {
        store.conversations.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) ||
            $0.messages.contains { $0.content.localizedCaseInsensitiveContains(query) } }
            .sorted { $0.updatedAt > $1.updatedAt }
    }
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 14) {
                    NoticeBanner()
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                        TextField("搜索标题或消息", text: $query)
                    }.padding(14).background(Theme.card).cornerRadius(14)
                    ForEach(filtered) { c in
                        Button { store.selectConversation(c.id); close() } label: {
                            Card {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(c.title).font(.headline).foregroundColor(.primary).lineLimit(1)
                                        Text(c.messages.last?.content ?? "一个新的开始").font(.subheadline).foregroundColor(.secondary).lineLimit(2)
                                        Text(c.updatedAt, style: .date).font(.caption2).foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    if c.id == store.selectedID { Image(systemName: "circle.fill").font(.system(size: 7)).foregroundColor(Theme.accent) }
                                }
                            }
                        }.contextMenu {
                            Button { title = c.title; sheet = .rename(c) } label: { Label("重命名", systemImage: "pencil") }
                            Button { export(c, json: true) } label: { Label("导出 JSON", systemImage: "square.and.arrow.up") }
                            Button { export(c, json: false) } label: { Label("导出 Markdown", systemImage: "doc.text") }
                            Button { deleting = c } label: { Label("删除", systemImage: "trash") }
                        }
                    }
                    if filtered.isEmpty { Text("没有匹配的会话").foregroundColor(.secondary).padding(40) }
                    Text("长按会话可重命名、导出或删除").font(.caption).foregroundColor(.secondary)
                    if let onSettings = onSettings { Button(action: onSettings) { Label("应用设置", systemImage: "gearshape").frame(minHeight: 44) } }
                }.padding(18)
            }.background(Theme.background).navigationTitle("对话空间")
                .navigationBarItems(leading: HStack { Button("完成") { close() }; Button("导入") { importing = true } }, trailing: Button {
                    store.newConversation(); close()
                } label: { Image(systemName: "plus") })
        }.navigationViewStyle(StackNavigationViewStyle())
            .alert(item: $deleting) { c in
                Alert(title: Text("删除“\(c.title)”？"), message: Text("此操作无法撤销。"),
                    primaryButton: .destructive(Text("删除")) { store.deleteConversation(c.id) }, secondaryButton: .cancel(Text("取消")))
            }
            .sheet(item: $sheet) { destination in
                switch destination {
                case .rename(let c): renameEditor(c)
                case .share(let file): ShareSheet(url: file.url)
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get()
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    try store.importArchive(Data(contentsOf: url, options: .mappedIfSafe))
                } catch { store.notice = error.localizedDescription }
            }
    }
    private func close() { if let onSelect = onSelect { onSelect() } else { presentation.wrappedValue.dismiss() } }
    private func renameEditor(_ c: Conversation) -> some View {
        NavigationView {
            VStack(spacing: 20) {
                TextField("会话名称", text: $title).textFieldStyle(RoundedBorderTextFieldStyle())
                Button("保存") { store.rename(c.id, title: title); sheet = nil }
                Spacer()
            }.padding().navigationTitle("重命名").navigationBarItems(trailing: Button("取消") { sheet = nil })
        }.navigationViewStyle(StackNavigationViewStyle())
    }
    private func export(_ c: Conversation, json: Bool) {
        let latest = store.exportConversations().first(where: { $0.id == c.id }) ?? c
        do { sheet = .share(try ShareFile.make(data: json ? ExportService.json([latest]) : Data(ExportService.markdown(latest).utf8), ext: json ? "json" : "md")) }
        catch { store.notice = error.localizedDescription }
    }
}
