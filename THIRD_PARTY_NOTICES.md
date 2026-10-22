# 第三方与原创实现说明

AkiChat 应用运行时没有第三方依赖包。SwiftUI、UIKit、Foundation、Combine、Core Data、Security、PhotosUI、ImageIO 为 Apple 系统框架，按 Apple SDK 条款使用。图标和界面由本项目独立绘制，界面符号采用系统 SF Symbols。

Chatbox Community Edition（https://github.com/chatboxai/chatbox）采用 GPL-3.0，仅作为功能理念参考。没有复制、修改或分发其代码、组件、图标、字体或其他资源；不将其许可证替换为 MIT。

开发/构建工具不嵌入 IPA：

- Python：PSF License；脚本仅依赖标准库。
- Pillow（仅重新生成应用图标时需要）：HPND License，https://github.com/python-pillow/Pillow/blob/main/LICENSE 。PNG 由本项目几何绘图代码生成，Pillow 不分发到应用中。
- actions/checkout：MIT，https://github.com/actions/checkout/blob/main/LICENSE 。
- actions/upload-artifact：MIT，https://github.com/actions/upload-artifact/blob/main/LICENSE 。
- GitHub CLI：MIT，https://github.com/cli/cli/blob/trunk/LICENSE 。
- Xcode、Apple SDK 和 codesign：构建机预装的 Apple 开发工具，按对应许可使用，不随源码或 IPA 再分发。

TrollStore 与可选 ldid 是用户设备/构建工具，均未嵌入应用。使用 ldid 时请遵守所选发行版的 GPL 许可证并保留工具自身版权；不需要将 ldid 加入本项目。官方源码：https://github.com/opa334/TrollStore 、https://github.com/opa334/ldid 。
