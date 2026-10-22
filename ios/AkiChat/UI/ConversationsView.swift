import SwiftUI
import UniformTypeIdentifiers

struct ConversationsView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.presentationMode) var presentation
    @State private var query = ""
    @State private var deleting: Conversation?
    @State private var renaming: Conversation?
    @State private var title = ""
    @State private var sharing: ShareFile?
    @State private var importing = false
    var filtered: [Conversation] {
        store.conversations.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) ||
            $0.messages.contains { $0.content.localizedCaseInsensitiveContains(query) } }
            .sorted { $0.updatedAt > $1.updatedAt }
    }
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 14) {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                        TextField("搜索标题或消息", text: $query)
                    }.padding(14).background(Theme.card).cornerRadius(14)
                    ForEach(filtered) { c in
                        Button { store.selectConversation(c.id); presentation.wrappedValue.dismiss() } label: {
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
                            Button { title = c.title; renaming = c } label: { Label("重命名", systemImage: "pencil") }
                            Button { export(c, json: true) } label: { Label("导出 JSON", systemImage: "square.and.arrow.up") }
                            Button { export(c, json: false) } label: { Label("导出 Markdown", systemImage: "doc.text") }
                            Button { deleting = c } label: { Label("删除", systemImage: "trash") }
                        }
                    }
                    if filtered.isEmpty { Text("没有匹配的会话").foregroundColor(.secondary).padding(40) }
                    Text("长按会话可重命名、导出或删除").font(.caption).foregroundColor(.secondary)
                }.padding(18)
            }.background(Theme.background).navigationTitle("对话空间")
                .navigationBarItems(leading: Button("导入 JSON") { importing = true }, trailing: Button {
                    store.newConversation(); presentation.wrappedValue.dismiss()
                } label: { Image(systemName: "plus") })
        }.navigationViewStyle(StackNavigationViewStyle())
            .alert(item: $deleting) { c in
                Alert(title: Text("删除“\(c.title)”？"), message: Text("此操作无法撤销。"),
                    primaryButton: .destructive(Text("删除")) { store.deleteConversation(c.id) }, secondaryButton: .cancel(Text("取消")))
            }
            .sheet(item: $renaming) { c in
                NavigationView {
                    VStack(spacing: 20) {
                        TextField("会话名称", text: $title).textFieldStyle(RoundedBorderTextFieldStyle())
                        Button("保存") { store.rename(c.id, title: title); renaming = nil }
                        Spacer()
                    }.padding().navigationTitle("重命名").navigationBarItems(trailing: Button("取消") { renaming = nil })
                }.navigationViewStyle(StackNavigationViewStyle())
            }
            .sheet(item: $sharing) { ShareSheet(url: $0.url) }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get()
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    try store.importArchive(Data(contentsOf: url, options: .mappedIfSafe))
                } catch { store.notice = error.localizedDescription }
            }
    }
    private func export(_ c: Conversation, json: Bool) {
        do { sharing = try ShareFile.make(data: json ? ExportService.json([c]) : Data(ExportService.markdown(c).utf8), ext: json ? "json" : "md") }
        catch { store.notice = error.localizedDescription }
    }
}
