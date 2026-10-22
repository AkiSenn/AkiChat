import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.presentationMode) var presentation
    @State private var deletion: Deletion?
    private enum Deletion: String, Identifiable { case conversation, all; var id: String { rawValue } }
    @State private var sharing: ShareFile?
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    NoticeBanner()
                    Text("按你的节奏").font(.system(size: 30, weight: .bold, design: .rounded)).padding(.top, 8)
                    Text("模型、外观与每一次思考。").foregroundColor(.secondary)
                    Card {
                        NavigationLink(destination: ProvidersView().environmentObject(store)) {
                            HStack { Label("模型与 API Key", systemImage: "square.stack.3d.up"); Spacer(); Image(systemName: "chevron.right").font(.caption) }
                        }
                        Text("多个服务商 · Keychain 密钥存储").font(.caption).foregroundColor(.secondary)
                    }
                    Card {
                        NavigationLink("提示词预设与导入导出", destination: PromptLibraryView().environmentObject(store)).frame(minHeight: 44)
                        Text("聊天输入栏右侧按钮可打开当前会话控制台，配置预算、摘要与工具。").font(.caption).foregroundColor(.secondary)
                    }
                    Card {
                        Label("外观", systemImage: "circle.lefthalf.fill").font(.headline)
                        Picker("外观模式", selection: setting(\.appearance)) {
                            Text("跟随系统").tag(AppearanceMode.automatic)
                            Text("浅色").tag(AppearanceMode.light)
                            Text("深色").tag(AppearanceMode.dark)
                        }.pickerStyle(SegmentedPickerStyle())
                        Text("字体 \(Int(store.settings.fontSize)) pt").font(.subheadline)
                        Slider(value: setting(\.fontSize), in: 13...22, step: 1)
                    }
                    Card {
                        Label("对话偏好", systemImage: "text.bubble").font(.headline)
                        Text("应用默认 System Prompt").font(.caption).foregroundColor(.secondary)
                        TextEditor(text: setting(\.systemPrompt)).frame(height: 110).padding(6).overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.2)))
                        Text("上下文与输出预算按会话配置。普通请求省略思考历史；DeepSeek 工具请求保留原始轮次的思考字段。").font(.caption).foregroundColor(.secondary)
                        Toggle("流式响应", isOn: setting(\.streaming))
                        Picker("推理强度", selection: Binding(get: { store.effort }, set: { store.setEffort($0) })) {
                            ForEach(ReasoningEffort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }.pickerStyle(SegmentedPickerStyle())
                        Text("推理强度仅用于 DeepSeek 深度思考。").font(.caption).foregroundColor(.secondary)
                    }
                    Card {
                        Label("生成参数", systemImage: "slider.horizontal.3").font(.headline)
                        if !(store.provider?.kind == .deepSeek && store.thinking) {
                            Text(String(format: "Temperature %.2f", store.settings.temperature))
                            Slider(value: setting(\.temperature), in: 0...2, step: 0.05)
                        }
                        if !(store.provider?.kind == .deepSeek && !store.thinking && store.provider?.modelID == "deepseek-flash") {
                            Text(String(format: "Top P %.2f", store.settings.topP))
                            Slider(value: setting(\.topP), in: 0.05...1, step: 0.05)
                        }
                        Text("输出预算在会话控制台中设置；不同模型使用各自的能力上限。").font(.caption).foregroundColor(.secondary)
                        Text("DeepSeek 思考模式不发送 Temperature；Flash 思考模式 Top P 最低为 0.95。").font(.caption).foregroundColor(.secondary)
                    }
                    Card {
                        Label("本地数据", systemImage: "externaldrive").font(.headline)
                        Text("\(store.conversations.count) 个会话 · 无登录 · 无遥测").font(.caption).foregroundColor(.secondary)
                        Button("导出全部会话 JSON") {
                            do { sharing = try ShareFile.make(data: ExportService.json(store.conversations), ext: "json") }
                            catch { store.notice = error.localizedDescription }
                        }
                        Button("清空当前会话") { deletion = .conversation }.foregroundColor(.red)
                        Button("删除全部聊天记录") { deletion = .all }.foregroundColor(.red)
                    }
                    Card {
                        Text("AkiChat 2.0").font(.headline)
                        Text("Created by AkiSenn\nBuilt with OpenAI Codex").font(.footnote)
                        Text("为 iPhone 与长久使用而写。独立原生实现，MIT License。无第三方运行时依赖。")
                            .font(.footnote).foregroundColor(.secondary)
                        NavigationLink("关于与开源许可证", destination: LicenseView())
                        Link("项目源码", destination: URL(string: "https://github.com/AkiSenn/akichat")!)
                    }
                }.padding(18)
            }.background(Theme.background).navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
                .navigationBarItems(trailing: Button("完成") { presentation.wrappedValue.dismiss() })
        }.navigationViewStyle(StackNavigationViewStyle())
            .alert(item: $deletion) { kind in
                Alert(title: Text(kind == .all ? "删除全部聊天记录？" : "清空当前会话？"), message: Text("无法撤销，建议先导出备份。"), primaryButton: .destructive(Text("删除")) {
                    if kind == .all { store.clearAll() } else { store.clearCurrent() }
                }, secondaryButton: .cancel(Text("取消")))
            }
            .sheet(item: $sharing) { ShareSheet(url: $0.url) }
    }
    private func setting<T>(_ path: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(get: { store.settings[keyPath: path] }, set: { store.updateSetting(path, $0) })
    }
}

struct LicenseView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("独立原生重写").font(.title2).bold()
                Text("Created by AkiSenn\nBuilt with OpenAI Codex").font(.headline)
                Text("仅参考 Chatbox 的通用功能理念，没有移植 React、Electron、组件、图标或其他实现。Chatbox Community Edition 为 GPL-3.0，本应用独立代码为 MIT。")
                Text("没有第三方 Swift 包。使用 Apple 系统框架。构建工具及其许可证详见仓库 THIRD_PARTY_NOTICES.md。")
                Text(Bundle.main.url(forResource: "LICENSE", withExtension: "txt").flatMap { try? String(contentsOf: $0) } ?? "MIT License — Copyright (c) 2026 AkiSenn")
                    .font(.system(size: 12, design: .monospaced))
            }.padding(20)
        }.navigationTitle("关于与许可证")
    }
}
