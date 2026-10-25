# 输入高度测量：单项维护

2026-10-25。基于 `433e9b3`，保留现有原生UI、iOS14部署目标、1.1版本、供应商能力和构建流程。

## 核对与用户复现

上轮的局部消息通知、草稿防抖、后台Markdown解析、尺寸缓存及滚动节流仍存在，不能假定旧问题尚未修复。用户本轮反馈输入/键盘/模型切换卡顿，空白短会话也存在，长会话更明显。表格路径与主要症状不吻合，候选实验已用独立revert提交撤回，不作为交付优化。

剩余可复现的输入开销：`ComposerTextView.measureHeight()`对每次编辑使用无限高的`sizeThatFits`，取得整篇草稿高度，再截到140。长草稿需要完整文本布局；主线程测量工作与输入框实际最多显示的高度不成比例。但这不证明空白会话的键盘或模型面板卡顿也是同一原因。

## 唯一优化

超过512个UTF-16字符时，用独立TextKit容器在140点显示范围内判定是否溢出；溢出直接返回已有上限，不再请求整篇高度。未溢出和短输入仍走原生精确测量，原42…140高度范围、删除回缩和宽度变化行为不变。独立测量storage不挂到编辑器上、不修改正文/选区/marked text、不访问编辑器layoutManager触发TextKit兼容切换。没有调整键盘、供应商、滚动、毛玻璃、Markdown或面板功能。

有限容器使用iOS14已有的[NSLayoutManager](https://developer.apple.com/documentation/uikit/nslayoutmanager)；参考Apple关于[UITextView.layoutManager](https://developer.apple.com/documentation/uikit/uitextview/layoutmanager)的说明，保持编辑器自身引擎不变。

## 必要测试和指标

`ComposerPerformanceTests`包含3项：多语言/emoji/窄宽度/尾换行的原生高度一致性；长文删除回缩及选区/宽度；同进程配对测量。既有工作流继续执行原有回归，不扩展全项目审计。

在同一个模拟器进程中，以短输入、约8k UTF-16折行草稿、2000行草稿，分别使用不同但相同配置的UITextView，预热后交替执行12次文本编辑及高度测量，4组样本。记录完整编辑+测量耗时、结果高度/文本相同；日志标识`COMPOSER_HEIGHT_BENCHMARK`。测试用Debug/-Onone；不将其比率当作Release真机、完整键盘动画、滚动或FPS提升。`textStorage.append`是受控编辑实验，不等同真实键盘输入/IME组合。

Windows不能运行Xcode，真实编译、配对结果及实际模拟器版本记录于PR/Actions。iOS14.8和iOS16真机、空白短输入的独立卡顿、真实IME、键盘及模型面板动画仍需设备采样；长历史但短草稿不保证从这项修改获益。没有凭本次结果声称整个卡顿问题已经解决。不会创建Tag/Release或自动合并。
