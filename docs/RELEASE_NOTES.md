AkiChat V2 原生 iOS 14+ 客户端，Created by AkiSenn · Built with OpenAI Codex。

- 新增模型自动发现/缓存/搜索/收藏与能力覆盖。
- 新增官方 DeepSeek Search/Fetch、受限 Function Calling 工具循环及来源记录。
- 新增每会话 Token 预算、结构化上下文摘要、版本回滚和四层 System Prompt 预设。
- 保留 SwiftUI 原生聊天、图片理解、SSE 流式思考、Keychain 和本地 SQLite 历史。
- 2.0.2 固定流式 Markdown 的刷新时钟，避免连续响应重建视图时重置刷新间隔；包括四层提示词顺序及清空摘要修复。

下载 `AkiChat-iOS14-unsigned.ipa`，交给 TrollStore 安装；完全无签名包被安装器拒绝时尝试 `AkiChat-iOS14-adhoc.ipa`。两者来自实际 arm64 真机 Release 构建，不需要 Apple 付费证书。校验和见 SHA256SUMS.txt。

**V2 Bundle ID 为 com.akisenn.akichat，与 V1 独立。先在 V1 导出 JSON，再于 V2 导入并重新填写密钥。**

工具、搜索和自动摘要默认关闭。启用外部搜索/额外摘要前需阅读并同意数据发送与费用提示。

CI 包含 iOS 14 目标的真机构建、Mock 单元测试和较新模拟器启动验证。iPhone XR / iOS 14.8 的实际安装、真实密钥对话仍需人工执行；见仓库 docs/DEVICE_TEST_MATRIX.md。未将模拟器测试宣称为真机验收。

Bing HTML 实验搜索、Tavily/BoCha 和 MCP 尚未实现，见 docs/TODO.md。
