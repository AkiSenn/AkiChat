import SwiftUI

/// The only interactive thinking controls; hosted by ThinkingPanel.
struct ReasoningControls: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        Group {
            if let p = store.provider, p.supportsThinking, let c = store.current {
                Toggle("深度思考", isOn: Binding(get: { ThinkingPolicy.active(p, c) }, set: { store.setThinking($0) }))
                    .disabled(store.isGenerating || !ThinkingPolicy.canDisable(p)).accessibilityIdentifier("thinking-toggle")
                if ThinkingPolicy.forced(p) {
                    Text("当前模型无法关闭深度思考").font(.footnote).foregroundColor(.secondary).accessibilityIdentifier("thinking-forced")
                } else if !ThinkingPolicy.canDisable(p) {
                    Text("服务商未声明关闭思考的协议，当前按模型默认行为执行。").font(.footnote).foregroundColor(.secondary)
                }
                let levels = ThinkingPolicy.levels(p)
                Picker("推理强度", selection: Binding(get: { ThinkingPolicy.selection(p, c) }, set: { store.setReasoningLevel($0) })) {
                    Text("默认（由模型决定）").tag("default")
                    ForEach(levels, id: \.self) { Text($0).tag($0) }
                }.pickerStyle(MenuPickerStyle()).disabled(store.isGenerating || !ThinkingPolicy.active(p, c))
                    .accessibilityIdentifier("thinking-effort-picker")
                Text("实际档位：" + (ThinkingPolicy.effort(p, c) ?? "默认（不发送可选强度）"))
                    .font(.caption).foregroundColor(.secondary)
                if levels.isEmpty { Text("未提供可选强度信息；不会猜测支持的档位。").font(.caption).foregroundColor(.secondary) }
            } else {
                Text("未提供可用的思考能力信息。可刷新当前模型目录，或核实服务商协议后在模型库设置兼容覆盖。").font(.subheadline).foregroundColor(.secondary)
            }
        }
    }
}
