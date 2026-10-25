import SwiftUI
import UIKit

struct MessageRow: View, Equatable {
    let message: Message
    let fontSize: Double
    let isActive: Bool
    var onRetry: () -> Void
    var onEdit: () -> Void
    var character: CharacterIdentity? = nil
    var greetingID: UUID? = nil
    @State private var expanded = false
    @State private var toolsExpanded = false
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.message == rhs.message && lhs.fontSize == rhs.fontSize && lhs.isActive == rhs.isActive && lhs.character == rhs.character && lhs.greetingID == rhs.greetingID
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                if message.role == .assistant, let identity = character { CharacterAvatar(identity: identity).frame(width: 28, height: 28) }
                else { Image(systemName: message.role == .user ? "person.crop.circle.fill" : "sparkles")
                    .foregroundColor(message.role == .user ? .secondary : Theme.accent) }
                Text(message.role == .user ? "你" : (character?.name ?? "AKI")).font(.system(size: 11, weight: .bold, design: .rounded)).foregroundColor(.secondary)
                if message.id == greetingID { Text("开场白 · 本地").font(.caption2).foregroundColor(.secondary) }
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
                AttachmentThumbnail(attachment: attachment).frame(maxHeight: 220).cornerRadius(12)
            }
            if !message.content.isEmpty {
                if isActive { StreamingMarkdownView(source: message.content, size: fontSize) }
                else { MarkdownView(source: message.content, size: fontSize) }
            }
            if let records = message.toolRecords, !records.isEmpty {
                DisclosureGroup(isExpanded: $toolsExpanded) {
                    ForEach(records) { record in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(record.call.function.name + (record.failed ? " · 失败" : " · 完成")).font(.caption).foregroundColor(record.failed ? .red : .secondary)
                            NativeRichText(text: record.call.function.arguments + "\n" + String(record.result.prefix(12000)), size: max(12, fontSize - 3))
                        }.padding(.vertical, 8)
                    }
                } label: { Text("工具记录 \(records.count) · 搜索 \(records.filter { $0.call.function.name == "web_search" }.count) 次（可能产生费用）").font(.caption) }
            }
            if let sources = message.sources, !sources.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("来源").font(.caption).foregroundColor(.secondary)
                    ForEach(Array(sources.enumerated()), id: \.element.id) { item in
                        if let url = ToolPolicy.publicURL(item.element.url) {
                            Link("[\(item.offset + 1)] " + item.element.title, destination: url).font(.footnote).frame(minHeight: 44, alignment: .leading)
                        }
                    }
                }
            }
            if let error = message.error { Text(error).font(.caption).foregroundColor(.red) }
            if message.state == .stopped { Text("已停止 · 内容已保留").font(.caption).foregroundColor(.secondary) }
            if message.finishReason == "length" { Text("已达到最大输出长度，可在设置中提高上限。").font(.caption).foregroundColor(.secondary) }
            if let usage = message.usage {
                Text("输入 \(usage.prompt_tokens ?? 0) · 输出 \(usage.completion_tokens ?? 0) · 共 \(usage.total_tokens ?? 0) tokens")
                    .font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary)
            }
            if !isActive {
                HStack(spacing: 20) {
                    Button { UIPasteboard.general.string = message.content } label: { Image(systemName: "doc.on.doc").frame(width: 44, height: 44) }.accessibilityLabel("复制消息")
                    if message.role == .user {
                        Button(action: onEdit) { Image(systemName: "pencil").frame(width: 44, height: 44) }.accessibilityLabel("编辑并重新发送")
                    } else if message.id != greetingID {
                        Button(action: onRetry) { Label("重新生成", systemImage: "arrow.clockwise").frame(minHeight: 44) }.accessibilityLabel("重试回答")
                    }
                }.font(.system(size: 11)).foregroundColor(.secondary)
            }
        }.padding(message.role == .user ? 16 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(message.role == .user ? Theme.card : Color.clear).cornerRadius(18)
    }
}
