import SwiftUI
import UIKit

struct ChatView: View {
    @EnvironmentObject var store: AppStore
    @State private var sheet: ChatSheet?
    @State private var editedText = ""
    @State private var showDrawer = false
    private enum ChatSheet: Identifiable {
        case sessions, settings, models, photos, advanced, edit(Message)
        var id: String {
            switch self {
            case .sessions: return "sessions"
            case .settings: return "settings"
            case .models: return "models"
            case .photos: return "photos"
            case .advanced: return "advanced"
            case .edit(let message): return message.id.uuidString
            }
        }
    }
    var body: some View {
        ZStack(alignment: .leading) {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.3)
            messageList
            ChatComposer(draft: store.composer, onPhotos: { sheet = .photos }, onAdvanced: { sheet = .advanced })
        }
        if showDrawer {
            Color.black.opacity(0.3).edgesIgnoringSafeArea(.all).onTapGesture { withAnimation(.easeOut(duration: 0.2)) { showDrawer = false } }
            ConversationsView(onSelect: { withAnimation(.easeOut(duration: 0.2)) { showDrawer = false } }, onSettings: { showDrawer = false; sheet = .settings }).environmentObject(store)
                .frame(width: min(350, UIScreen.main.bounds.width * 0.86)).background(Theme.background).transition(.move(edge: .leading))
        }
        }
        .background(Theme.background.edgesIgnoringSafeArea(.all))
        .sheet(item: $sheet) { destination in
            switch destination {
            case .sessions: ConversationsView().environmentObject(store)
            case .settings: SettingsView().environmentObject(store)
            case .models: modelPicker
            case .advanced: AdvancedConversationView().environmentObject(store)
            case .photos:
                PhotoPicker(completion: { result in
                    switch result {
                    case .success(let image): store.addImage(image)
                    case .failure(let error): store.notice = error.localizedDescription
                    }
                }, dimension: store.settings.options.imageDimension, quality: store.settings.options.imageQuality)
            case .edit(let message): editSheet(message)
            }
        }
        .alert(isPresented: Binding(get: { store.notice != nil }, set: { if !$0 { store.notice = nil } })) {
            Alert(title: Text("AkiChat"), message: Text(store.notice ?? ""), dismissButton: .default(Text("好")))
        }
    }
    private func editSheet(_ message: Message) -> some View {
        NavigationView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("发送后将替换该消息及其后续回答。图片会保留。").font(.footnote).foregroundColor(.secondary)
                    TextEditor(text: $editedText).padding(8).background(Theme.card).cornerRadius(12)
                    Button("编辑并重新发送") {
                        store.editAndResend(message.id, text: editedText); sheet = nil
                    }.disabled(editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && message.images.isEmpty)
                }.padding().navigationTitle("编辑消息")
                .navigationBarItems(trailing: Button("取消") { sheet = nil })
            }.navigationViewStyle(StackNavigationViewStyle())
    }
    private var header: some View {
        HStack(spacing: 12) {
            IconButton(symbol: "line.horizontal.3", label: "会话抽屉") {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                withAnimation(.easeOut(duration: 0.22)) { showDrawer = true }
            }
            Button {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                sheet = .models
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.providerName).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                    HStack(spacing: 4) {
                        Circle().fill(store.isGenerating ? Color.orange : Theme.accent).frame(width: 5, height: 5)
                        Text(store.selectedModelLabel).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                        Image(systemName: "chevron.down").font(.system(size: 9)).foregroundColor(.secondary)
                    }
                }.foregroundColor(.primary)
            }.accessibilityIdentifier("model-selector")
            Spacer(minLength: 0)
            IconButton(symbol: "square.and.pencil", label: "新建对话") { store.newConversation() }
        }.padding(.horizontal, 18).padding(.vertical, 12).background(Theme.background)
    }
    private var messageList: some View {
        ChatTimelineView(presentation: store.chat, fontSize: store.settings.fontSize,
                         onRetry: { store.regenerate(from: $0) },
                         onEdit: { editedText = $0.content; sheet = .edit($0) },
                         welcome: AnyView(welcome))
    }
    private var welcome: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer().frame(height: 55)
            Image(systemName: "sparkles").font(.system(size: 36)).foregroundColor(Theme.accent)
            Text("让想法，\n慢慢展开。").font(.system(.largeTitle, design: .rounded)).bold()
            Text("写作、探索、理解。\n从一个问题开始，留下有价值的对话。")
                .foregroundColor(.secondary).font(.system(size: 16)).lineSpacing(6)
            Button { sheet = .settings } label: {
                Label("配置你的 API", systemImage: "slider.horizontal.3").padding(14)
                    .background(Theme.card).cornerRadius(14)
            }
            Text("密钥保存在设备 Keychain，聊天记录保存在本机。").font(.caption).foregroundColor(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var modelPicker: some View {
        ModelSelectionPanel(dismiss: { sheet = nil }).environmentObject(store)
    }

}
