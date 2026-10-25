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
                                }.accessibilityLabel("�Ƴ�ͼƬ")
                            }
                        }
                    }
                }
            }
            HStack(alignment: .bottom, spacing: 10) {
                GrowingTextView(text: Binding(get: { draft.text }, set: { store.setDraft($0) }), height: $inputHeight)
                    .frame(height: inputHeight)
                    .accessibilityLabel("��Ϣ�����")
                Button {
                    if store.isGenerating { store.stop() } else {
                        store.send()
                    }
                } label: {
                    Image(systemName: store.isGenerating ? "stop.fill" : "arrow.up")
                        .font(.system(size: 18, weight: .bold)).foregroundColor(.white)
                        .frame(width: 42, height: 42).background(Theme.accent).clipShape(Circle())
                }.accessibilityLabel(store.isGenerating ? "ֹͣ����" : "����")
                .disabled(!store.isGenerating && draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft.images.isEmpty)
            }
            HStack {
                Button { onPhotos() } label: { Image(systemName: "photo").frame(width: 44, height: 44) }
                    .disabled(store.isGenerating || store.provider?.supportsVision != true)
                    .accessibilityLabel("���������ͼƬ")
                    .accessibilityHint(store.provider?.supportsVision == true ? "�������" : "��ǰģ�Ͳ�֧��ͼƬ�����л�ģ��")
                featureButton(thinkingLabel, symbol: "sparkles", active: thinkingActive, id: "thinking-button", action: onThinking)
                featureButton(store.current?.options.searchMode == .always ? "ÿ������" : "����", symbol: "globe", active: searchActive, id: "search-button", action: onSearch)
                Spacer()
                Button { onAdvanced() } label: { Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44) }.accessibilityLabel("�Ự����̨")
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
        }.frame(minHeight: 44).accessibilityIdentifier(id).accessibilityValue(active ? "�ѿ���" : "�ѹر�")
    }
    private var thinkingActive: Bool { ThinkingPolicy.active(store.provider, store.current) }
    private var searchActive: Bool {
        let mode = store.current?.options.searchMode ?? .off
        return mode != .off && store.searchConsent && store.searchCredentialAvailable && (mode != .automatic || store.provider?.options.supportsTools == true)
    }
    private var thinkingLabel: String {
        guard thinkingActive, let p = store.provider, let c = store.current else { return "���˼��" }
        return "˼�� �� " + (ThinkingPolicy.effort(p, c) ?? "Ĭ��")
    }
}
