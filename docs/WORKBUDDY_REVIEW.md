# WorkBuddy 兼容审查与修复记录

审查日期：2026-10-23。用户报告原 V2 已在 iPhone XR / iOS 14.8 / TrollStore 启动运行；该报告不等于本次增量修复已完成真机验证。

## 实际基线

任务描述称 PR #1 尚未合并。实际 GitHub 元数据表明 [PR #1](https://github.com/AkiSenn/AkiChat/pull/1) 已合并，main 为 `768a1541dc943e1130a08ab3015a661bc22bc5eb`，PR 原头为 `9a4030f535ce43bef8088c7ca65ddcd7dc3c05f2`。本次从该 main 增量修复，另留 PR，不撤销合并、不重写历史。

协议依据为上游 main 检出的 `477ba36ceea78ec4252c47a68e94a5a1612bab0b`：[wb_proxy.py](https://github.com/ardeyouxipianyi/workbuddy2api-hub/blob/477ba36ceea78ec4252c47a68e94a5a1612bab0b/wb_proxy.py)、wb_catalog.py、模型目录、README 和测试 `_test_reasoning_effort_map.py`、`_test_models_available.py`、`_test_reasoning_backfill.py`。仅研究协议，没有复制网关实现到应用。

## 已确认的问题

| 原状态 | 修复 |
|---|---|
| 草稿声明局域网 ATS，但两个 CI 脚本禁止任何 ATS 字典 | 检查精确允许 NSAllowsLocalNetworking，仍拒绝全局例外和 TLS 覆盖 |
| 模型解析读 supports_tools / capabilities.tools | 补上实际 supports_tool_calls / capabilities.tool_calls，保留已有兼容别名 |
| 固定推理档位只用于推断能力，没有参与请求 | 应用 fixed/default/effort 列表优先级；档位使用字符串，不限于 Swift 固定枚举 |
| 思考设置只提供固定枚举，关闭按钮可能误导 | 目录动态选择；固定档位、不可关闭或未声明关闭能力均有说明，显示本次实际参数 |
| 顶部先选 Provider 默认模型，再进入二级模型库 | 一层按 Provider 分组的模型列表，跨 Provider 搜索/收藏/选中标记，复用原目录和会话选择状态 |
| 缺失的会话模型可能静默回退到 Provider 的另一个模型 | 未找到时要求重新选择；删除 Provider 清除旧模型引用 |
| 刷新后手动模型命中远端目录会丢失 manual 标记 | 保留手动管理、收藏、覆盖及缺失缓存；错误与空目录不覆盖原目录 |
| 工具请求回传 Hub reasoning，但预算估算漏计 | 预算与实际回传一致，工具链仍完整保留 |
| 429 直接失败，无退避 | 首包前拒绝的 429 最多重试两次，尊重短 Retry-After；长冷却交给用户，部分流式响应不重放 |
| 深色聊天安全区域与顶部材质颜色不同 | 恢复纯黑根背景和同色顶部，不重新设计首页 |

## 保留的边界

- Chat Completions 是本版 Hub 传输协议；`/u/<ref>/v1` 路由前缀保留。
- Hub Responses / 网关本地联网未接入。客户端 Search/Fetch 使用独立官方 DeepSeek Key；普通 Hub 聊天和本地时间/计算工具不要求 DeepSeek Key。
- 模型目录不代表当前网关 Key 已获模型/区域/账号权限。不显示原始错误体，避免服务回显凭据进入界面或日志。
- Bundle ID、Keychain service、providers.v1/conversations.v1/settings.v1/catalogs.v2 均保留。新增字段可选；按维护者要求显示版本为 1.1，保留本次全部兼容修复。
- 无新增运行时第三方依赖。默认分支保持已有状态，本次修改留在修复 PR 等待审核。

CI 与产物的实际结果在修复 PR 中记录；真机待验证项见 DEVICE_TEST_MATRIX.md。Windows 源码检查不作为 Xcode 编译成功的证据。
