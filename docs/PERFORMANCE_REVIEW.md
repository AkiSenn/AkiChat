# 聊天性能与模型选择器维护

日期：2026-10-23。基于仍未合并的 WorkBuddy PR #2（31492e3），追加可回滚提交，不覆盖或合并其兼容改动。显示版本1.1、构建号7，Bundle ID和部署目标14.0不变。

## 源码确认的高频路径

| 原路径 | 修改 |
|---|---|
| 每80ms快照替换 AppStore.conversations 并发布 renderRevision / generationStatus | 稳定 MessageCell 对象，只有当前行发布快照；会话存储每2秒检查点及终止保存，状态文字未变时不再发布 |
| 草稿每键触发 conversations 发布，保存防抖前即捕获全库快照 | ComposerState 单独通知输入组件；700ms防抖实际触发时才捕获快照，编码/写入仍在串行后台队列 |
| GeometryReader → 全列高度 PreferenceKey → scrollTo 持续反馈 | 去掉全列高度偏好；公开 UIScrollView KVO +150ms合并跟随，拖动/减速时不抢滚动，明确返回底部与切换会话才用 scrollTo |
| computed provider 在多个控件读取时反复 apply，Hub 元数据 JSON 重复解码 | 选择/目录/Provider变更时解析并缓存，普通输入和token不重复解析 |
| Markdown onAppear/onChange 在主线程解析，代码前的稳定块反复布局 | 可取消后台解析，12MiB/96条完成文本缓存；流式前缀不占历史缓存，稳定块等值比较 |
| UITextView 每次update（含自身高度反馈）都 sizeThatFits | 内容/字体/宽度变化才测量，跳过零宽度，过期高度回调丢弃；正则只编译一次 |
| 消息和附件body同步UIImage(data:) | ImageIO后台缩略图，32MiB成本缓存，保留图片原始数据与发送格式 |
| 模型面板展开即遍历请求所有Provider，VStack急切生成行 | 本地缓存优先，手动刷新与首次配置发现，惰性行；搜索过滤不相关服务商 |

现有传输已经在串行delegate队列解析SSE并80ms合并快照，数据库编码原先也在后台；没有把它们错误描述为“原来每token直接写数据库/主线程解析网络”。主要修改是发布范围、快照保留时间、渲染/解码与滚动反馈路径。

## 数据和命名

- 后台、停止、完成、切换/新建会话立即保存缓冲草稿与最新流式消息；导出使用最新草稿。普通崩溃前700ms内尚未提交的草稿仍受进程异常退出限制，不承诺零窗口丢失。
- 旧 DeepSeek 默认名称只按确切旧字符串修正显示，UUID、Keychain引用和模型ID保持原样。主标题为Provider.name、副标题为当前会话模型ID；自定义Provider名称不改。
- DeepSeek /models可以返回Pro或未来模型，不限制为Flash，不预置Pro权限；请求原样发送所选ID。失败不删除缓存或手动模型。
- 换到不支持思考/工具的模型时关闭不兼容开关，图片附件保留并提示；上下文按新模型容量取安全交集，原始历史不删。
- 保留单个输入区域毛玻璃，支持减少透明度；没有嵌套新增大范围模糊或动画。深色根背景和导航同色纯黑，只有背景越过安全区域，控件仍受Safe Area约束。

## 可复核验证

- XCTest覆盖100/500消息稳定行对象、连续100次流式通知不发布历史行、输入不发布整库、后台/切换/删除其他会话的草稿保留、停止后最新流式内容落库、后台Markdown解析和过期结果拒绝、滚动暂停/恢复、DeepSeek命名不改变身份与其他模型真实请求。
- 增加500消息/200次快照的XCTest measure，记录当前机器耗时，不将合成计时当作FPS、A12性能或前后改善百分比。
- 原生XCUITest覆盖空白、100、500条合成会话，打开模型面板/搜索/跨Provider切换、抽屉、键盘弹出及关闭、草稿保留、阅读历史与返回底部。DEBUG测试数据仅驻内存，Release中不包含该入口，不使用真实Key或远程请求。
- CI先尝试已安装且可用的iOS16运行时，否则使用现有Xcode16.4/iOS18.5组合；runtime-report.json记录实际版本，不将18.5冒充16。当前托管镜像未预装iOS16。
- CI尝试500条合成页面的10秒Time Profiler，成功保留trace和目录，失败保留profiler.log并明确不可用。该采样是静态合成页面，不代表完整手势/键盘/流式交互的性能分析，也不测量FPS。
- UI截图、XCTest/UI xcresult、runtime-report、Profiler日志随构建产物保存。具体实际通过状态和耗时见当前PR/Actions；Windows静态检查不是Xcode构建证据。

## 待设备验收

Windows环境无法运行iOS16真机或本地Instruments。仍需在XR/iOS14.8以及iOS16设备上使用真实长会话、图片、代码与流式输出，测量Time Profiler/Core Animation/FPS、键盘和手势响应、后台恢复。没有声称仅凭源码分析已解决所有iOS16卡顿。
