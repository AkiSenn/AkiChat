import SwiftUI

struct SearchPanel: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.presentationMode) private var presentation
    @State private var adding = false
    @State private var sourceName = "DeepSeek ����"
    @State private var key = ""
    @State private var status = ""
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 18) {
                    modeCard
                    sourceCard
                    privacyCard
                }.padding(18)
            }.background(Theme.background.edgesIgnoringSafeArea(.all))
                .navigationTitle("��������").navigationBarTitleDisplayMode(.inline)
                .navigationBarItems(leading: Button("�ر�") { presentation.wrappedValue.dismiss() }, trailing: Button("���") { presentation.wrappedValue.dismiss() })
        }.navigationViewStyle(StackNavigationViewStyle()).accessibilityIdentifier("search-panel")
    }
    private var modeCard: some View {
        Card {
            Text("����ģʽ").font(.headline)
            Picker("����ģʽ", selection: Binding(get: { store.current?.options.searchMode ?? .off }, set: { store.setSearchMode($0) })) {
                Text("�ر�").tag(SearchMode.off)
                Text("�Զ�����").tag(SearchMode.automatic).disabled(store.provider?.options.supportsTools != true)
                Text("ÿ������").tag(SearchMode.always)
            }.pickerStyle(SegmentedPickerStyle()).disabled(store.isGenerating).accessibilityIdentifier("search-mode-picker")
            Text("ÿ����Ϣ������������ǰִ����ʵ�������ٰѴ����ӵĲο����Ͻ�����ǰģ�͡�").font(.caption).foregroundColor(.secondary)
            if store.provider?.options.supportsTools != true {
                Text("��ǰģ�Ͳ�֧���Զ�������������ѡ��ÿ���������ͻ���Ԥ��������αװ��ģ���������ù��ߡ�").font(.footnote).foregroundColor(.secondary).accessibilityIdentifier("search-auto-unavailable")
            }
            if store.isGenerating { Text("�������ɣ�����ֻ������ֹͣ���޸ġ�").font(.caption).foregroundColor(.secondary) }
        }
    }
    private var sourceCard: some View {
        Card {
            Text("������Դ").font(.headline)
            Picker("DeepSeek �ٷ�����", selection: Binding(get: { store.settings.options.searchProviderID }, set: { store.selectSearchProvider($0) })) {
                Text("�׸� DeepSeek �ٷ�����").tag(nil as UUID?)
                ForEach(store.searchProviders) { Text($0.name).tag(Optional($0.id)) }
            }.accessibilityIdentifier("search-provider-picker").disabled(store.isGenerating)
            Text(store.searchCredentialAvailable ? "����ʹ�ô���Դ�����������Կ���������ʹ�õ�ǰ����ģ�͵���Կ��" : "���޿��õ�������Կ��������������Դ��")
                .font(.caption).foregroundColor(.secondary)
            DisclosureGroup("����������Դ", isExpanded: $adding) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("DeepSeek �ٷ� Search / Fetch �� https://api.deepseek.com").font(.caption).foregroundColor(.secondary)
                    TextField("��Դ����", text: $sourceName)
                    SecureField("DeepSeek �ٷ� API Key", text: $key).autocapitalization(.none).disableAutocorrection(true).accessibilityIdentifier("search-api-key")
                    Button("����������Կ") {
                        do {
                            try store.saveSearchCredential(name: sourceName, key: key)
                            key = ""; adding = false; status = "������Դ�ѱ��棬��Կ������ Keychain��"
                        } catch { status = error.localizedDescription }
                    }.frame(minHeight: 44)
                }.padding(.top, 12)
            }.disabled(store.isGenerating).accessibilityIdentifier("add-search-provider")
            if !status.isEmpty { Text(status).font(.caption).foregroundColor(.secondary) }
            Stepper("ÿ����� \(store.settings.options.searchCount) �����", value: Binding(get: { store.settings.options.searchCount }, set: { store.updateGlobalOption(\.searchCount, $0) }), in: 1...10).disabled(store.isGenerating)
            Toggle("������ȡ��Դ��ҳ", isOn: Binding(get: { store.current?.options.fetchTool ?? true }, set: { store.updateConversationOption(\.fetchTool, $0) })).disabled(store.isGenerating)
            if store.current?.options.searchTool == false {
                Button("�ָ�������ѯ����") { store.updateConversationOption(\.searchTool, true) }.disabled(store.isGenerating)
            }
        }
    }
    private var privacyCard: some View {
        Card {
            Text("��˽�����").font(.headline)
            Text("�����������ܽ���Ĳ�ѯ���͸����������̣�������������á���ҳ��ȡ���ᷢ����ѡ URL����Կ�����ṩ��ģ�ͻ���ҳ��").font(.footnote).foregroundColor(.secondary)
            Toggle("ͬ���ⲿ����", isOn: Binding(get: { store.searchConsent }, set: { store.updateGlobalOption(\.searchConsent, Optional($0)) }))
                .disabled(store.isGenerating).accessibilityIdentifier("search-consent-toggle")
            if !store.searchConsent { Text("��δ��Ȩ�����ᷢ�����������ڴ�ֱ��ͬ���ܾ���").font(.caption).foregroundColor(.secondary) }
            Text("�Զ�ģʽ��֧�ֹ��ߵ��õ�ģ�;����Ƿ��ѯ��ÿ��ģʽ���������ر�������ܾ���Ȩ�󲻷����µ��������ѽ��е���������ֹͣ��ťȡ����").font(.caption).foregroundColor(.secondary)
        }
    }
}
