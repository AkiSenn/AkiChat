import SwiftUI

struct ThinkingPanel: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.presentationMode) private var presentation
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 18) {
                    Card {
                        Text(store.selectedModelLabel).font(.headline)
                        ReasoningControls()
                        if store.isGenerating { Text("�����������ɣ�����ֻ������ֹͣ���޸ġ�").font(.caption).foregroundColor(.secondary) }
                    }
                    if let id = store.current?.providerID {
                        Card {
                            Button(store.refreshingModels.contains(id) ? "ȡ��ˢ��" : "ˢ��ģ������") {
                                if store.refreshingModels.contains(id) { store.cancelModelRefresh(id) }
                                else { store.refreshModels(id) }
                            }.frame(minHeight: 44).disabled(store.isGenerating)
                            if store.refreshingModels.contains(id) { ProgressView() }
                            if let error = store.modelErrors[id] { Text(error).font(.caption).foregroundColor(.secondary) }
                            NavigationLink("ģ��������߼���������", destination: ModelsView(providerID: id).environmentObject(store))
                        }
                    }
                    Text("���Ļᱣ�浽��ǰ�Ự���ر���岻�Ὺ���κι��ܣ�����ִ�е����󲻻ᱻ�޸ġ�").font(.caption).foregroundColor(.secondary)
                }.padding(18)
            }.background(Theme.background.edgesIgnoringSafeArea(.all))
                .navigationTitle("���˼��").navigationBarTitleDisplayMode(.inline)
                .navigationBarItems(leading: Button("�ر�") { presentation.wrappedValue.dismiss() }, trailing: Button("���") { presentation.wrappedValue.dismiss() })
        }.navigationViewStyle(StackNavigationViewStyle()).accessibilityIdentifier("thinking-panel")
            .onAppear {
                if !store.isGenerating, let p = store.provider, p.options.reasoning?.levels.isEmpty != false {
                    store.refreshModels(p.id, onlyIfNeeded: true)
                }
            }
    }
}
