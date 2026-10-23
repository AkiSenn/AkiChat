import SwiftUI

struct ModelSelectionPanel: View {
    @EnvironmentObject var store: AppStore
    let dismiss: () -> Void
    @State private var query = ""
    @State private var favoritesOnly = false
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    TextField("搜索模型或服务商", text: $query).padding(14).background(Theme.card).cornerRadius(14)
                    Toggle("只看收藏", isOn: $favoritesOnly).font(.subheadline)
                    NavigationLink("服务商与 API Key 管理", destination: ProvidersView().environmentObject(store)).frame(minHeight: 44)
                    if store.isGenerating { Text("请先停止生成，再切换模型。").font(.caption).foregroundColor(.orange) }
                    ForEach(store.providers) { provider in
                        ProviderModelSection(provider: provider, query: query, favoritesOnly: favoritesOnly, dismiss: dismiss)
                    }
                }.padding(18)
            }.background(Theme.background.edgesIgnoringSafeArea(.all))
                .navigationTitle("选择模型").navigationBarTitleDisplayMode(.inline)
                .navigationBarItems(trailing: Button("完成", action: dismiss))
        }.navigationViewStyle(StackNavigationViewStyle())
    }
}

private struct ProviderModelSection: View {
    @EnvironmentObject var store: AppStore
    let provider: Provider
    let query: String
    let favoritesOnly: Bool
    let dismiss: () -> Void
    private var models: [ModelRecord] {
        ModelDiscovery.filtered(store.models(for: provider.id), query: provider.name.localizedCaseInsensitiveContains(query) ? "" : query, favoritesOnly: favoritesOnly)
    }
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(provider.name).font(.headline).lineLimit(2)
                Spacer()
                Button(store.refreshingModels.contains(provider.id) ? "取消" : "刷新") {
                    if store.refreshingModels.contains(provider.id) { store.cancelModelRefresh(provider.id) }
                    else { store.refreshModels(provider.id) }
                }.font(.caption).frame(minHeight: 44)
                NavigationLink("管理", destination: ModelsView(providerID: provider.id).environmentObject(store)).font(.caption).frame(minHeight: 44)
            }
            if models.isEmpty {
                Text("暂无匹配模型；可在管理中刷新或手动添加。").font(.caption).foregroundColor(.secondary)
            }
            ForEach(models) { model in
                HStack(spacing: 8) {
                    Button {
                        store.selectModel(providerID: provider.id, modelID: model.id)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(model.name == ProviderNaming.legacyFlashName ? model.id : model.name).font(.subheadline).fontWeight(.semibold).lineLimit(2)
                                Text(model.id).font(.caption).foregroundColor(.secondary).lineLimit(2)
                                Text(model.manual ? "手动添加" : "模型目录").font(.caption2).foregroundColor(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            if store.current?.providerID == provider.id && (store.current?.options.modelID ?? provider.modelID) == model.id {
                                Image(systemName: "checkmark.circle.fill").foregroundColor(Theme.accent).accessibilityLabel("当前模型")
                            }
                        }.foregroundColor(.primary).padding(.vertical, 12).padding(.leading, 14)
                    }.disabled(store.isGenerating)
                    Button {
                        var updated = model; updated.favorite.toggle(); store.saveModel(updated, providerID: provider.id)
                    } label: {
                        Image(systemName: model.favorite ? "star.fill" : "star").frame(width: 44, height: 44)
                    }.accessibilityLabel(model.favorite ? "取消收藏" : "收藏模型")
                }.background(Theme.card).cornerRadius(15)
            }
            if let error = store.modelErrors[provider.id] { Text(error).font(.caption).foregroundColor(.secondary) }
            if store.refreshingModels.contains(provider.id) { ProgressView("正在同步模型") }
        }
    }
}
