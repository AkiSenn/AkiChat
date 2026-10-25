import SwiftUI

/// The only interactive thinking controls; hosted by ThinkingPanel.
struct ReasoningControls: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        Group {
            if let p = store.provider, p.supportsThinking, let c = store.current {
                Toggle("���˼��", isOn: Binding(get: { ThinkingPolicy.active(p, c) }, set: { store.setThinking($0) }))
                    .disabled(store.isGenerating || !ThinkingPolicy.canDisable(p)).accessibilityIdentifier("thinking-toggle")
                if ThinkingPolicy.forced(p) {
                    Text("��ǰģ���޷��ر����˼��").font(.footnote).foregroundColor(.secondary).accessibilityIdentifier("thinking-forced")
                } else if !ThinkingPolicy.canDisable(p) {
                    Text("������δ�����ر�˼����Э�飬��ǰ��ģ��Ĭ����Ϊִ�С�").font(.footnote).foregroundColor(.secondary)
                }
                let levels = ThinkingPolicy.levels(p)
                Picker("����ǿ��", selection: Binding(get: { ThinkingPolicy.selection(p, c) }, set: { store.setReasoningLevel($0) })) {
                    Text("Ĭ�ϣ���ģ�;�����").tag("default")
                    ForEach(levels, id: \.self) { Text($0).tag($0) }
                }.pickerStyle(MenuPickerStyle()).disabled(store.isGenerating || !ThinkingPolicy.active(p, c))
                    .accessibilityIdentifier("thinking-effort-picker")
                Text("ʵ�ʵ�λ��" + (ThinkingPolicy.effort(p, c) ?? "Ĭ�ϣ������Ϳ�ѡǿ�ȣ�"))
                    .font(.caption).foregroundColor(.secondary)
                if levels.isEmpty { Text("δ�ṩ��ѡǿ����Ϣ������²�֧�ֵĵ�λ��").font(.caption).foregroundColor(.secondary) }
            } else {
                Text("δ�ṩ���õ�˼��������Ϣ����ˢ�µ�ǰģ��Ŀ¼�����ʵ������Э�����ģ�Ϳ����ü��ݸ��ǡ�").font(.subheadline).foregroundColor(.secondary)
            }
        }
    }
}
