import SwiftUI
import UIKit

struct MessageRow: View, Equatable {
    let message: Message
    let fontSize: Double
    let isActive: Bool
    var onRetry: () -> Void
    var onEdit: () -> Void
    @State private var expanded = false
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.message == rhs.message && lhs.fontSize == rhs.fontSize && lhs.isActive == rhs.isActive
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: message.role == .user ? "person.crop.circle.fill" : "sparkles")
                    .foregroundColor(message.role == .user ? .secondary : Theme.accent)
                Text(message.role == .user ? "你" : "AKI").font(.system(size: 11, weight: .bold, design: .rounded)).foregroundColor(.secondary)
                Spacer()
                if isActive { ProgressView().scaleEffect(0.7) }
            }
            if !message.reasoning.isEmpty || (isActive && message.content.isEmpty) {
                VStack(alignment: .leading, spacing: 8) {
                    Button { withAnimation(.easeOut(duration: 0.18)) { expanded.toggle() } } label: {
                        HStack {
                            Image(systemName: "sparkles")
                            Text(isActive && message.content.isEmpty ? "正在思考…" : "思考内容")
                            Spacer()
                            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        }.font(.system(size: 12, weight: .medium)).foregroundColor(.secondary)
                    }
                    if expanded { NativeRichText(text: message.reasoning, size: max(12, fontSize - 2), color: .secondaryLabel) }
                }.padding(12).background(Theme.accent.opacity(0.055)).cornerRadius(12)
            }
            ForEach(message.images) { attachment in
                if let image = UIImage(data: attachment.jpeg) {
                    Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 220).cornerRadius(12)
                }
            }
            if !message.content.isEmpty {
                if isActive { NativeRichText(text: message.content, size: fontSize) }
                else { MarkdownView(source: message.content, size: fontSize) }
            }
            if let error = message.error { Text(error).font(.caption).foregroundColor(.red) }
            if message.state == .stopped { Text("已停止 · 内容已保留").font(.caption).foregroundColor(.secondary) }
            if let usage = message.usage {
                Text("输入 \(usage.prompt_tokens ?? 0) · 输出 \(usage.completion_tokens ?? 0) · 共 \(usage.total_tokens ?? 0) tokens")
                    .font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary)
            }
            if !isActive {
                HStack(spacing: 20) {
                    Button { UIPasteboard.general.string = message.content } label: { Image(systemName: "doc.on.doc") }.accessibilityLabel("复制消息")
                    if message.role == .user {
                        Button(action: onEdit) { Image(systemName: "pencil") }.accessibilityLabel("编辑并重新发送")
                    } else {
                        Button(action: onRetry) { Label("重新生成", systemImage: "arrow.clockwise") }.accessibilityLabel("重试回答")
                    }
                }.font(.system(size: 11)).foregroundColor(.secondary)
            }
        }.padding(message.role == .user ? 16 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(message.role == .user ? Theme.card : Color.clear).cornerRadius(18)
    }
}
