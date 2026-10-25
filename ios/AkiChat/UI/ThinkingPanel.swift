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
                        if store.isGenerating { Text("本轮正在生成，设置只读；请停止后修改。").font(.caption).foregroundColor(.secondary) }
                    }
                    if let id = store.current?.providerID {
                        Card {
                            Button(store.refreshingModels.contains(id) ? "取消刷新" : "刷新模型能力") {
                                if store.refreshingModels.contains(id) { store.cancelModelRefresh(id) }
                                else { store.refreshModels(id) }
                            }.frame(minHeight: 44).disabled(store.isGenerating)
                            if store.refreshingModels.contains(id) { ProgressView() }
                            if let error = store.modelErrors[id] { Text(error).font(.caption).foregroundColor(.secondary) }
                            NavigationLink("模型能力与高级兼容设置", destination: ModelsView(providerID: id).environmentObject(store))
                        }
                    }
                    Text("更改会保存到当前会话。关闭面板不会开启任何功能，正在执行的请求不会被修改。").font(.caption).foregroundColor(.secondary)
                }.padding(18)
            }.background(Theme.background.edgesIgnoringSafeArea(.all))
                .navigationTitle("深度思考").navigationBarTitleDisplayMode(.inline)
                .navigationBarItems(leading: Button("关闭") { presentation.wrappedValue.dismiss() }.accessibilityIdentifier("thinking-panel-close"), trailing: Button("完成") { presentation.wrappedValue.dismiss() })
        }.navigationViewStyle(StackNavigationViewStyle()).accessibilityIdentifier("thinking-panel")
            .onAppear {
                if !store.isGenerating, let p = store.provider, p.options.reasoning?.levels.isEmpty != false {
                    store.refreshModels(p.id, onlyIfNeeded: true)
                }
            }
    }
}
