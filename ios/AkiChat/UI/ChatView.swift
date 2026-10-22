import SwiftUI
import UIKit

struct ChatView: View {
    @EnvironmentObject var store: AppStore
    @State private var sheet: ChatSheet?
    @State private var followLatest = true
    @State private var editedText = ""
    private enum ChatSheet: Identifiable {
        case sessions, settings, models, photos, edit(Message)
        var id: String {
            switch self {
            case .sessions: return "sessions"
            case .settings: return "settings"
            case .models: return "models"
            case .photos: return "photos"
            case .edit(let message): return message.id.uuidString
            }
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.3)
            messageList
            composer
        }
        .background(Theme.background.edgesIgnoringSafeArea(.all))
        .sheet(item: $sheet) { destination in
            switch destination {
            case .sessions: ConversationsView().environmentObject(store)
            case .settings: SettingsView().environmentObject(store)
            case .models: modelPicker
            case .photos:
                PhotoPicker { result in
                    switch result {
                    case .success(let image): store.addImage(image)
                    case .failure(let error): store.notice = error.localizedDescription
                    }
                }
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
            IconButton(symbol: "line.horizontal.3", label: "会话列表") { sheet = .sessions }
            Button { sheet = .models } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.provider?.displayName ?? "选择模型").font(.system(size: 16, weight: .semibold)).lineLimit(1)
                    HStack(spacing: 4) {
                        Circle().fill(store.isGenerating ? Color.orange : Theme.accent).frame(width: 5, height: 5)
                        Text(store.isGenerating ? "正在生成" : "AkiChat · 本地保存").font(.system(size: 11)).foregroundColor(.secondary)
                        Image(systemName: "chevron.down").font(.system(size: 9)).foregroundColor(.secondary)
                    }
                }.foregroundColor(.primary)
            }
            Spacer(minLength: 0)
            IconButton(symbol: "square.and.pencil", label: "新建对话") { store.newConversation() }
        }.padding(.horizontal, 18).padding(.vertical, 12)
    }
    private var messageList: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        if store.messages.isEmpty { welcome }
                        ForEach(store.messages) { message in
                            MessageRow(message: message, fontSize: store.settings.fontSize,
                                isActive: store.isGenerating && message.state == .generating,
                                onRetry: { store.regenerate(from: message.id) },
                                onEdit: { editedText = message.content; sheet = .edit(message) })
                                .equatable().id(message.id)
                        }
                        Color.clear.frame(height: 1).id("latest")
                    }.padding(20).background(GeometryReader { geometry in
                        Color.clear.preference(key: MessageHeightKey.self, value: geometry.size.height)
                    })
                }
                .simultaneousGesture(DragGesture().onChanged { _ in followLatest = false })
                .onPreferenceChange(MessageHeightKey.self) { _ in
                    if followLatest { proxy.scrollTo("latest", anchor: .bottom) }
                }
                .onChange(of: store.selectedID) { _ in followLatest = true; proxy.scrollTo("latest", anchor: .bottom) }
                if !followLatest {
                    IconButton(symbol: "arrow.down", label: "返回最新消息") {
                        followLatest = true
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("latest", anchor: .bottom) }
                    }.padding(16)
                }
            }
        }
    }
    private var welcome: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer().frame(height: 55)
            Image(systemName: "sparkles").font(.system(size: 36)).foregroundColor(Theme.accent)
            Text("让想法，\n慢慢展开。").font(.system(size: 34, weight: .bold, design: .rounded))
            Text("写作、探索、理解。\n从一个问题开始，留下有价值的对话。")
                .foregroundColor(.secondary).font(.system(size: 16)).lineSpacing(6)
            Button { sheet = .settings } label: {
                Label("配置你的 API", systemImage: "slider.horizontal.3").padding(14)
                    .background(Theme.card).cornerRadius(14)
            }
            Text("密钥保存在设备 Keychain，聊天记录保存在本机。").font(.caption).foregroundColor(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !store.draftImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(store.draftImages) { attachment in
                            ZStack(alignment: .topTrailing) {
                                if let image = UIImage(data: attachment.jpeg) {
                                    Image(uiImage: image).resizable().scaledToFill().frame(width: 64, height: 64).clipped().cornerRadius(10)
                                }
                                Button { store.removeImage(attachment.id) } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundColor(.white).background(Color.black.opacity(0.4)).clipShape(Circle())
                                }.accessibilityLabel("移除图片")
                            }
                        }
                    }
                }
            }
            HStack(alignment: .bottom, spacing: 10) {
                GrowingTextView(text: Binding(get: { store.draft }, set: { store.setDraft($0) }))
                    .frame(height: store.composerHeight)
                    .accessibilityLabel("消息输入框")
                Button {
                    if store.isGenerating { store.stop() } else {
                        followLatest = true; store.send()
                    }
                } label: {
                    Image(systemName: store.isGenerating ? "stop.fill" : "arrow.up")
                        .font(.system(size: 18, weight: .bold)).foregroundColor(.white)
                        .frame(width: 42, height: 42).background(Theme.accent).clipShape(Circle())
                }.accessibilityLabel(store.isGenerating ? "停止生成" : "发送")
                .disabled(!store.isGenerating && store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && store.draftImages.isEmpty)
            }
            HStack {
                Button { sheet = .photos } label: { Image(systemName: "photo").frame(width: 36, height: 30) }
                    .disabled(store.isGenerating || store.provider?.supportsVision != true)
                    .accessibilityLabel("从相册添加图片")
                if store.provider?.supportsThinking == true && store.provider?.kind == .deepSeek {
                    Button { store.setThinking(!store.thinking) } label: {
                        Label("深度思考", systemImage: "sparkles").font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(store.thinking ? Theme.accent.opacity(0.12) : Color.secondary.opacity(0.08)).cornerRadius(12)
                    }.disabled(store.isGenerating)
                }
                Spacer()
                Button { sheet = .settings } label: { Image(systemName: "slider.horizontal.3").frame(width: 36, height: 30) }.accessibilityLabel("设置")
            }.foregroundColor(Theme.accent)
        }.padding(14).background(Theme.card).cornerRadius(24)
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.primary.opacity(0.04)))
            .padding(.horizontal, 14).padding(.bottom, 8)
    }
    private var modelPicker: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(store.providers) { provider in
                        NavigationLink(destination: ModelsView(providerID: provider.id, selecting: true, onSelect: { sheet = nil }).environmentObject(store)) {
                            Label("\(provider.name) · 模型库与发现", systemImage: "square.stack")
                        }.frame(minHeight: 44)
                        Button {
                            store.selectProvider(provider.id); sheet = nil
                        } label: {
                            Card {
                                HStack {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(provider.displayName).font(.headline)
                                        Text("\(provider.name) · \(provider.modelID)").font(.caption).foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    if store.provider?.id == provider.id { Image(systemName: "checkmark.circle.fill").foregroundColor(Theme.accent) }
                                }
                            }.foregroundColor(.primary)
                        }.disabled(store.isGenerating)
                    }
                }.padding()
            }.background(Theme.background).navigationTitle("选择模型")
                .navigationBarItems(trailing: Button("完成") { sheet = nil })
        }.navigationViewStyle(StackNavigationViewStyle())
    }
}

private struct MessageHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
