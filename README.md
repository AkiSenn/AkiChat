# AkiChat

原生 iOS 14+ 多模型 AI 客户端，主要面向 **iPhone XR / iOS 14.8 / A12**。Swift 5、SwiftUI/UIKit、URLSessionDataDelegate、Core Data SQLite、Keychain；无中转后端、无登录、无遥测、无第三方 Swift 运行时依赖。

**Created by AkiSenn**<br>
**Built with OpenAI Codex**

Copyright (c) 2026 AkiSenn · [MIT](LICENSE) · [AUTHORS](AUTHORS.md) · [第三方说明](THIRD_PARTY_NOTICES.md)

## 下载与 TrollStore 安装

稳定版本见 [GitHub Releases](https://github.com/AkiSenn/AkiChat/releases)。自行构建：打开 [Build iOS 14 IPA](https://github.com/AkiSenn/AkiChat/actions/workflows/build-ios.yml) → **Run workflow** → 等待绿色结果 → 下载 **AkiChat-iOS14** Artifact ZIP 并解压。

- `AkiChat-iOS14-unsigned.ipa`：实际 Release arm64 真机无签名构建。
- `AkiChat-iOS14-adhoc.ipa`：同一构建的本地 ad-hoc 备用包，不需要开发者证书。
- `SHA256SUMS.txt`：校验和；产物目录可执行 `shasum -a 256 -c SHA256SUMS.txt`。
- `launch.png`：实际模拟器启动截图。

将 IPA 传到 iPhone“文件”App，分享给已安装的 TrollStore 并安装。外层 Artifact ZIP 不是 IPA。

三种步骤必须区分：**无签名编译**使用 CODE_SIGNING_ALLOWED=NO；**本地 ad-hoc**备用包使用 `codesign --sign -`，不是付费证书或永久签名；**TrollStore 安装处理**会按安装器机制重签/注册。不能承诺纯 unsigned IPA 不经安装处理就能运行。

先尝试 unsigned；若当前 TrollStore/ldid 拒绝未签名 Mach-O，使用随附 adhoc IPA，并检查 TrollStore 官方 ldid 是否已安装/更新。必要时可在 Mac 解压 unsigned IPA，执行 `ldid -S Payload/AkiChat.app/AkiChat`，再 `zip -r AkiChat-iOS14-fakesigned.ipa Payload`。ldid 应从官方可信来源获得，不添加任意私有 entitlement。

官方依据：[TrollStore](https://github.com/opa334/TrollStore)。本项目不需要越狱注入、root helper、Apple 付费证书或 Provisioning Profile。

### 版本与早期安装包的数据迁移

当前版本为 **1.2.0（build 8）**，属于现有 AkiChat v1 的持续迭代。此前的 V2/2.x 名称是版本规划误解，不代表重建新一代应用，后续沿用 1.x.x 编号。

当前 Bundle ID 保持 **com.akisenn.akichat**。仅当早期安装包使用 `app.akichat.ios` 时，两个标识才对应独立容器：先从早期包导出聊天 JSON，再在当前应用会话抽屉中导入，并重新填写 API Key。按实际 Bundle ID 判断迁移需求，而不是按 v1/v2 名称；没有跨容器自动迁移。相同 Bundle ID 的历史、配置、密钥引用及内部数据格式编号保持不变。完成备份前不要删除早期安装包。

## 聊天性能与模型切换维护

显示版本为 1.2.0，构建号8。顶部主标题显示服务商名称，副标题显示当前真实模型 ID；点击直接按服务商分组选择模型。先展示本地缓存，刷新由用户主动触发，新配置保存后仍可自动发现。DeepSeek 默认 ID 仍为 deepseek-flash，其他模型以 /models 返回和手动配置为准。

流式更新集中到当前消息；草稿独立更新并防抖保存；历史 Markdown 缓存、后台解析、原生文本测量缓存和后台图片缩略图减少高频工作。详见 [性能审查与验证边界](docs/PERFORMANCE_REVIEW.md)。没有声称已测得 iOS 16 真机 FPS 或优化百分比。

## WorkBuddy2API Hub 兼容修复

可添加独立 WorkBuddy Provider，保存网关地址和管理面板生成的 Key 后自动获取模型。顶部模型面板按服务商分组，支持搜索、收藏与跨服务商切换；Hub 推理档位按目录适配，保留网关原始模型 ID。可信局域网 HTTP 需主动启用明文风险开关。

详细设置、推理/工具/搜索边界、429 退避与审查依据见 [接入教程](docs/WORKBUDDY_HUB.md) 和 [PR #1 审查记录](docs/WORKBUDDY_REVIEW.md)。Hub Responses 联网未接入；当前客户端联网使用单独的官方 DeepSeek Key，普通 Hub 聊天不要求它。

## 开始使用

1. 空白聊天页“配置你的 API”，或左侧会话抽屉底部“应用设置” → “模型与 API Key”。
2. 打开 DeepSeek，填写自己的密钥、测试并保存。保存新密钥后自动尝试 GET /models。
3. 顶部模型选择器 → 模型库，刷新、搜索并选择 `deepseek-flash`；接口不可用时可手动添加模型 ID。
4. 输入消息并开启深度思考。思考与回答分离，支持折叠、复制、编辑重发、重新生成和停止。
5. 图片按钮可选择最多 4 张图片；输入栏右侧按钮打开“会话控制台”，配置图片、上下文、提示词、工具与搜索。
6. 搜索或摘要前，先阅读并启用“同意外部搜索与额外摘要请求”。工具、联网与自动压缩默认关闭。
7. 联网按钮切换关闭/自动/每条强制；来源列表和 Markdown 链接可打开原文。
8. 长会话可自动或手动压缩，查看与恢复摘要版本。预算裁剪和压缩均不删除原始历史。

## 功能

| 模块 | 行为 |
|---|---|
| 原生 UI | 左侧会话抽屉、模型选择器、自动增高输入、键盘/安全区域、毛玻璃、卡片、浅色/深色/系统、动态字体与无障碍标签 |
| Provider | DeepSeek、OpenAI 预设、自定义兼容接口，Chat/Models 路径、Header、超时、能力和预算上限 |
| 模型库 | 自动/手动刷新、缓存与同步时间、搜索、收藏、排序、手动添加/删除、元数据与能力/容量覆盖 |
| 网络 | 流式/非流式、UTF-8/SSE 分片、reasoning_content、tool_calls 增量、finish_reason、usage、超时/取消/错误/重试 |
| 图片 | PHPicker 多图、预览/移除、512/1024/2048 最长边、JPEG 质量、解码时缩图、data URL、格式/大小限制 |
| 工具 | 多轮 Function Calling，搜索、网页读取、日期时间、安全计算，白名单、参数校验、错误恢复、循环限制和折叠日志 |
| 搜索 | 官方 DeepSeek Search/Fetch，自动/强制模式、默认 5 条（1–10 可调）、真实来源、状态/失败/费用提示 |
| 上下文 | 每会话总预算/输出预留、自动/全量/滑动窗口/摘要+近期、完整轮次与工具链、Token 估算及实际 usage 校准 |
| 压缩 | 75% 默认阈值（50%–90%），保留最近 8 轮完整对话，结构化摘要、覆盖范围、独立摘要模型、版本/回滚/额外 usage |
| 提示词 | 应用→Provider→模型→会话，预设创建/编辑/复制/删除/启停/导入导出、按模型选择、有效提示词预览 |
| Prefix Beta | 独立开关，DeepSeek /beta 与最后 assistant 的 prefix:true，本版与工具互斥 |
| 数据 | SQLite 历史、搜索/重命名/确认删除、JSON 导入导出、Markdown 导出、工具/来源/usage/摘要版本持久化，Keychain 单独保存密钥 |
| Markdown | 流式逐步渲染，标题、列表、引用、粗斜体、行内代码、代码块/语言/复制、链接、基础表格 |

轻量原生 Markdown 不宣称完整 CommonMark。JSON 是保真备份格式，Markdown 是便于阅读的导出。

## API 与模型配置

| DeepSeek 默认字段 | 值 |
|---|---|
| Base URL | `https://api.deepseek.com` |
| Chat / Models | `/chat/completions` / `/models` |
| API model ID | `deepseek-flash` |
| Provider 显示名称 | DeepSeek |
| 推理强度 | high，可选 low / high / max |

版本名称不是 API model ID。发现接口返回名称后优先展示服务端名称。支持根地址、/v1、完整 /v1/chat/completions 和手动端点路径，避免重复拼接。只接受无账号、查询参数和 fragment 的 HTTPS Base URL，保持系统 TLS 验证，拒绝重定向。

模型发现读取 id、name、context_window、max_output_tokens、input/output_modalities、effort、api_capabilities。图片、思考、工具元数据缺失时保持未知/禁用，可核实后手动覆盖；官方 Flash 预设使用公开文档中的能力。刷新失败、空列表或远端缺失条目都不会删除本地配置。能力/容量覆盖、提示词、收藏和排序保留。

并非所有兼容接口都实现 /models，404 时手动添加即可。Header 只用于非敏感元数据，不能存认证、Cookie 或 Key/Token/Secret。官方 OpenAI 预设自动选择 max_completion_tokens 并默认不发送可能被推理模型拒绝的采样参数；通用兼容接口默认 max_tokens，两项均可覆盖。非 DeepSeek 不发送其私有 thinking 参数。

## 思考、工具与联网

DeepSeek 开关使用 `{"thinking":{"type":"enabled"}}` 或 disabled，开启时传 reasoning_effort。思考模式不发送 Temperature，界面隐藏该无效参数。Flash 思考 Top P 最低 0.95，非思考 Flash 不发送无效 Top P。

普通多轮不回传历史 reasoning_content；携带 tools 时完整保留原始 assistant 的 reasoning_content、tool_calls 和匹配的 tool_call_id，包括没有调用工具的 assistant 回答。上下文按完整轮次和完整工具链处理，不能留下孤立 tool 消息。摘要覆盖旧轮次后发送摘要数据与近期原始轮次，近期推理字段仍完整保留。

工具默认最多 4 轮、可设至 8 轮，每轮最多 4 个调用。纯数字计算使用独立解析器，不用任意代码执行或 NSExpression。未授权工具或非法参数返回错误；没有终端、任意代码、文件删除和私有数据访问。当前工具没有敏感写操作；未来敏感工具必须增加明确确认。

搜索固定调用官方 `POST /v1/tools/search` 和 `POST /v1/tools/fetch`，复用用户选定的官方 DeepSeek 密钥。自动模式由真实 Function Calling 决定，强制模式先执行真实搜索再交给模型。失败会记录错误，不用提示词虚构联网。网页/搜索内容是有界不可信资料，不能提升权限或读取密钥；网页读取不访问设备本地网络。

## 上下文、压缩与提示词

预算是输入加输出总量，并与模型元数据/手动上限取交集。Token 显示是估算（图片也计入），返回实际 prompt usage 时校准，不是精确 tokenizer 或账单。自动策略保留预算内最近完整轮次；全量超限明确报错；窗口保留最近 N 轮加当前问题；摘要策略使用活动版本和未覆盖原始轮次。

自动压缩达到阈值且有超过保留轮数的旧历史才请求摘要。可指定独立 Provider/模型；大历史按摘要模型预算处理完整旧轮次，后续继续覆盖尚未摘要的部分。保存覆盖消息 ID、时间、模型及额外 usage。格式错误、请求失败或取消不替换旧版本。System Prompt 不被压缩覆盖；编辑旧消息会停用可能过时的活动摘要，版本历史仍保留。

关闭自动压缩切到窗口，可显式重选摘要策略。多层提示词按应用、Provider、模型、会话顺序合并，后级更具体配置优先；每次请求重新计算，关闭预设立即作用于下一次请求。Prefix 是独立的 assistant 输出前缀，不与 System Prompt 混用。

## 隐私

API Key 只在 Keychain（ThisDeviceOnly），不进入 UserDefaults、SQLite、导出或应用日志。临时 URLSession 无持久 Cookie/缓存，不绕过证书校验。普通聊天发往用户选择的模型服务商，不发往作者服务器。

搜索将查询/URL 发送至 DeepSeek；额外摘要把历史发给当前或独立模型，可能产生费用，需在控制台同意后启用。导出含私密聊天、思考与图片，请自行选择目的地。导入只新增副本，不导入密钥、不覆盖旧会话；检查 80 MiB 限制、版本/重复 ID、实际图片格式/尺寸、消息/工具参数和上下文配置。数据库无法解码时暂停写入，保护原文件。

## 工程与构建

```text
ios/AkiChat.xcodeproj/       完整工程与共享 Scheme
ios/AkiChat/Models/          Codable、Provider、模型库、工具、来源、摘要、预设
ios/AkiChat/API/             请求适配、SSE、delegate、模型发现、JSON HTTP
ios/AkiChat/Services/        AppStore、ChatRun、ContextManager、SummaryService、工具/搜索、图片
ios/AkiChat/Storage/         Core Data SQLite、Keychain
ios/AkiChat/UI/              聊天、抽屉、模型库、控制台、预设、原生 Markdown/UIKit
ios/AkiChatTests/            Mock URLProtocol、脚本化多轮测试、XCTest
ios/scripts/                工程生成、兼容性、实际 App/Framework/IPA 校验
.github/workflows/          构建、测试、Artifact、Tag Release
docs/                       真机验收矩阵、后续 TODO
```

Xcode 16.4 打开工程；Swift 5、Deployment Target 固定 14.0，Bundle ID 固定 com.akisenn.akichat。使用 NavigationView、PHPicker、UITextView、UIVisualEffectView，不使用 NavigationStack、SwiftData、PhotosPicker、URLSession.bytes 或 SwiftUI 原生 Markdown。无第三方 Markdown 包。

```sh
python3 ios/scripts/generate_project.py
python3 ios/scripts/check_compatibility.py
xcodebuild -project ios/AkiChat.xcodeproj -scheme AkiChat \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build/device ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
  IPHONEOS_DEPLOYMENT_TARGET=14.0 CODE_SIGNING_ALLOWED=NO build
python3 ios/scripts/package_ipa.py \
  build/device/Build/Products/Release-iphoneos/AkiChat.app \
  build/AkiChat-iOS14-unsigned.ipa
```

Windows 可编辑和 Python 自检，不能运行 Xcode。新增 Swift 文件后重新生成并提交工程。图标已提交，仅重生成需要开发工具 Pillow。

工作流支持 push、workflow_dispatch、Tag push 与已发布 Release，使用 GitHub macos-15、固定 Xcode 16.4 和匹配 iOS 18.5 模拟器。先真机 arm64 Release 无签名编译，再检查 App、嵌入 Mach-O/Framework 的 arm64/iPhoneOS/最低系统，打包两种 IPA，执行 Mock 测试与截图，最后上传。模拟器测试宿主另用本地 ad-hoc 签名与最小普通 Keychain entitlement，解决无签名测试宿主缺少访问组的 -34018；CI 身份前缀不是 Apple 团队或账号，也不用于真机 Release。只在全部通过后发布 tag Release。失败日志与 xcresult 在 AkiChat-build-diagnostics。

打包检查主程序、执行权限、Bundle ID、Info.plist、MinimumOSVersion 精确 14.0、Assets.car、无 provisioning、unsigned 确无签名、ZIP CRC 和 Payload/AkiChat.app；不接受模拟器、空文件或假 IPA。发布标签沿用 `v1.2.0` 这样的 1.x.x 编号；推送版本标签即授权构建与测试通过后发布附带真实 IPA 的 Release。具体已执行状态见 [Actions](https://github.com/AkiSenn/AkiChat/actions)。

## 测试与排查

Mock 测试覆盖请求/路径、模型列表及 HTTP 错误、能力、SSE 每字节分片、reasoning/tool_calls、Function Calling 多轮、Search/Fetch、权限、计算、预算/阈值/工具链、摘要失败/回滚、提示词、Prefix、图片、SQLite、Keychain、导出与 iOS 14 元数据。源码静态检查与 SDK availability 编译检查共同使用。

**未声称在用户 iPhone XR / iOS 14.8 安装或使用真实 API Key 验收成功。** 较新模拟器不能代替真机，待执行项见 [DEVICE_TEST_MATRIX.md](docs/DEVICE_TEST_MATRIX.md)。

| 问题 | 排查 |
|---|---|
| /models 404/空列表 | 保留缓存或手动添加，接口不一定实现发现 |
| 图片/工具按钮禁用 | 能力未声明；确认文档后在模型库覆盖 |
| 401/403 | 对应 Provider 密钥或权限 |
| 402/429 | 余额、频率、并发或额度 |
| 400/422 | 核对模型 ID、路径、能力、输出字段；推理模型可关闭采样参数 |
| 搜索不启动 | 检查工具总开关、模式、模型能力、外部请求同意及官方 DeepSeek 密钥 |
| 上下文不足 | 调整预算/窗口/摘要策略；原始记录保留 |
| 摘要失败 | 旧版本保留，重试或换摘要模型 |
| Keychain 错误 | 确认 TrollStore 注册、固定 Bundle ID、ldid 正常；不改为明文密钥 |
| 后台停止 | 主动取消并保存，避免 iOS 14 后台挂起形成残缺请求 |
| CI 排队或失败 | 等待 macOS 队列，读取真实日志修复；不提高部署目标或忽略错误 |

## 开源与后续范围

独立原生实现，只参考 [Chatbox](https://github.com/chatboxai/chatbox) 通用功能理念，不复制其 GPL 实现、商标或资产。真实提交记录归属开发贡献；共同作者尾注遵循已核对的官方实现，具体见 AUTHORS，GitHub Contributors 展示不作保证。

Bing HTML 实验搜索、Tavily/BoCha、MCP、复杂公式、图片生成、更多主题和跨会话账单统计未实现，没有虚假入口；扩展接口与边界见 [TODO](docs/TODO.md)。核心搜索不依赖 Bing 网页解析。

协议核对（2026-10-23）：[DeepSeek Chat](https://api-docs.deepseek.com/api/create-chat-completion/)、[Models](https://api-docs.deepseek.com/api/list-models/)、[Thinking/tools](https://api-docs.deepseek.com/guides/thinking_mode/)、[Search/Fetch](https://api-docs.deepseek.com/guides/search/)、[Vision](https://api-docs.deepseek.com/guides/vision/)、[Prefix Beta](https://api-docs.deepseek.com/guides/chat_prefix_completion/)、[OpenAI Chat](https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create)。
