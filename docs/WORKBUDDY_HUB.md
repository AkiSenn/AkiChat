# AkiChat × WorkBuddy2API-Hub 兼容说明

参考网关：[ardeyouxipianyi/workbuddy2api-hub](https://github.com/ardeyouxipianyi/workbuddy2api-hub)。

本适配以其公开的 OpenAI Chat Completions API 为主，不要求 AkiChat 登录腾讯账号，也不在客户端存储网关的上游账号凭据。

## 配置

1. 先在网关的设置页面创建、启用一个 API Key，并按照需要将其绑定到国际版或国内版。
2. AkiChat → 设置 → 模型与 API Key → 添加 WorkBuddy2API Hub。
3. 推荐填写 HTTPS 反向代理地址，**包括 /v1**：例如 `https://proxy.example.com/v1`。填网关 API Key（不是面板密码），Chat 路径使用 `/chat/completions`、Models 路径使用 `/models`。
4. 保存后进入模型库刷新，选择网关实时返回的模型；若 /models 不可用可手动添加模型 ID。模型列表不保证该 Key、区域和账号当前都有调用权限。
5. 如使用同一可信 Wi-Fi 上的本地网关，填 `http://192.168.x.x:8788/v1` 并显式开启「允许本地 HTTP」。这会在局域网以明文发送 Key 和聊天文本，只有可信网络适用。应用仅声明 NSAllowsLocalNetworking，不启用全局任意 HTTP。iOS 14 真机仍需验证 ATS 对 IP literal 的具体行为。

## 协议差异

- 网关使用 `GET /v1/models`、`POST /v1/chat/completions`；也支持 `POST /v1/responses`，AkiChat 当前仍沿用 Chat Completions。
- 网关模型 ID 如 `deepseek-v4.1-flash`，不同于 DeepSeek 官方 API 的 `deepseek-flash`。客户端不改写它。
- 兼容元数据包括 `context_length`、`max_output_tokens`、`supports_vision`、`capabilities.vision`、`reasoning_efforts`、`reasoning_default_effort` 与 `reasoning_can_disable`。实际字段缺失仍由用户手动覆盖能力，不猜测。
- WorkBuddy 思考等级采用标准 `reasoning_effort`，不发送 DeepSeek 独有 `thinking` 块。无效档位回退到网关宣告的默认档位，禁止关闭思考的模型不强行发送 `none`。
- 网关 API Key 可以限制区域、模型和账号；模型存在于目录不意味着一定可调用，错误由网关返回并显示。
- AkiChat 的「联网」按钮当前调用 DeepSeek 官方 Search/Fetch，因此不会自动调用网关的本地 Web 搜索工具。请勿将两者混为一谈；WorkBuddy Web 搜索支持可作为单独功能迭代。

## 验收

自动测试覆盖模型发现、推理参数、URL 与局域网 HTTP 限制。真机需要逐项验证 HTTPS / LAN、Keychain、滚动流式对话、模型切换、切换后 model 参数、SSE 工具回放、429/400 错误以及升级后旧数据保留。当前未执行 iOS 14.8 真机或真实网关测试。

网关的账号操作、免费额度与使用条款由网关服务方决定。不要公开暴露默认面板密码、API Key 或未加保护的 8788 端口。
