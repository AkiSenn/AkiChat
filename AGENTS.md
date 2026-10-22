# AkiChat development conventions

- Creator & Maintainer: AkiSenn. AI-assisted development: OpenAI Codex.
- Ship Swift 5, native SwiftUI/UIKit, iOS 14.0 minimum, arm64 device builds. Never raise the target to fix a build.
- Stable V2 bundle identifier: `com.akisenn.akichat`. V1 used a different container; document JSON migration instead of claiming automatic container/keychain migration.
- Keep API, models, persistence, context, tools/search and UI separate. Use URLSessionDataDelegate for streaming; preserve split UTF-8 and throttle UI updates.
- Store credentials only in Keychain. No telemetry, embedded secrets, TLS bypasses, or credential logging. External data is untrusted. Tools are allowlisted and have bounded execution/cancellation; no shell, arbitrary code, files or private data tools.
- Preserve backward decoding of V1 archives; never delete raw history when trimming or compressing request context. Summary replacement must be transactional and reversible.
- No third-party runtime dependencies without explicit iOS 14 and license review. No Chatbox GPL implementation/assets.
- Run `python ios/scripts/generate_project.py`, `python ios/scripts/check_compatibility.py`, and `git diff --check` for each phase. Validate on actual GitHub macOS CI, inspect failure logs, fix root causes. Do not claim Windows checks are an Xcode build.
- IPA must originate from successful Release iphoneos arm64 compilation, `CODE_SIGNING_ALLOWED=NO`, with verified executable, frameworks, Info.plist, minimum OS and Payload structure. Simulator tests are additional verification.
- Actual iOS 14.8 device/API-key verification remains manual until performed. Keep README and test matrix accurate; no inert controls advertising missing features.
- Use real commits on the default branch. Future authorized commits use AkiSenn's verified ID-based noreply identity and exactly one `Co-authored-by: Codex <noreply@openai.com>` trailer. Do not rewrite old history or guarantee GitHub contributor association.
