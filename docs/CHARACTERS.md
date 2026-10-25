# 角色库与酒馆角色卡 MVP

AkiChat 仍为通用 AI 客户端，角色是会话设定，不是 Provider 或 Model。独立 Swift 实现，仅参考公开格式及产品理念；没有复制 RikkaHub（AGPL）或 SillyTavern 实现，没有新增第三方运行时包。zlib 为 iOS SDK 自带系统库。

格式依据：[CCv2](https://github.com/malfoyslastname/character-card-spec-v2/blob/main/spec_v2.md)、[CCv3](https://github.com/kwaroran/character-card-spec-v3/blob/main/SPEC_V3.md)。这是核心格式及基础运行支持，不宣称完整酒馆生态兼容。

## 使用

1. 会话抽屉 → **角色库** → **导入角色 · PNG / JSON**。
2. 在系统“文件”选择原始 PNG 或 JSON；相册、截图或重新保存的 PNG 可能不含角色元数据。
3. 后台本地解析后显示头像、设定、作者说明与兼容范围，点击确认才保存到角色库。取消预览不会创建角色或调用 API。
4. 进入角色详情，选择真实服务商/模型（默认当前模型）、默认或备用开场白，点击开始对话。开场白直接本地显示，不收费生成。
5. 首页顶部显示角色名及真实服务商/模型；仍可点击顶部切换模型，角色绑定保持。角色回复使用本地缩略头像，用户样式不变。
6. 设置中的“角色对话中的用户称呼”用于 `{{user}}`，默认“旅行者”，最多 60 字；不改变普通聊天。更改称呼作用于后续请求，已有消息不被改写。

## 导入支持

| 格式 | 本版行为 |
|---|---|
| V2 JSON | spec=chara_card_v2、spec_version=2.0；要求六个基础字符串字段，不能只凭 name 识别 |
| V3 JSON | spec=chara_card_v3、spec_version=3.0；核心字段运行，完整原始对象保留 |
| V2 PNG | 原始字节读取 chara 元数据 |
| V3 PNG | 原始字节读取 ccv3；同时存在时优先有效 V3，无效 V3 可回退有效 V2并在预览说明 |
| PNG tEXt / zTXt / iTXt | Base64 UTF-8 JSON；按压缩标志与 zlib 方法处理，iTXt 校验 UTF-8；也接受 UTF-8 JSON 文本载荷 |
| V1 / CHARX / 在线卡片 | 暂不支持，不误认为 V2，不自动下载 |

结构化保存 name、description、personality、scenario、first_mes、mes_example、alternate_greetings、system_prompt、post_history_instructions、creator_notes、tags、creator、character_version、character_book、extensions。原始 JSON 完整保存，V3 nickname/assets/group_only_greetings 及未知字段不会丢弃；资源引用、脚本、群聊设定等不执行、不下载。原始 PNG 独立保存以保留未知嵌入资产；头像是从去除元数据后的安全 PNG 光栅生成的 256 px JPEG，不用重编码图片反向读取角色卡。

## 实际请求组装

- 复用 PromptResolver → ContextManager → RequestBuilder → ChatRun，无第二套网络实现。
- 绑定会话的卡片 system_prompt 非空时替代该会话原本的通用提示词；支持 `{{original}}` 引用原合并提示。为空时保留原提示。全局设置不会被改写。
- 依次组合世界书 before_char、角色名/背景/性格/场景、带“不是已发生聊天”标注的 mes_example、世界书 after_char。作者说明、标签、作者和版本不注入。
- 没有 system 能力的模型收到明确标注的 user 角色设定作为兼容降级，仍使用真实当前 Provider/Model/Key。
- post_history_instructions 展开后以末尾兼容 user 提示发送，在历史之后、Assistant Prefix 之前；它只存在于请求中，不写成真实聊天。避免依赖各服务商对末尾 system 的不同支持；`{{original}}` 在此对应空的默认历史后提示。
- `{{char}}`/`{{user}}` 大小写兼容，单次字符串替换，不递归、不执行模板代码，限制替换次数及展开大小。超过上限明确报错，不发送残缺设定。
- 开场白有稳定消息 ID，标注“开场白 · 本地”、不提供付费重生成。首个 user 轮次保留时仅在请求中出现一次；该轮次被窗口/摘要省略后，不反复强行添加。原始开场白仍留在历史，不占一个 user 轮次。
- 角色设定、开场白、世界书及历史后提示纳入请求预算；容量不足时报错，不清空历史。

## 世界书范围

保存完整 character_book 原始数据；详情展示条目与状态。运行支持 enabled、constant、字面关键词、case_sensitive、selective + secondary_keys、insertion_order、before_char/after_char。扫描最近 1–12 条 user/assistant 消息（默认 6），扫描文本最多 16384 字，文字替换后采用保守预算（最大约 1024 tokens），整条加入或跳过。

不运行递归扫描、正则、复杂 priority、扩展条件或装饰器。带未知扩展、正则/装饰器或不支持位置的条目标为“仅保存”，不假装生效；预算外条目不注入。详情中的“可触发”不代表每轮必定加入。

## 存储与安全边界

- 角色库独立使用原 SQLite RecordDatabase 的 `characters.v1` 记录；原有记录键不变。
- Conversation 新增可选 CharacterBinding（稳定 ID + 完整设定/头像快照 + 开场消息 ID），旧普通聊天仍可解码。删除角色仅从角色库移除，已有对话和快照保留。
- JSON 会话导出包含角色快照、必要关联和缩略图；导入重新验证快照。原始 PNG 扩展资产不随会话 JSON 打包，跨容器导入时这些资产只保留引用而不执行；核心角色对话仍可用。Markdown 标明角色，完整设定以 JSON 为准。
- 原始 PNG 在应用私有 Application Support/CharacterAssets 中按 UUID 原样保存，禁止卡片控制路径；删除角色后资源保留以保护历史及未知资产。当前总量上限 128 MiB，不提供虚假的自动清理按钮。
- 单文件 16 MiB；JSON 512 KiB、32 层、最多 20000 容器；PNG chunk 8 MiB、4096 chunks、角色候选 16 段、元数据累计 2 MiB、单段解压 1 MiB；校验签名、CRC、IHDR、边界、IEND及像素限制（最长边4096、800万像素）。
- 单文字字段 64 KiB，备用开场最多64条，世界书最多256条、每条8 KiB、每组关键词最多8个。角色库最多128张，设定与缩略图合计32 MiB，角色会话快照合计64 MiB，头像不超过128 KiB/256px。所有读取、解析、解压、缩图及资源写入有界且在后台执行。
- 卡片无设备/Keychain权限，不能修改工具白名单、联网授权、Provider 或全局提示词；不会自动访问卡片资源URL。角色设定会在开始聊天后发给用户选定的模型服务商，导入预览明确说明。

## 验证与待验证

单元测试覆盖 V2/V3 JSON、PNG V2/V3优先级、zTXt/iTXt、头像、CRC/恶意长度/压缩炸弹/嵌套上限、变量、世界书、真实请求提示词与普通/跨角色隔离、开场轮次、持久化/删除/导出及文件原样保存。UI 测试覆盖抽屉角色库、文件选择器打开/取消、详情开始对话、本地开场白、顶部真实模型切换。网络使用 Mock。

本地 Windows 的静态检查不是 Xcode 构建；实际编译、测试和 IPA 结果以 Actions 为准。仍需 iPhone XR/iOS14.8及iOS16验证：Files/iCloud提供者原始PNG/JSON导入、预览确认/取消、头像/长设定滚动、备用开场白、真实API连续角色聊天、切换模型与重启恢复、世界书及历史压缩、TrollStore安装。版本、Bundle ID 和最低 iOS14.0保持不变，不发布正式 Release。
