import SwiftUI
import UIKit

struct ChatComposer: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject var draft: ComposerState
    var onPhotos: () -> Void
    var onAdvanced: () -> Void
    var onThinking: () -> Void
    var onSearch: () -> Void
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
                featureButton(thinkingLabel, symbol: "sparkles", active: thinkingActive, id: "thinking-button", action: onThinking)
                featureButton(store.current?.options.searchMode == .always ? "每次搜索" : "联网", symbol: "globe", active: searchActive, id: "search-button", action: onSearch)
                Spacer()
                Button { onAdvanced() } label: { Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44) }.accessibilityLabel("会话控制台")
            }.foregroundColor(Theme.accent)
        }.padding(14).background(BlurView()).cornerRadius(24)
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.primary.opacity(0.04)))
            .padding(.horizontal, 14).padding(.bottom, 8)
    }
    private func featureButton(_ title: String, symbol: String, active: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 10).padding(.vertical, 9)
                .foregroundColor(active ? Theme.accent : .secondary)
                .background(active ? Theme.accent.opacity(0.12) : Color.clear).cornerRadius(14)
        }.frame(minHeight: 44).accessibilityIdentifier(id).accessibilityValue(active ? "已开启" : "已关闭")
    }
    private var thinkingActive: Bool { ThinkingPolicy.active(store.provider, store.current) }
    private var searchActive: Bool {
        let mode = store.current?.options.searchMode ?? .off
        return mode != .off && store.searchConsent && store.searchCredentialAvailable && (mode != .automatic || store.provider?.options.supportsTools == true)
    }
    private var thinkingLabel: String {
        guard thinkingActive, let p = store.provider, let c = store.current else { return "深度思考" }
        return "思考 · " + (ThinkingPolicy.effort(p, c) ?? "默认")
    }
}
