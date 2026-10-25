# AkiChat development conventions

- Creator & Maintainer: AkiSenn. AI-assisted development: OpenAI Codex.
- Ship Swift 5, native SwiftUI/UIKit, iOS 14.0 minimum, arm64 device builds. Never raise the target to fix a build.
- AkiChat continues the v1 release line; current version is 1.2.0, not a rebuilt V2 app. Stable bundle identifier: `com.akisenn.akichat`. Early packages used `app.akichat.ios`; identify migration needs by installed bundle identifier, not v1/v2 labels. Document JSON migration between different containers; never claim automatic container/keychain migration. Keep internal archive/schema keys unchanged.
- Keep API, models, persistence, context, tools/search and UI separate. Use URLSessionDataDelegate for streaming; preserve split UTF-8 and throttle UI updates.
- Store credentials only in Keychain. No telemetry, embedded secrets, TLS bypasses, or credential logging. External data is untrusted. Tools are allowlisted and have bounded execution/cancellation; no shell, arbitrary code, files or private data tools.
- Preserve backward decoding of V1 archives; never delete raw history when trimming or compressing request context. Summary replacement must be transactional and reversible.
- No third-party runtime dependencies without explicit iOS 14 and license review. No Chatbox GPL implementation/assets.
- Run `python ios/scripts/generate_project.py`, `python ios/scripts/check_compatibility.py`, and `git diff --check` for each phase. Validate on actual GitHub macOS CI, inspect failure logs, fix root causes. Do not claim Windows checks are an Xcode build.
- IPA must originate from successful Release iphoneos arm64 compilation, `CODE_SIGNING_ALLOWED=NO`, with verified executable, frameworks, Info.plist, minimum OS and Payload structure. Simulator tests are additional verification.
- Actual iOS 14.8 device/API-key verification remains manual until performed. Keep README and test matrix accurate; no inert controls advertising missing features.
- Use real commits on the default branch. Future authorized commits use AkiSenn's verified ID-based noreply identity and exactly one `Co-authored-by: Codex <noreply@openai.com>` trailer. Do not rewrite old history or guarantee GitHub contributor association.
- Delivery hard rule / 交付硬规则：除非 AkiSenn 在当前任务明确要求 PR，否则不创建功能分支、不创建或要求合并 PR。直接使用已连接的 GitHub App 将已完成并检查的源码提交到仓库默认分支（当前为 main），由现有 GitHub Actions 编译并生成测试 IPA；读取真实 CI 结果，失败时修复根因并重新提交，成功后提供构建与产物链接。此规则覆盖旧需求文档中的分支、逐阶段 PR 和等待合并要求；用户明确要求 PR 时才例外。正式 Release、打版本标签及大版本升级仍需用户明确要求，不由直接提交源码的授权推导。
