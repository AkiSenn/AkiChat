# AkiChat

ԭ�� iOS 14+ ��ģ�� AI �ͻ��ˣ���Ҫ���� **iPhone XR / iOS 14.8 / A12**��Swift 5��SwiftUI/UIKit��URLSessionDataDelegate��Core Data SQLite��Keychain������ת��ˡ��޵�¼����ң�⡢�޵����� Swift ����ʱ������

**Created by AkiSenn**<br>
**Built with OpenAI Codex**

Copyright (c) 2026 AkiSenn �� [MIT](LICENSE) �� [AUTHORS](AUTHORS.md) �� [������˵��](THIRD_PARTY_NOTICES.md)

## ������ TrollStore ��װ

�ȶ��汾�� [GitHub Releases](https://github.com/AkiSenn/AkiChat/releases)�����й������� [Build iOS 14 IPA](https://github.com/AkiSenn/AkiChat/actions/workflows/build-ios.yml) �� **Run workflow** �� �ȴ���ɫ��� �� ���� **AkiChat-iOS14** Artifact ZIP ����ѹ��

- `AkiChat-iOS14-unsigned.ipa`��ʵ�� Release arm64 �����ǩ��������
- `AkiChat-iOS14-adhoc.ipa`��ͬһ�����ı��� ad-hoc ���ð�������Ҫ������֤�顣
- `SHA256SUMS.txt`��У��ͣ�����Ŀ¼��ִ�� `shasum -a 256 -c SHA256SUMS.txt`��
- `launch.png`��ʵ��ģ����������ͼ��

�� IPA ���� iPhone���ļ���App���������Ѱ�װ�� TrollStore ����װ����� Artifact ZIP ���� IPA��

���ֲ���������֣�**��ǩ������**ʹ�� CODE_SIGNING_ALLOWED=NO��**���� ad-hoc**���ð�ʹ�� `codesign --sign -`�����Ǹ���֤�������ǩ����**TrollStore ��װ����**�ᰴ��װ��������ǩ/ע�ᡣ���ܳ�ŵ�� unsigned IPA ������װ�����������С�

�ȳ��� unsigned������ǰ TrollStore/ldid �ܾ�δǩ�� Mach-O��ʹ���渽 adhoc IPA������� TrollStore �ٷ� ldid �Ƿ��Ѱ�װ/���¡���Ҫʱ���� Mac ��ѹ unsigned IPA��ִ�� `ldid -S Payload/AkiChat.app/AkiChat`���� `zip -r AkiChat-iOS14-fakesigned.ipa Payload`��ldid Ӧ�ӹٷ�������Դ��ã�����������˽�� entitlement��

�ٷ����ݣ�[TrollStore](https://github.com/opa334/TrollStore)������Ŀ����ҪԽ��ע�롢root helper��Apple ����֤��� Provisioning Profile��

### �汾�����ڰ�װ��������Ǩ��

��ǰ�汾Ϊ **1.2.0��build 8��**���������� AkiChat v1 �ĳ�����������ǰ�� V2/2.x �����ǰ汾�滮��⣬�������ؽ���һ��Ӧ�ã��������� 1.x.x ��š�

��ǰ Bundle ID ���� **com.akisenn.akichat**���������ڰ�װ��ʹ�� `app.akichat.ios` ʱ��������ʶ�Ŷ�Ӧ�����������ȴ����ڰ��������� JSON�����ڵ�ǰӦ�ûỰ�����е��룬��������д API Key����ʵ�� Bundle ID �ж�Ǩ�����󣬶����ǰ� v1/v2 ���ƣ�û�п������Զ�Ǩ�ơ���ͬ Bundle ID ����ʷ�����á���Կ���ü��ڲ����ݸ�ʽ��ű��ֲ��䡣��ɱ���ǰ��Ҫɾ�����ڰ�װ����

## ����������ģ���л�ά��

��ʾ�汾Ϊ 1.2.0��������8��������������ʾ���������ƣ���������ʾ��ǰ��ʵģ�� ID�����ֱ�Ӱ������̷���ѡ��ģ�͡���չʾ���ػ��棬ˢ�����û����������������ñ�����Կ��Զ����֡�DeepSeek Ĭ�� ID ��Ϊ deepseek-flash������ģ���� /models ���غ��ֶ�����Ϊ׼��

��ʽ���¼��е���ǰ��Ϣ���ݸ�������²��������棻��ʷ Markdown ���桢��̨������ԭ���ı���������ͺ�̨ͼƬ����ͼ���ٸ�Ƶ��������� [�����������֤�߽�](docs/PERFORMANCE_REVIEW.md)��û�������Ѳ�� iOS 16 ��� FPS ���Ż��ٷֱȡ�

## WorkBuddy2API Hub �����޸�

�����Ӷ��� WorkBuddy Provider���������ص�ַ�͹���������ɵ� Key ���Զ���ȡģ�͡�����ģ����尴�����̷��飬֧���������ղ����������л���Hub ������λ��Ŀ¼���䣬��������ԭʼģ�� ID�����ž����� HTTP �������������ķ��տ��ء�

��ϸ���á�����/����/�����߽硢429 �˱���������ݼ� [����̳�](docs/WORKBUDDY_HUB.md) �� [PR #1 ����¼](docs/WORKBUDDY_REVIEW.md)��Hub Responses ����δ���룻��ǰ�ͻ�������ʹ�õ����Ĺٷ� DeepSeek Key����ͨ Hub ���첻Ҫ������

## ��ʼʹ��

1. �հ�����ҳ��������� API����ֱ�ӽ��� API �����̹�����Ҳ�ɴӻỰ���롰Ӧ�����á� �� ��ģ���� API Key�����롣
2. �� DeepSeek����д�Լ�����Կ�����Բ����档��������Կ���Զ����� GET /models��
3. ����ģ��ѡ���� �� ģ�Ϳ⣬ˢ�¡�������ѡ�� `deepseek-flash`���ӿڲ�����ʱ���ֶ�����ģ�� ID��
4. ������Ϣ���������˼����˼����ش���룬֧���۵������ơ��༭�ط����������ɺ�ֹͣ��
5. ͼƬ��ť��ѡ����� 4 ��ͼƬ���������Ҳఴť�򿪡��Ự����̨��������ͼƬ�������ġ���ʾ�ʡ�������������
6. ������ժҪǰ�����Ķ������á�ͬ���ⲿ���������ժҪ���󡱡����ߡ��������Զ�ѹ��Ĭ�Ϲرա�
7. ������ť�л��ر�/�Զ�/ÿ��ǿ�ƣ���Դ�б��� Markdown ���ӿɴ�ԭ�ġ�
8. ���Ự���Զ����ֶ�ѹ�����鿴��ָ�ժҪ�汾��Ԥ��ü���ѹ������ɾ��ԭʼ��ʷ��

## ����

| ģ�� | ��Ϊ |
|---|---|
| ԭ�� UI | ���Ự���롢ģ��ѡ�������Զ��������롢����/��ȫ����ë��������Ƭ��ǳɫ/��ɫ/ϵͳ����̬���������ϰ���ǩ |
| Provider | DeepSeek��OpenAI Ԥ�衢�Զ�����ݽӿڣ�Chat/Models ·����Header����ʱ��������Ԥ������ |
| ģ�Ϳ� | �Զ�/�ֶ�ˢ�¡�������ͬ��ʱ�䡢�������ղء������ֶ�����/ɾ����Ԫ����������/�������� |
| ���� | ��ʽ/����ʽ��UTF-8/SSE ��Ƭ��reasoning_content��tool_calls ������finish_reason��usage����ʱ/ȡ��/����/���� |
| ͼƬ | PHPicker ��ͼ��Ԥ��/�Ƴ���512/1024/2048 ��ߡ�JPEG ����������ʱ��ͼ��data URL����ʽ/��С���� |
| ���� | ���� Function Calling����������ҳ��ȡ������ʱ�䡢��ȫ���㣬������������У�顢����ָ���ѭ�����ƺ��۵���־ |
| ���� | �ٷ� DeepSeek Search/Fetch���Զ�/ǿ��ģʽ��Ĭ�� 5 ����1�C10 �ɵ�������ʵ��Դ��״̬/ʧ��/������ʾ |
| ������ | ÿ�Ự��Ԥ��/���Ԥ�����Զ�/ȫ��/��������/ժҪ+���ڡ������ִ��빤������Token ���㼰ʵ�� usage У׼ |
| ѹ�� | 75% Ĭ����ֵ��50%�C90%����������� 8 �������Ի����ṹ��ժҪ�����Ƿ�Χ������ժҪģ�͡��汾/�ع�/���� usage |
| ��ʾ�� | Ӧ�á�Provider��ģ�͡��Ự��Ԥ�贴��/�༭/����/ɾ��/��ͣ/���뵼������ģ��ѡ����Ч��ʾ��Ԥ�� |
| Prefix Beta | �������أ�DeepSeek /beta ����� assistant �� prefix:true�������빤�߻��� |
| ���� | SQLite ��ʷ������/������/ȷ��ɾ����JSON ���뵼����Markdown ����������/��Դ/usage/ժҪ�汾�־û���Keychain ����������Կ |
| Markdown | ��ʽ����Ⱦ�����⡢�б������á���б�塢���ڴ��롢�����/����/���ơ����ӡ��������� |

����ԭ�� Markdown ���������� CommonMark��JSON �Ǳ��汸�ݸ�ʽ��Markdown �Ǳ����Ķ��ĵ�����

## ���� API ���ȡģ�ͣ��׶� A��

1. ��ҳ��������� API��ֱ�Ӵ򿪡�API �����̡������������ API �����̡���
2. ֻ����д���������ơ�API Base URL��API Key����������沢��ȡģ�͡����߼�·����Э�顢Header����ʱ����������Ĭ���۵�����Ҫ������ģ�� ID ����ʾ���ơ�
3. ҳ���첽��ȡģ���б���ѡ��Ĭ��ģ�ͺ󷵻����죻Ҳ�����Ժ�ѡ�񡣻�ȡ�б����ᷢ����������Ҳ�������б��е�ÿ��ģ�Ͷ���ͨ��������֤��
4. ��֧���б���404/405��ʱ��ʾ������ģʽ�������ֶ�����ģ�� ID����ѡ��������֤��401����Ȩ�ޣ�403����������429������ʽ�����볬ʱ�ֱ���ʾ��ʧ�ܡ����б���ȡ������������ģ�ͣ��Զ����ֶ�ģ�͹��档
5. ��ҳ�����������̷���ѡ��ģ�ͣ�֧���������ղء�ˢ�ºͽ���ģ�͹�����ѡ���ı���һ������ĵ�ַ��ģ�� ID �� Keychain ��Կ��Դ�����лỰ�������ֶ���ѡ��

�½�ͨ�����õ�Ĭ��·��Ϊ `/v1/chat/completions` �� `/v1/models`��Base URL �� `/v1` ʱ�����ظ�ƴ�ӡ��������õ��Զ���·����Ĭ��ģ�͡�ID����Կ���á�ģ�͸��Ǻ��������ݼ�����ȡ��DeepSeek �ٷ�Ԥ��·�����ֲ��䡣��ȡģ�ͺ����û���ȷѡ��Ĭ��ֵ�����Զ��滻���лỰʹ�õ�ģ�͡�

�����ں����󼰷ֽ׶����ռ� [UI_UX_PLAN.md](docs/UI_UX_PLAN.md)��˼����������������Ѱ������ع�Ҫ���ͨ���� [FEATURE_PANEL_FIX.md](docs/FEATURE_PANEL_FIX.md)���������������š���ǰģ��ժҪ���Լ�����������Դ��Ϊ������Χ��

## API ��ģ������

| DeepSeek Ĭ���ֶ� | ֵ |
|---|---|
| Base URL | `https://api.deepseek.com` |
| Chat / Models | `/chat/completions` / `/models` |
| API model ID | `deepseek-flash` |
| Provider ��ʾ���� | DeepSeek |
| ����ǿ�� | high����ѡ low / high / max |

�汾���Ʋ��� API model ID�����ֽӿڷ������ƺ�����չʾ��������ơ�֧�ָ���ַ��/v1������ /v1/chat/completions ���ֶ��˵�·���������ظ�ƴ�ӡ�ֻ�������˺š���ѯ������ fragment �� HTTPS Base URL������ϵͳ TLS ��֤���ܾ��ض���

ģ�ͷ��ֶ�ȡ id��name��context_window��max_output_tokens��input/output_modalities��effort��api_capabilities��ͼƬ��˼��������Ԫ����ȱʧʱ����δ֪/���ã��ɺ�ʵ���ֶ����ǣ��ٷ� Flash Ԥ��ʹ�ù����ĵ��е�������ˢ��ʧ�ܡ����б���Զ��ȱʧ��Ŀ������ɾ���������á�����/�������ǡ���ʾ�ʡ��ղغ���������

�������м��ݽӿڶ�ʵ�� /models��404 ʱ�ֶ����Ӽ��ɡ�Header ֻ���ڷ�����Ԫ���ݣ����ܴ���֤��Cookie �� Key/Token/Secret���ٷ� OpenAI Ԥ���Զ�ѡ�� max_completion_tokens ��Ĭ�ϲ����Ϳ��ܱ�����ģ�;ܾ��Ĳ���������ͨ�ü��ݽӿ�Ĭ�� max_tokens��������ɸ��ǡ��� DeepSeek ��������˽�� thinking ������

## ˼��������������

�����������˼�����͡����������򿪶��� iOS 14 ������壬��ɫ�Կɵ����˼�����ء�ǿ��ֻ��˼�����ά��������ģʽ����Դ����Ȩֻ���������ά�������ٽ���Ự����̨Ѱ����ͨ�������á�����ֱ�ӱ��浽�Ự���ر���岻�ı俪�أ������ڼ�ɲ鿴�����ؼ�ֻ����

DeepSeek ����ʹ�� `{"thinking":{"type":"enabled"}}` �� disabled����ʽѡ��λʱ�� reasoning_effort����Ĭ�ϡ��ɲ�����˼��ģʽ������ Temperature���������ظ���Ч������Flash ˼�� Top P ��� 0.95����˼�� Flash ��������Ч Top P��

��ͨ���ֲ��ش���ʷ reasoning_content��Я�� tools ʱ��������ԭʼ assistant �� reasoning_content��tool_calls ��ƥ��� tool_call_id������û�е��ù��ߵ� assistant �ش������İ������ִκ������������������������¹��� tool ��Ϣ��ժҪ���Ǿ��ִκ���ժҪ���������ԭʼ�ִΣ����������ֶ�������������

����Ĭ����� 4 �֡������� 8 �֣�ÿ����� 4 �����á������ּ���ʹ�ö����������������������ִ�л� NSExpression��δ��Ȩ���߻�Ƿ��������ش���û���նˡ�������롢�ļ�ɾ����˽�����ݷ��ʡ���ǰ����û������д������δ�����й��߱���������ȷȷ�ϡ�

�����̶����ùٷ� `POST /v1/tools/search` �� `POST /v1/tools/fetch`�������û�ѡ���Ĺٷ� DeepSeek ��Կ���Զ�ģʽ����ʵ Function Calling ��������֧�ֹ��ߵ���ʱ��ȷ�����ã�ÿ���������޹���ģ�Ͳ��ÿͻ���Ԥ����������ʵ�������ⲿ�ο�ֻ���뱾�����󸱱���������ʷԭ�ģ�Ҳ��αװ��ģ�͹��ߵ��á������������߼�����/���㹤�ߵĿ��ء�������Կ������ģ�Ͷ�����֧�� WorkBuddy �������ٷ� DeepSeek ������SearXNG �� Brave ����δ���룬��չʾΪ������Դ��ʧ�ܻ��¼���󣬲�����ʾ���鹹��������ҳ/�����������н粻�������ϣ���������Ȩ�޻��ȡ��Կ����ҳ��ȡ�������豸�������硣

## �����ġ�ѹ������ʾ��

Ԥ����������������������ģ��Ԫ����/�ֶ�����ȡ������Token ��ʾ�ǹ��㣨ͼƬҲ���룩������ʵ�� prompt usage ʱУ׼�����Ǿ�ȷ tokenizer ���˵����Զ����Ա���Ԥ������������ִΣ�ȫ��������ȷ���������ڱ������ N �ּӵ�ǰ���⣻ժҪ����ʹ�û�汾��δ����ԭʼ�ִΡ�

�Զ�ѹ���ﵽ��ֵ���г������������ľ���ʷ������ժҪ����ָ������ Provider/ģ�ͣ�����ʷ��ժҪģ��Ԥ�㴦���������ִΣ���������������δժҪ�Ĳ��֡����渲����Ϣ ID��ʱ�䡢ģ�ͼ����� usage����ʽ��������ʧ�ܻ�ȡ�����滻�ɰ汾��System Prompt ����ѹ�����ǣ��༭����Ϣ��ͣ�ÿ��ܹ�ʱ�ĻժҪ���汾��ʷ�Ա�����

�ر��Զ�ѹ���е����ڣ�����ʽ��ѡժҪ���ԡ������ʾ�ʰ�Ӧ�á�Provider��ģ�͡��Ự˳��ϲ����󼶸������������ȣ�ÿ���������¼��㣬�ر�Ԥ��������������һ������Prefix �Ƕ����� assistant ���ǰ׺������ System Prompt ���á�

## ��˽

API Key ֻ�� Keychain��ThisDeviceOnly���������� UserDefaults��SQLite��������Ӧ����־����ʱ URLSession �޳־� Cookie/���棬���ƹ�֤��У�顣��ͨ���췢���û�ѡ���ģ�ͷ����̣����������߷�������

��������ѯ/URL ������ DeepSeek������ժҪ����ʷ������ǰ�����ģ�ͣ����ܲ������ã��������������ͬ�⣬ժҪ�ڿ���̨����ͬ�⡣�ɰ湲����Ȩ���ּ��ݶ�ȡ����ȷ�ܾ������󲻱�ժҪ�������´򿪡�������˽�����졢˼����ͼƬ��������ѡ��Ŀ�ĵء�����ֻ������������������Կ�������ǾɻỰ����� 80 MiB ���ơ��汾/�ظ� ID��ʵ��ͼƬ��ʽ/�ߴ硢��Ϣ/���߲��������������á����ݿ��޷�����ʱ��ͣд�룬����ԭ�ļ���

## �����빹��

```text
ios/AkiChat.xcodeproj/       ���������빲�� Scheme
ios/AkiChat/Models/          Codable��Provider��ģ�Ϳ⡢���ߡ���Դ��ժҪ��Ԥ��
ios/AkiChat/API/             �������䡢SSE��delegate��ģ�ͷ��֡�JSON HTTP
ios/AkiChat/Services/        AppStore��ChatRun��ContextManager��SummaryService������/������ͼƬ
ios/AkiChat/Storage/         Core Data SQLite��Keychain
ios/AkiChat/UI/              ���졢���롢ģ�Ϳ⡢����̨��Ԥ�衢ԭ�� Markdown/UIKit
ios/AkiChatTests/            Mock URLProtocol���ű������ֲ��ԡ�XCTest
ios/scripts/                �������ɡ������ԡ�ʵ�� App/Framework/IPA У��
.github/workflows/          ���������ԡ�Artifact��Tag Release
docs/                       ������վ��󡢺��� TODO
```

Xcode 16.4 �򿪹��̣�Swift 5��Deployment Target �̶� 14.0��Bundle ID �̶� com.akisenn.akichat��ʹ�� NavigationView��PHPicker��UITextView��UIVisualEffectView����ʹ�� NavigationStack��SwiftData��PhotosPicker��URLSession.bytes �� SwiftUI ԭ�� Markdown���޵����� Markdown ����

```sh
python3 ios/scripts/generate_project.py
python3 ios/scripts/check_compatibility.py
xcodebuild -project ios/AkiChat.xcodeproj -scheme AkiChat \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build/device ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
  IPHONEOS_DEPLOYMENT_TARGET=14.0 CODE_SIGNING_ALLOWED=NO build
python3 ios/scripts/package_ipa.py \
  build/device/Build/Products/Release-iphoneos/AkiChat.app \
  build/AkiChat-iOS14-unsigned.ipa
```

Windows �ɱ༭�� Python �Լ죬�������� Xcode������ Swift �ļ����������ɲ��ύ���̡�ͼ�����ύ������������Ҫ�������� Pillow��

������֧�� push��workflow_dispatch��Tag push ���ѷ��� Release��ʹ�� GitHub macos-15���̶� Xcode 16.4 ��ƥ�� iOS 18.5 ģ����������� arm64 Release ��ǩ�����룬�ټ�� App��Ƕ�� Mach-O/Framework �� arm64/iPhoneOS/���ϵͳ��������� IPA��ִ�� Mock �������ͼ������ϴ���ģ���������������ñ��� ad-hoc ǩ������С��ͨ Keychain entitlement�������ǩ����������ȱ�ٷ������ -34018��CI ����ǰ׺���� Apple �Ŷӻ��˺ţ�Ҳ��������� Release��ֻ��ȫ��ͨ���󷢲� tag Release��ʧ����־�� xcresult �� AkiChat-build-diagnostics��

������������ִ��Ȩ�ޡ�Bundle ID��Info.plist��MinimumOSVersion ��ȷ 14.0��Assets.car���� provisioning��unsigned ȷ��ǩ����ZIP CRC �� Payload/AkiChat.app��������ģ���������ļ���� IPA��������ǩ���� `v1.2.0` ������ 1.x.x ��ţ����Ͱ汾��ǩ����Ȩ���������ͨ���󷢲�������ʵ IPA �� Release��������ִ��״̬�� [Actions](https://github.com/AkiSenn/AkiChat/actions)��

## �������Ų�

Mock ���Ը�������/·����ģ���б��� HTTP ����������SSE ÿ�ֽڷ�Ƭ��reasoning/tool_calls��Function Calling ���֡�Search/Fetch��Ȩ�ޡ����㡢Ԥ��/��ֵ/��������ժҪʧ��/�ع�����ʾ�ʡ�Prefix��ͼƬ��SQLite��Keychain�������� iOS 14 Ԫ���ݡ�Դ�뾲̬����� SDK availability �����鹲ͬʹ�á�

**δ�������û� iPhone XR / iOS 14.8 ��װ��ʹ����ʵ API Key ���ճɹ���** ����ģ�������ܴ����������ִ����� [DEVICE_TEST_MATRIX.md](docs/DEVICE_TEST_MATRIX.md)��

| ���� | �Ų� |
|---|---|
| /models 404/���б� | ����������ֶ����ӣ��ӿڲ�һ��ʵ�ַ��� |
| ͼƬ/���߰�ť���� | ����δ������ȷ���ĵ�����ģ�Ϳ⸲�� |
| 401/403 | ��Ӧ Provider ��Կ��Ȩ�� |
| 402/429 | ��Ƶ�ʡ��������� |
| 400/422 | �˶�ģ�� ID��·��������������ֶΣ�����ģ�Ϳɹرղ������� |
| ���������� | ��鹤���ܿ��ء�ģʽ��ģ���������ⲿ����ͬ�⼰�ٷ� DeepSeek ��Կ |
| �����Ĳ��� | ����Ԥ��/����/ժҪ���ԣ�ԭʼ��¼���� |
| ժҪʧ�� | �ɰ汾���������Ի�ժҪģ�� |
| Keychain ���� | ȷ�� TrollStore ע�ᡢ�̶� Bundle ID��ldid ����������Ϊ������Կ |
| ��ֹ̨ͣ | ����ȡ�������棬���� iOS 14 ��̨�����γɲ�ȱ���� |
| CI �Ŷӻ�ʧ�� | �ȴ� macOS ���У���ȡ��ʵ��־�޸�������߲���Ŀ�����Դ��� |

## ��Դ�������Χ

����ԭ��ʵ�֣�ֻ�ο� [Chatbox](https://github.com/chatboxai/chatbox) ͨ�ù�������������� GPL ʵ�֡��̱���ʲ�����ʵ�ύ��¼�����������ף���ͬ����βע��ѭ�Ѻ˶ԵĹٷ�ʵ�֣������ AUTHORS��GitHub Contributors չʾ������֤��

Bing HTML ʵ��������Tavily/BoCha��MCP�����ӹ�ʽ��ͼƬ���ɡ���������Ϳ�Ự�˵�ͳ��δʵ�֣�û�������ڣ���չ�ӿ���߽�� [TODO](docs/TODO.md)���������������� Bing ��ҳ������

Э��˶ԣ�2026-10-23����[DeepSeek Chat](https://api-docs.deepseek.com/api/create-chat-completion/)��[Models](https://api-docs.deepseek.com/api/list-models/)��[Thinking/tools](https://api-docs.deepseek.com/guides/thinking_mode/)��[Search/Fetch](https://api-docs.deepseek.com/guides/search/)��[Vision](https://api-docs.deepseek.com/guides/vision/)��[Prefix Beta](https://api-docs.deepseek.com/guides/chat_prefix_completion/)��[OpenAI Chat](https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create)��
