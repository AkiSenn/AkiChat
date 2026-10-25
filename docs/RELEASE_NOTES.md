AkiChat 1.2.0 是现有 v1 系列的持续迭代，Created by AkiSenn · Built with OpenAI Codex。

- 纠正此前误用的 V2/2.x 名称，应用版本为 1.2.0（build 8），并非重建新一代 App。

- 新增模型自动发现/缓存/搜索/收藏与能力覆盖。
- 新增官方 DeepSeek Search/Fetch、受限 Function Calling 工具循环及来源记录。
- 新增每会话 Token 预算、结构化上下文摘要、版本回滚和四层 System Prompt 预设。
- 保留 SwiftUI 原生聊天、图片理解、SSE 流式思考、Keychain 和本地 SQLite 历史。
- 固定流式 Markdown 刷新时钟，保留四层提示词顺序及清空摘要修复。
- 保留 WorkBuddy2API Hub 兼容、按服务商分组的模型切换及原始模型 ID，适配推理和工具能力。
- 保留流式局部更新、草稿防抖、后台 Markdown 与图片缩略图；多段长草稿可复用有完整段落前缀证明的输入高度缓存。未声称空白会话的键盘/模型面板卡顿已全部解决。

下载 `AkiChat-iOS14-unsigned.ipa`，交给 TrollStore 安装；完全无签名包被安装器拒绝时尝试 `AkiChat-iOS14-adhoc.ipa`。两者来自实际 arm64 真机 Release 构建，不需要 Apple 付费证书。校验和见 SHA256SUMS.txt。

Bundle ID 保持 `com.akisenn.akichat`，现有容器的历史、配置和密钥引用不变。仅当早期安装包使用 `app.akichat.ios` 时，才需导出 JSON、在当前应用导入并重新配置密钥；版本命名修正不代表能跨容器自动迁移。备份前不要删除早期安装包。

工具、搜索和自动摘要默认关闭。启用外部搜索/额外摘要前需阅读并同意数据发送与费用提示。

CI 包含 iOS 14 目标的真机构建、Mock 单元测试和较新模拟器启动验证。iPhone XR / iOS 14.8 的实际安装、真实密钥对话仍需人工执行；见仓库 docs/DEVICE_TEST_MATRIX.md。未将模拟器测试宣称为真机验收。

Bing HTML 实验搜索、Tavily/BoCha 和 MCP 尚未实现，见 docs/TODO.md。

本次将 v1.2.0 设为最新发行版，并将误编号的 v2.0.2 撤回为草稿，保留其标签和附件；后续沿用 1.x.x 编号。
