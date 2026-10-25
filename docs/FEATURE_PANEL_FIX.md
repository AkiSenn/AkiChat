# ���˼���������������ع��޸�

## ԭ�����¼���

��ǰ�׶� A ֻ���� API �������̣��׶� B �����δʵ�֡�ChatComposer ����ֱ�� toggle��WorkBuddy ������̨��ѭ������ģʽ�ľ��¼���ChatView �޶���·�ɣ�����̨��ȫ�������ְ���ͬ״̬����������ظ���Ԥ���ѽڡ�

���� ChatComposer ע�� onThinking/onSearch���� ChatView ������̺������� thinking/search Sheet�����߾�Ϊ iOS 14 NavigationView + ScrollView���йرպ���ɰ�ť����ʹ��ϵͳ�°� detents����Ƕ����ͨ���� Sheet��

ReasoningControls ֻ�� ThinkingPanel ���á���״̬���Ե�ǰ Conversation��ͨ�� AppStore ���²��� RequestBuilder ʹ�ã������ڼ�ֻ����������λ���ȣ�δ֪��Ĭ�ϣ��̶�/���ɹر���ȷ˵�����л�ģ�Ͳ����˼��ƫ�ã�����ͨ�ýӿڷ��� DeepSeek ˽�� thinking��

SearchPanel ����ά���ر�/�Զ�/ÿ�Ρ���Դ��������Ȩ�����ü��� Provider + Keychain ���ã�����������Դд�����ƾ�����ã����л����� Provider/Model��δ����Ҳ���Դ���塣����ʹ��������Դ�ĺϷ�ƾ�ݣ�����ʹ������ģ���Լ���ƾ�ݡ�

## ��ʵ���������ݱ���

- DeepSeek �� thinking �� reasoning_effort ��[�ٷ�˼��Э��](https://api-docs.deepseek.com/guides/thinking_mode/)���ͣ�ģ��Ŀ¼���������� reasoning_efforts��Ĭ�ϡ��̶����ɹرպ� always_reasoning��Hub ������ HubReasoning ���䣻ͨ�ýӿڽ�����ȷԪ�������ñ�׼ effort����ʹ��˽��Э�顣
- ����[�ٷ� Search/Fetch](https://api-docs.deepseek.com/api/search/)��·����ʵ�ֻ�������δ����� SearXNG/Brave��
- �Զ�ģʽ��֧����ʵ���ߵ��õ�ģ�ͣ��������߰�������߼�����/���㿪�طֿ���������߼����߹رն���ʾ��������
- ÿ������������ģ�ͱ����н繤�������޹���ģ����ͨ�� SearchProviderService �������ɹ����н硢����ʵ URL�����Ϊ�����ŵ� JSON �ο��������󸱱���������������Ԥ�㡣������Ϣ����ԭʼ�û���������ʵ��Դ����α�� assistant ���ߵ��á�����Դ�������ȡ����������ģ�ͷ�������
- UI ��ͨ����/˼������ֻ���������ڡ�����̨����ժҪ����������Ȩ���߼����ߡ������ġ���ʾ�ʡ�ͼƬ�� Prefix������ Prefix ͨ��ͳһ�����ر����������ڿ���̨�ṩ�ڶ���������������
- ������ reasoning Ԫ���ݼ� searchConsent ��Ϊ optional���ɹ��� externalConsent ֻ��Ϊ���޶�������ѡ��ʱ�ļ���Ĭ�ϣ���ȷ�ܾ��������ᱻժҪ��Ȩ���¿������������ݿ������ʷ��ʽ��Keychain ������ԭ�Ļ�ժҪ�汾��
- ������汾 1.2.0/build8��Bundle ID com.akisenn.akichat��iOS 14.0 ���Ҫ�󡣰��ֿ⽻��Ӳ����ֱ��ʹ�� GitHub App �ύĬ�Ϸ�֧������ Actions�������� PR��tag ����ʽ Release��

## ��֤��Χ

���� FeaturePanelTests ��֤Э�������δ֪/ǿ��˼����״̬�����Ȩ���ݡ��޹���Ԥ��������ʵ�Զ������������ر���������ʧ��/ȡ��������/������Կ���롣UI ����ִ����ʵ��ť�����������̡�����/��λ����ɫ�ؿ���ǿ����δ֪ģ�͡�����������塢��Ȩ������ģʽ������ͼ��DEBUG ����ƾ��Ϊ Mock �Ҳ����� Release��

�����Խű����� composer ״̬�޸�/������̨��Ϊ���ظ���ڲ��ܻع飻�������ɡ�iOS 14 ���Ͳ����鱾��ִ�У�Xcode ������ UI XCTest ����ʵ macOS Actions ���Ϊ׼��iOS 14.8/16��TrollStore����ʵ Key/ģ��/�������񡢼�������ɫ���������˹�ʵ����֤���� DEVICE_TEST_MATRIX.md��
