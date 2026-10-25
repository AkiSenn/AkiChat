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
                    Text("����Ľ���").font(.system(size: 30, weight: .bold, design: .rounded)).padding(.top, 8)
                    Text("ģ�͡������ÿһ��˼����").foregroundColor(.secondary)
                    Card {
                        NavigationLink(destination: ProvidersView().environmentObject(store)) {
                            HStack { Label("ģ���� API Key", systemImage: "square.stack.3d.up"); Spacer(); Image(systemName: "chevron.right").font(.caption) }
                        }
                        Text("��������� �� Keychain ��Կ�洢").font(.caption).foregroundColor(.secondary)
                    }
                    Card {
                        NavigationLink("��ʾ��Ԥ���뵼�뵼��", destination: PromptLibraryView().environmentObject(store)).frame(minHeight: 44)
                        Text("�����������Ҳఴť�ɴ򿪵�ǰ�Ự����̨������Ԥ�㡢ժҪ�빤�ߡ�").font(.caption).foregroundColor(.secondary)
                    }
                    Card {
                        Label("���", systemImage: "circle.lefthalf.fill").font(.headline)
                        Picker("���ģʽ", selection: setting(\.appearance)) {
                            Text("����ϵͳ").tag(AppearanceMode.automatic)
                            Text("ǳɫ").tag(AppearanceMode.light)
                            Text("��ɫ").tag(AppearanceMode.dark)
                        }.pickerStyle(SegmentedPickerStyle())
                        Text("���� \(Int(store.settings.fontSize)) pt").font(.subheadline)
                        Slider(value: setting(\.fontSize), in: 13...22, step: 1)
                    }
                    Card {
                        Label("�Ի�ƫ��", systemImage: "text.bubble").font(.headline)
                        Text("Ӧ��Ĭ�� System Prompt").font(.caption).foregroundColor(.secondary)
                        TextEditor(text: setting(\.systemPrompt)).frame(height: 110).padding(6).overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.2)))
                        Text("�����������Ԥ�㰴�Ự���á���ͨ����ʡ��˼����ʷ��DeepSeek ����������ԭʼ�ִε�˼���ֶΡ�").font(.caption).foregroundColor(.secondary)
                        Toggle("��ʽ��Ӧ", isOn: setting(\.streaming))
                    }
                    Card {
                        Label("���ɲ���", systemImage: "slider.horizontal.3").font(.headline)
                        if !(store.provider?.kind == .deepSeek && store.thinking) {
                            Text(String(format: "Temperature %.2f", store.settings.temperature))
                            Slider(value: setting(\.temperature), in: 0...2, step: 0.05)
                        }
                        if !(store.provider?.kind == .deepSeek && !store.thinking && store.provider?.modelID == "deepseek-flash") {
                            Text(String(format: "Top P %.2f", store.settings.topP))
                            Slider(value: setting(\.topP), in: 0.05...1, step: 0.05)
                        }
                        Text("���Ԥ���ڻỰ����̨�����ã���ͬģ��ʹ�ø��Ե��������ޡ�").font(.caption).foregroundColor(.secondary)
                        Text("DeepSeek ˼��ģʽ������ Temperature��Flash ˼��ģʽ Top P ���Ϊ 0.95��").font(.caption).foregroundColor(.secondary)
                    }
                    Card {
                        Label("��������", systemImage: "externaldrive").font(.headline)
                        Text("\(store.conversations.count) ���Ự �� �޵�¼ �� ��ң��").font(.caption).foregroundColor(.secondary)
                        Button("����ȫ���Ự JSON") {
                            do { sharing = try ShareFile.make(data: ExportService.json(store.exportConversations()), ext: "json") }
                            catch { store.notice = error.localizedDescription }
                        }
                        Button("��յ�ǰ�Ự") { deletion = .conversation }.foregroundColor(.red)
                        Button("ɾ��ȫ�������¼") { deletion = .all }.foregroundColor(.red)
                    }
                    Card {
                        Text("AkiChat " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.2.0")).font(.headline)
                        Text("Created by AkiSenn\nBuilt with OpenAI Codex").font(.footnote)
                        Text("Ϊ iPhone �볤��ʹ�ö�д������ԭ��ʵ�֣�MIT License���޵���������ʱ������")
                            .font(.footnote).foregroundColor(.secondary)
                        NavigationLink("�����뿪Դ����֤", destination: LicenseView())
                        Link("��ĿԴ��", destination: URL(string: "https://github.com/AkiSenn/akichat")!)
                    }
                }.padding(18)
            }.background(Theme.background).navigationTitle("����").navigationBarTitleDisplayMode(.inline)
                .navigationBarItems(trailing: Button("���") { presentation.wrappedValue.dismiss() })
        }.navigationViewStyle(StackNavigationViewStyle())
            .alert(item: $deletion) { kind in
                Alert(title: Text(kind == .all ? "ɾ��ȫ�������¼��" : "��յ�ǰ�Ự��"), message: Text("�޷������������ȵ������ݡ�"), primaryButton: .destructive(Text("ɾ��")) {
                    if kind == .all { store.clearAll() } else { store.clearCurrent() }
                }, secondaryButton: .cancel(Text("ȡ��")))
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
                Text("����ԭ����д").font(.title2).bold()
                Text("Created by AkiSenn\nBuilt with OpenAI Codex").font(.headline)
                Text("���ο� Chatbox ��ͨ�ù������û����ֲ React��Electron�������ͼ�������ʵ�֡�Chatbox Community Edition Ϊ GPL-3.0����Ӧ�ö�������Ϊ MIT��")
                Text("û�е����� Swift ����ʹ�� Apple ϵͳ��ܡ��������߼�������֤����ֿ� THIRD_PARTY_NOTICES.md��")
                Text(Bundle.main.url(forResource: "LICENSE", withExtension: "txt").flatMap { try? String(contentsOf: $0) } ?? "MIT License �� Copyright (c) 2026 AkiSenn")
                    .font(.system(size: 12, design: .monospaced))
            }.padding(20)
        }.navigationTitle("����������֤")
    }
}
