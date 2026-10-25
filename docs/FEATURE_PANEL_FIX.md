# 深度思考与联网独立面板回归修复

## 原因与事件链

此前阶段 A 只交付 API 添加流程，阶段 B 面板尚未实现。ChatComposer 保留直接 toggle、WorkBuddy 跳控制台和循环联网模式的旧事件；ChatView 无独立路由，控制台与全局设置又绑定相同状态，导致入口重复和预期脱节。

现在 ChatComposer 注入 onThinking/onSearch，由 ChatView 收起键盘后进入独立 thinking/search Sheet；两者均为 iOS 14 NavigationView + ScrollView，有关闭和完成按钮，不使用系统新版 detents，不嵌套普通操作 Sheet。

ReasoningControls 只由 ThinkingPanel 调用。其状态来自当前 Conversation，通过 AppStore 更新并由 RequestBuilder 使用；生成期间只读。声明档位优先，未知仅默认，固定/不可关闭明确说明；切换模型不清除思考偏好，不向通用接口发送 DeepSeek 私有 thinking。

SearchPanel 独立维护关闭/自动/每次、来源和搜索授权。复用既有 Provider + Keychain 配置，新增搜索来源写入独立凭据引用；不切换聊天 Provider/Model。未配置也可以打开面板。搜索使用搜索来源的合法凭据，聊天使用聊天模型自己的凭据。

## 真实请求与数据保护

- DeepSeek 的 thinking 与 reasoning_effort 按[官方思考协议](https://api-docs.deepseek.com/guides/thinking_mode/)发送；模型目录保留声明的 reasoning_efforts、默认、固定、可关闭和 always_reasoning。Hub 继续由 HubReasoning 适配；通用接口仅按明确元数据启用标准 effort，不使用私有协议。
- 保留[官方 Search/Fetch](https://api-docs.deepseek.com/api/search/)链路；不实现或宣传尚未接入的 SearXNG/Brave。
- 自动模式仅支持真实工具调用的模型；搜索工具白名单与高级日期/计算开关分开，不能因高级工具关闭而显示假联网。
- 每次搜索：工具模型保留有界工具链；无工具模型先通过 SearchProviderService 搜索，成功后将有界、带真实 URL、标记为不可信的 JSON 参考加入请求副本，并计入上下文预算。返回消息保留原始用户内容与真实来源，不伪造 assistant 工具调用。空来源、错误或取消不继续向模型发送请求。
- UI 普通搜索/思考控制只保留面板入口。控制台保留摘要独立费用授权、高级工具、上下文、提示词、图片和 Prefix；开启 Prefix 通过统一操作关闭联网，不在控制台提供第二个搜索设置器。
- 新增的 reasoning 元数据及 searchConsent 均为 optional。旧共享 externalConsent 只作为尚无独立搜索选择时的兼容默认；明确拒绝搜索不会被摘要授权重新开启。不改数据库键、历史格式、Keychain 容器、原文或摘要版本。
- 不变更版本 1.2.0/build8、Bundle ID com.akisenn.akichat、iOS 14.0 最低要求。按仓库交付硬规则直接使用 GitHub App 提交默认分支及运行 Actions；不创建 PR、tag 或正式 Release。

## 验证范围

新增 FeaturePanelTests 验证协议参数、未知/强制思考、状态与旧授权兼容、无工具预搜索、真实自动工具搜索、关闭零搜索、失败/取消和聊天/搜索密钥隔离。UI 测试执行真实按钮点击、收起键盘、开关/档位、灰色重开、强制与未知模型、独立搜索面板、授权及三种模式，附截图。DEBUG 测试凭据为 Mock 且不参与 Release。

兼容性脚本检查旧 composer 状态修改/跳控制台行为及重复入口不能回归；工程生成、iOS 14 检查和差异检查本地执行，Xcode 编译与 UI XCTest 以真实 macOS Actions 结果为准。iOS 14.8/16、TrollStore、真实 Key/模型/搜索服务、键盘与深色布局仍须人工实机验证，见 DEVICE_TEST_MATRIX.md。
