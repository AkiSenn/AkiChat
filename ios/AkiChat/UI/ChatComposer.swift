import SwiftUI
import UIKit

struct ChatComposer: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject var draft: ComposerState
    var onPhotos: () -> Void
    var onAdvanced: () -> Void
    @State private var inputHeight: CGFloat = 42
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !draft.images.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(draft.images) { attachment in
                            ZStack(alignment: .topTrailing) {
                                AttachmentThumbnail(attachment: attachment, maxPixel: 160).frame(width: 64, height: 64).clipped().cornerRadius(10)
                                Button { store.removeImage(attachment.id) } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundColor(.white).background(Color.black.opacity(0.4)).clipShape(Circle())
                                }.accessibilityLabel("移除图片")
                            }
                        }
                    }
                }
            }
            HStack(alignment: .bottom, spacing: 10) {
                GrowingTextView(text: Binding(get: { draft.text }, set: { store.setDraft($0) }), height: $inputHeight)
                    .frame(height: inputHeight)
                    .accessibilityLabel("消息输入框")
                Button {
                    if store.isGenerating { store.stop() } else {
                        store.send()
                    }
                } label: {
                    Image(systemName: store.isGenerating ? "stop.fill" : "arrow.up")
                        .font(.system(size: 18, weight: .bold)).foregroundColor(.white)
                        .frame(width: 42, height: 42).background(Theme.accent).clipShape(Circle())
                }.accessibilityLabel(store.isGenerating ? "停止生成" : "发送")
                .disabled(!store.isGenerating && draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft.images.isEmpty)
            }
            HStack {
                Button { onPhotos() } label: { Image(systemName: "photo").frame(width: 44, height: 44) }
                    .disabled(store.isGenerating || store.provider?.supportsVision != true)
                    .accessibilityLabel("从相册添加图片")
                    .accessibilityHint(store.provider?.supportsVision == true ? "最多四张" : "当前模型不支持图片，请切换模型")
                if store.provider?.supportsThinking == true && (store.provider?.kind == .deepSeek || store.provider?.kind == .workBuddy) {
                    Button {
                        if let provider = store.provider, provider.kind == .workBuddy && !HubReasoning.canDisable(provider) { onAdvanced() }
                        else { store.setThinking(!store.thinking) }
                    } label: {
                        Label(thinkingLabel, systemImage: "sparkles").font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(thinkingActive ? Theme.accent.opacity(0.12) : Color.secondary.opacity(0.08)).cornerRadius(12)
                    }.frame(minHeight: 44).disabled(store.isGenerating)
                }
                Button {
                    guard store.settings.options.externalConsent else { store.notice = "联网会向 DeepSeek 发送查询并可能产生费用，请在会话控制台中启用同意开关。"; onAdvanced(); return }
                    let mode = store.current?.options.searchMode ?? .off
                    store.updateConversationOption(\.toolsEnabled, true)
                    store.updateConversationOption(\.prefixEnabled, false)
                    store.updateConversationOption(\.searchMode, mode == .off ? SearchMode.automatic : (mode == .automatic ? SearchMode.always : SearchMode.off))
                } label: {
                    Label(store.current?.options.searchMode == .always ? "强制联网" : "联网", systemImage: "globe")
                        .font(.caption).padding(.horizontal, 8).frame(minHeight: 44)
                        .background(store.current?.options.searchMode != .off ? Theme.accent.opacity(0.1) : Color.clear).cornerRadius(12)
                }.disabled(store.isGenerating || store.provider?.options.supportsTools != true)
                    .accessibilityHint("依次切换关闭、自动与每条强制搜索")
                Spacer()
                Button { onAdvanced() } label: { Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44) }.accessibilityLabel("会话控制台")
            }.foregroundColor(Theme.accent)
        }.padding(14).background(BlurView()).cornerRadius(24)
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.primary.opacity(0.04)))
            .padding(.horizontal, 14).padding(.bottom, 8)
    }
    private var thinkingActive: Bool {
        if let p = store.provider, p.kind == .workBuddy { return store.thinking || !HubReasoning.canDisable(p) }
        return store.thinking
    }
    private var thinkingLabel: String {
        guard let p = store.provider, p.kind == .workBuddy, let c = store.current else { return "深度思考" }
        return "思考 · " + (HubReasoning.resolve(provider: p, conversation: c) ?? "默认")
    }
}
