# AkiChat × WorkBuddy2API Hub

本版使用 OpenAI Chat Completions，通过用户自己的网关访问模型。无需在 AkiChat 登录腾讯账号或保存上游 OAuth 凭据。协议审查基线和问题记录见 [WORKBUDDY_REVIEW](WORKBUDDY_REVIEW.md)。

## 配置与切换

1. 在 Hub 管理面板创建并启用网关 API Key，确认 Key 的区域、账号出口和模型白名单。
2. AkiChat → 设置 → 模型与 API Key → 添加 WorkBuddy2API Hub。
3. 填入 `https://example.com/v1` 或按账号定址的 `https://example.com/u/<ref>/v1`，填写网关 Key。Chat 路径 `/chat/completions`，Models 路径 `/models`。不改写网关返回的模型 ID：例如 `deepseek-v4.1-flash` 不是官方的 `deepseek-flash`。
4. 保存地址和 Key 后自动获取模型；点击顶部模型名，在同一面板按 Provider 分组搜索、收藏和选择。选择会更新下一请求的地址、Key、模型、能力和参数。生成过程中禁止切换。
5. 模型库可刷新、手动添加、覆盖能力和预算；手动模型与自动模型共存。404/405/空列表/鉴权失败均保留上次目录与手动模型。目录中出现不代表当前 Key 一定有调用权限。
6. 每个会话独立保存选择，重启保留。删除 Provider 后清除其旧模型引用；失效引用不会悄悄改发给另一模型。

## 可信局域网 HTTP

支持主动启用「允许本地 HTTP」，例如 `http://192.168.1.100:8788/v1`。仅允许私有 IPv4、链路本地/ULA IPv6、回环及 `.local` 名称；拒绝公网 HTTP、URL 中的账号密码、查询参数和重定向。优先使用 HTTPS 反代。

**HTTP 会以明文发送网关 Key、消息和图片，只能在用户主动信任的网络上开启。** 应用仅声明 `NSAllowsLocalNetworking` 和 `NSLocalNetworkUsageDescription`，没有 `NSAllowsArbitraryLoads`，没有自定义证书信任或 TLS 绕过。系统首次访问可能请求本地网络权限；如拒绝，到 iOS 设置 → 隐私 → 本地网络中允许 AkiChat 后重试。不使用 Bonjour 浏览或多播，不需要额外私有 entitlement。

依据 [Apple 本地 ATS 说明](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking) 与 [本地网络隐私说明](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)。本次 iOS 14.8 实机 LAN 权限与连接仍待验证。

## 推理、视觉与工具

- 解析 `context_length`、`max_output_tokens`、`supports_vision`、`capabilities.vision`、`supports_tool_calls` / `capabilities.tool_calls` 和推理元数据；未知能力保持未声明。
- Hub 仅使用标准 `reasoning_effort`，不发送 DeepSeek 私有 `thinking` 对象。UI 档位来自 `reasoning_efforts`，不固定限制为 low/high/max，支持 medium 和未来字符串档位。
- `reasoning_fixed_effort` 只在没有可选档位列表时固定；与列表同时出现时作为回退候选。无效选择回退到有效默认值或首个档位，UI 显示实际发送档位。无元数据则省略参数，交给网关默认。
- 只有目录明确允许关闭且不是 `always_reasoning` 时，关闭按钮才发送 `none`；`reasoning_can_disable=false` 不承诺关闭。旧会话的无效档位不会直接发给网关。
- 思考、正文和 usage 分开显示。工具历史按完整调用链回传 `tool_call_id` 和 reasoning，并计入预算；不截断为孤立 tool 消息。视觉未明确启用的模型禁止发送附件。
- 日期时间、安全计算和客户端 Function Calling 可使用 Hub，不要求官方 DeepSeek Key。

## 联网边界

AkiChat 的 Search/Fetch 仍是客户端调用 **DeepSeek 官方**服务，使用单独配置的官方 DeepSeek Key，绝不会把 Hub Key 发给 DeepSeek。Hub 聊天不要求该官方 Key。若会话主动启用联网但未配置独立密钥，会给出说明；可关闭联网继续普通聊天。

Hub `/v1/responses` 与实验性网关本地 `web_search` / `web_fetch` 未接入，不显示已经联网的虚假状态，也不让客户端和网关重复执行工具。

## 错误与重试

| 状态 | 排查 |
|---|---|
| 401 | 网关 Key 错误、缺失；不是面板密码或 OAuth |
| 403 | Key 是否启用、模型白名单、账号及区域权限 |
| 400/422 | 模型禁用、区域不匹配、参数不支持 |
| 404/405 | Base URL / 端点路径；模型发现不可用时手动添加 |
| 429 | 账号额度、频率或模型冷却；模型存在不代表可调用 |

聊天仅在收到 HTTP 429 且尚未收到响应内容时自动退避重试，最多两次，默认 1/2 秒；尊重不超过 30 秒的 Retry-After（秒数或 HTTP 日期），更长冷却直接提示等待。取消会取消待重试任务。200 后的断线、超时、部分 SSE 和已执行工具不会自动重放；手动重试可能产生新的费用。

## 数据与验证

Bundle ID、Keychain service、历史存储键、摘要、预设和工具设置保持不变。新增配置字段可选，兼容原 V2 和 PR #1 数据。补丁版本 2.0.3，没有升级到 3.0。源码/SDK 编译检查与 Mock 测试不能代替真实 Hub Key 和设备验证；待执行项见 [设备矩阵](DEVICE_TEST_MATRIX.md)。
