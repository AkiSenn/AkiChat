# AkiChat

原生 SwiftUI AI 对话客户端，最低 **iOS 14.0**。主要面向 iPhone XR（414×896 pt、iOS 14.8）和 TrollStore 安装场景。Swift 5、URLSessionDataDelegate、Core Data SQLite、Keychain，无服务器、无登录、无遥测、无第三方 Swift 包。

## 快速获得 IPA

1. 打开 [GitHub Actions](https://github.com/AkiSenn/akichat/actions/workflows/build-ios.yml)，选择 **Build iOS 14 IPA → Run workflow → Run workflow**。
2. 等待整个任务变绿。真机 Release 编译、校验、模拟器单元测试全部通过后，才上传 `AkiChat-iOS14` 产物。
3. 下载并解压 Artifact ZIP，得到 `AkiChat-iOS14-unsigned.ipa`、备用 `AkiChat-iOS14-adhoc.ipa`、SHA256 和模拟器启动截图。
4. 将 IPA 传到 iPhone 的“文件”App，分享给已安装的 TrollStore，点击安装。打开 AkiChat，配置自己的密钥。

不要把外层 Artifact ZIP 当作 IPA。IPA 必须包含 `Payload/AkiChat.app`。不需要 Apple Developer 付费证书或 Provisioning Profile。

## 当前功能

- 多会话：新建、搜索标题/消息、最近排序、重命名、确认删除、清空、JSON 导入导出、Markdown 导出。
- 聊天：自动增高输入框、复制、编辑重发、重新生成、停止生成、自动跟随和返回最新消息；草稿与图片随会话保存。
- 模型：默认 DeepSeek、多配置/模型、每会话独立选择、手动模型 ID、HTTPS Base URL 规范化、非敏感自定义 Header、连接/密钥测试。
- 流式/非流式：SSE 字节解析、拆分 UTF-8、跨数据块事件、多事件、`[DONE]`、独立思考/回答、Token usage、HTTP/超时/中断处理。
- 深度思考：独立开关，low/high/max（默认 high），可折叠思考内容、状态及回答分区。
- 图片：iOS 14 PHPicker 相册选择、预览/移除、ImageIO 解码时缩图、JPEG 压缩、Base64 data URL，发送失败可重新生成。
- 原生 Markdown：标题、列表、引用、粗体、斜体、行内代码、代码块和复制、可点链接、基础表格。流式生成期间用原生纯文本降低渲染成本，结束后解析 Markdown。
- 主题：自动/浅色/深色、字体大小、系统提示词、上下文消息数量、Temperature/Top P/输出长度、流式开关。
- 数据：Keychain 密钥、Core Data SQLite 历史、系统文件保护；API 失败保留用户内容，进后台停止请求并保存。

基础 Markdown 采用独立轻量解析器，不宣称完整 CommonMark；数学公式、复杂嵌套表格、语法高亮、工具调用和后台持续生成不在本版范围。动画图片会转换为静态 JPEG。仅支持竖屏 iPhone。

## API 配置

聊天页右下角“设置” → “模型与 API Key” → DeepSeek 或“添加 OpenAI 兼容服务商 / 模型”。填写名称、显示名称、Base URL、模型 ID、密钥与能力开关。

默认 DeepSeek：

| 字段 | 值 |
|---|---|
| Provider | DeepSeek |
| Base URL | `https://api.deepseek.com` |
| 最终 Endpoint | `https://api.deepseek.com/chat/completions` |
| API model | `deepseek-flash` |
| 显示名称 | DeepSeek V4.1 Flash 1017 |
| 适配方式 | DeepSeek 官方格式 |
| 能力 | 图片、思考、流式 |

**版本显示名不是 API 模型 ID。** 请勿把 `DeepSeek-V4.1-Flash-1017` 填入请求的 model。

点“测试连接和密钥”，看到成功后点“保存”。测试发送一条简短非流式消息，可能产生少量 API 费用。留空密钥保留已有值；“删除已保存密钥”明确移除 Keychain 记录。没有预置开发者密钥。

自定义接口可填 `https://example.com/v1` 或 `https://example.com/v1/chat/completions/`，最终路径只拼接一次。只允许 HTTPS，保持系统 TLS 验证，拒绝重定向以避免认证信息转发。普通 OpenAI 兼容适配不会发送 DeepSeek 的 `thinking` 与 `reasoning_effort`。不依赖 `/models` 列表接口。

一个 Provider 配置代表一个模型；同一服务商可添加多个配置，每个配置拥有独立 Keychain 引用。自定义 Header 仅用于非敏感元数据（例如 `X-Client-Version`），不能放入密钥。认证统一使用 Keychain 中的 Bearer Key。

### 思考、上下文与图片

DeepSeek 开启思考时发送 `"thinking":{"type":"enabled"}`，关闭时发送 `"thinking":{"type":"disabled"}`；开启时携带 `reasoning_effort`。Temperature 在思考模式不发送，Flash 思考模式 Top P 下限为 0.95。

本版没有工具调用，历史 `reasoning_content` 仅用于本地显示与导出，**不会回传到普通多轮请求**；回答通过 content 回传。未来增加 tools 时必须另建上下文策略，遵循官方工具场景的推理回传规则。

图片内容为 `[{"type":"text","text":"…"},{"type":"image_url","image_url":{"url":"data:image/jpeg;base64,…"}}]`，仅放在 user 消息。客户端每条消息最多 4 张、每张最多 4 MiB、最长边 2048 px；官方当前接受 JPEG/PNG/GIF/WebP，单图内联上限 32 MiB、请求体上限 48 MiB、每侧最多 8192 px（15 张及以上最多 4096 px）。客户端还校验上下文的总图片数量、总大小和编码后整个请求体。上下文过大时减小消息数量或开始新会话。

核对依据（2026-10-22）：[Chat Completions](https://api-docs.deepseek.com/api/create-chat-completion/)、[Thinking Mode](https://api-docs.deepseek.com/guides/thinking_mode/)、[Vision](https://api-docs.deepseek.com/guides/vision/)。API 未来变化时可在设置中修改模型 ID 或新增配置。

## iOS 14 与本地开发

打开 `ios/AkiChat.xcodeproj`，选择共享 Scheme **AkiChat**。所有 Debug/Release 和测试目标的 Deployment Target 固定为 **14.0**，Bundle ID 固定为 **app.akichat.ios**。建议 Xcode 16.2（CI 固定版本），Swift 编译模式为 5。

使用 iOS 14 可用的 `NavigationView`、`ScrollViewReader`、`LazyVStack`、PHPicker、UITextView、UIActivityViewController；不使用 NavigationStack、PhotosPicker、SwiftData、原生 SwiftUI Markdown、URLSession.bytes。SwiftUI 处理键盘安全区域，主界面仅背景延伸到屏幕边缘。

```sh
python3 ios/scripts/check_compatibility.py
xcodebuild -project ios/AkiChat.xcodeproj -scheme AkiChat \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build/device ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
  IPHONEOS_DEPLOYMENT_TARGET=14.0 CODE_SIGNING_ALLOWED=NO build
python3 ios/scripts/package_ipa.py \
  build/device/Build/Products/Release-iphoneos/AkiChat.app \
  build/AkiChat-iOS14-unsigned.ipa
```

Windows 可以编辑完整源码和运行 Python 工程自检，但不能执行 Xcode 编译。添加 Swift 文件后运行 `python3 ios/scripts/generate_project.py` 并提交更新后的工程。已提交的工程不依赖 XcodeGen。图标已提交，只有重新生成图标才需要 Pillow：`python3 ios/scripts/generate_icons.py`。

## 项目结构

```text
ios/AkiChat.xcodeproj/       完整工程及共享 Scheme
ios/AkiChat/
  AkiChatApp.swift            SwiftUI 应用入口
  Models/                    Codable 模型、导入导出、错误
  UI/                        聊天、会话、设置、Provider、原生 Markdown
  API/                       Provider 适配、请求、SSE、URLSessionDataDelegate
  Storage/                   Core Data SQLite、Keychain
  Services/                  主线程状态、图片处理、异步持久化
  Assets.xcassets/            原创应用图标
ios/AkiChatTests/            无真实密钥的 XCTest / Mock URLProtocol
ios/scripts/                工程生成、兼容性回归检查、真实产物校验/打包
.github/workflows/          真机编译、测试、Artifacts、tag Release
```

Core Data 保存版本化 Codable 记录。密钥不进入数据库、UserDefaults、JSON、Markdown 或日志。数据库无法解码时暂停写入，不用空记录覆盖原文件。导出含聊天文本、思考和图片，使用系统分享界面交给用户选择目的地；导入将聊天作为新副本加入，不覆盖已有聊天、不导入认证配置。

## Actions 与 Release

工作流支持任意 push（包括 tag）、workflow_dispatch 和已发布 GitHub Release。使用 GitHub `macos-15` Runner 和预装 `/Applications/Xcode_16.2.app`，该组合来自 [Runner 官方镜像清单](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md)。固定版本不存在时直接失败，避免静默更换工具链。

流程：源码/工程自检 → 真机 arm64 Release 无签名编译 → 校验真实 `.app` → 两种 IPA → iOS 18.2 模拟器 Mock 测试和启动截图 → 上传产物。自动测试使用较新模拟器，编译目标仍是 14.0；这不能代替 iOS 14.8 真机验收。

打包器检查实际可执行文件大小、执行权限、Mach-O arm64、最低系统 14.0、iPhoneOS 平台、Info.plist、Assets.car、无 provisioning、原始包确实未签名、ZIP CRC 和 `Payload/AkiChat.app` 结构。任何检查失败即停止。仅成功构建和测试后才发布用户下载产物，失败日志在诊断 Artifact 中。

发布示例：`git tag v1.0.0 && git push origin v1.0.0`，工作流将创建 GitHub Release 并附加 IPA 与校验和；已存在 Release 时更新附件。普通分支 push 不创建 Release。

## TrollStore 的三种签名步骤

1. **无签名编译**：`CODE_SIGNING_ALLOWED=NO`，没有使用 Apple 开发者签名，产出 `AkiChat-iOS14-unsigned.ipa`。
2. **本地 ad-hoc**：备用 `AkiChat-iOS14-adhoc.ipa` 使用 macOS `codesign --sign -`，不需要账号或证书，不是 TrollStore 的永久签名。没有添加私有 entitlement。
3. **TrollStore 安装**：TrollStore 安装时按其机制重新签名/注册。官方说明见 [TrollStore README](https://github.com/opa334/TrollStore)。iOS 14.8 在其支持区间内；本项目不需要越狱注入、root helper 或私有权限。

先尝试 unsigned 包；若当前 TrollStore/ldid 版本拒绝完全无签名的 Mach-O，使用工作流同时提供的 adhoc 包。仍有问题时，先在 TrollStore 设置检查其官方 ldid 是否已安装/更新。

若需要在 Mac 上按官方 ldid 流程补签，可解压 unsigned IPA，对 `Payload/AkiChat.app/AkiChat` 执行 `ldid -S Payload/AkiChat.app/AkiChat`，再 `zip -r AkiChat-iOS14-fakesigned.ipa Payload`。这只是本地 fake signing，最终仍由 TrollStore 安装处理；不要添加任意私有 entitlement，不要改最低系统版本，也无需开发者证书。工具本身请从可信官方来源安装。

在设备上首次启动后检查：保存密钥→重启应用仍可使用→普通连续多轮→思考开关及三种强度→图片→停止/断网/重试→重启后的历史。请记录设备、系统、TrollStore 版本。CI 成功不代表这份真机清单已经执行。

## 测试与验收状态

XCTest 覆盖请求 JSON、默认模型/地址、思考开关和强度、OpenAI 参数隔离、上下文、图片内容块、SSE 每个字节切分、CR/LF、多行事件、异常 JSON、usage、HTTP 错误、超时、取消、提前断流、SQLite 落盘重开、Provider 配置、损坏数据保护、导入导出、Markdown 和最低系统元数据。网络测试仅用 Mock URLProtocol，不连接实际 API。

`check_compatibility.py` 是已知新 API 的静态回归检查；Xcode 针对 iOS 14.0 的编译负责 SDK 可用性诊断。两者都不能完整替代 iOS 14.8 真机测试。真实 API 也需要用户自己的密钥，仓库不将其用于 CI。

初始交付环境为 Windows。具体 CI 执行结果以 [Actions 记录](https://github.com/AkiSenn/akichat/actions) 为准，不将未执行的 Xcode/真机测试称为通过。

## 常见问题

| 问题 | 排查 |
|---|---|
| 401 / 403 | 检查密钥是否来自当前服务商、权限是否有效；删除旧密钥后重新保存 |
| 402 | DeepSeek 账户余额不足 |
| 400 / 404 / 422 | 检查最终 URL、模型 ID、适配方式和图片能力；DeepSeek 用 `deepseek-flash` |
| 429 | 额度/并发限制，稍后重试 |
| 没有 usage | 部分兼容接口不返回 usage；仅在收到时显示 |
| 自定义服务不支持 stream_options | 关闭该模型的“请求流式 Token usage 扩展”；普通兼容配置默认不发送该字段 |
| 超时 / 中断 | 消息和部分回答会保留，点重新生成；进后台会主动停止 |
| 图片失败 | 相册/云端原图失败时重新选择；发送失败点重新生成；上下文过大时减少历史消息 |
| Keychain 错误 | 确认通过 TrollStore 正常安装/注册，使用固定 Bundle ID，检查 TrollStore/ldid；不要退回明文保存密钥 |
| 本地保存失败 | 及时导出备份，检查设备存储；不要在未备份前卸载 |
| Actions 编译失败 | 查看 `AkiChat-build-diagnostics` 与具体失败步骤；不要提高 Deployment Target 规避 |
| Actions 没有运行 | 在仓库 Actions 设置允许运行工作流；手动 Run workflow；检查账户分钟数/额度 |
| 安装后无法启动 | 检查 IPA 来源与结构、尝试 adhoc 包、检查 TrollStore/持久化助手；提交设备日志定位 |

## 开源

独立原生实现采用 [MIT](LICENSE)。仅参考 Chatbox 通用功能理念，无复制其 GPL 代码或资源。[第三方说明](THIRD_PARTY_NOTICES.md) 列出构建工具及许可证。
