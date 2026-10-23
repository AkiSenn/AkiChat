import SwiftUI

struct ReasoningControls: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        Group {
            if let provider = store.provider, provider.supportsThinking {
                if provider.kind == .workBuddy {
                    hubControls(provider)
                } else if provider.kind == .deepSeek {
                    Toggle("深度思考", isOn: Binding(get: { store.thinking }, set: { store.setThinking($0) }))
                    Picker("推理强度", selection: Binding(get: { store.effort == .medium ? ReasoningEffort.high : store.effort }, set: { store.setEffort($0) })) {
                        ForEach([ReasoningEffort.low, .high, .max], id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(SegmentedPickerStyle())
                }
            }
        }.disabled(store.isGenerating)
    }
    private func hubControls(_ provider: Provider) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if HubReasoning.canDisable(provider) {
                Toggle("深度思考", isOn: Binding(get: { store.thinking }, set: { store.setThinking($0) }))
            } else {
                Text(provider.options.workBuddy?.canDisableThinking == false || provider.options.workBuddy?.alwaysReasoning == true
                     ? "此模型无法关闭思考" : "网关未声明关闭思考能力").font(.caption).foregroundColor(.secondary)
            }
            let levels = HubReasoning.levels(provider)
            if !levels.isEmpty {
                Picker("推理强度", selection: Binding(get: {
                    HubReasoning.resolve(provider: provider, conversation: store.current ?? Conversation(providerID: provider.id)) ?? levels[0]
                }, set: { store.updateConversationOption(\.hubReasoningEffort, Optional($0)) })) {
                    ForEach(levels, id: \.self) { Text($0).tag($0) }
                }.pickerStyle(MenuPickerStyle()).disabled(!store.thinking && HubReasoning.canDisable(provider))
            }
            if let current = store.current {
                let actual = HubReasoning.resolve(provider: provider, conversation: current)
                Text("本次推理档位：" + (actual ?? "网关默认（不发送参数）") + (HubReasoning.fixed(provider) == nil ? "" : " · 固定"))
                    .font(.caption).foregroundColor(.secondary)
                let requested = current.options.hubReasoningEffort ?? current.effort.rawValue
                if actual != nil && actual != "none" && requested != actual {
                    Text("所选 \(requested) 不适用，按模型目录使用 \(actual ?? "默认值")。").font(.caption).foregroundColor(.secondary)
                }
            }
        }
    }
}
