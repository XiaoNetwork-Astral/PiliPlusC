import 'package:PiliPlus/utils/cognitive_filter/ai/llm_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('接口地址拼接', () {
    test('Anthropic 根地址补 /v1/messages', () {
      expect(
        buildChatUrl('https://api.anthropic.com', LlmApiFormat.anthropic),
        'https://api.anthropic.com/v1/messages',
      );
      expect(
        buildChatUrl('https://api.anthropic.com/', LlmApiFormat.anthropic),
        'https://api.anthropic.com/v1/messages',
      );
    });

    test('Anthropic 地址已带 /v1 时只补 /messages', () {
      expect(
        buildChatUrl('https://api.anthropic.com/v1', LlmApiFormat.anthropic),
        'https://api.anthropic.com/v1/messages',
      );
      expect(
        buildChatUrl('https://api.anthropic.com/v1/', LlmApiFormat.anthropic),
        'https://api.anthropic.com/v1/messages',
      );
    });

    test('OpenAI 兼容地址补 /chat/completions', () {
      expect(
        buildChatUrl('https://api.deepseek.com', LlmApiFormat.openai),
        'https://api.deepseek.com/chat/completions',
      );
      expect(
        buildChatUrl('https://api.openai.com/v1/', LlmApiFormat.openai),
        'https://api.openai.com/v1/chat/completions',
      );
    });

    test('接口地址校验只接受 http 与 https', () {
      expect(isValidApiBaseUrl('https://api.anthropic.com'), isTrue);
      expect(isValidApiBaseUrl('http://127.0.0.1:8080/v1'), isTrue);
      expect(isValidApiBaseUrl('api.anthropic.com'), isFalse);
      expect(isValidApiBaseUrl('ftp://api.anthropic.com'), isFalse);
      expect(isValidApiBaseUrl(''), isFalse);
    });
  });

  group('提供商推断', () {
    test('判定接口按存储的地址推断', () {
      expect(
        judgeProviderForUrl('https://api.typesafe.ai/v1/systemone'),
        JudgeProvider.typesafe,
      );
      expect(
        judgeProviderForUrl(
          'https://ws123.cn-beijing.maas.aliyuncs.com'
          '/compatible-mode/v1/systemone',
        ),
        JudgeProvider.bailian,
      );
      expect(
        judgeProviderForUrl('https://api.example.com/v1/systemone'),
        JudgeProvider.custom,
      );
    });

    test('整理接口按存储的地址推断', () {
      const cases = <String, OrganizeProvider>{
        'https://api.deepseek.com': OrganizeProvider.deepseek,
        'https://api.deepseek.com/anthropic': OrganizeProvider.deepseek,
        'https://api.openai.com/v1': OrganizeProvider.openai,
        'https://api.anthropic.com': OrganizeProvider.anthropic,
        'https://api.anthropic.com/v1': OrganizeProvider.anthropic,
        'https://example.com/v1': OrganizeProvider.custom,
      };
      for (final entry in cases.entries) {
        expect(
          organizeProviderForUrl(entry.key),
          entry.value,
          reason: entry.key,
        );
      }
    });

    test('域名匹配不会把相似后缀当成预设', () {
      expect(
        organizeProviderForUrl('https://eviltypesafe.ai/v1'),
        OrganizeProvider.custom,
      );
      expect(
        organizeProviderForUrl('https://notdeepseek.com/v1'),
        OrganizeProvider.custom,
      );
    });

    test('预设自带地址、模型与格式，自定义没有预设', () {
      expect(OrganizeProvider.deepseek.baseUrl, 'https://api.deepseek.com');
      expect(OrganizeProvider.deepseek.model, 'deepseek-flash');
      expect(OrganizeProvider.deepseek.format, LlmApiFormat.openai);
      expect(OrganizeProvider.openai.baseUrl, 'https://api.openai.com/v1');
      expect(OrganizeProvider.openai.format, LlmApiFormat.openai);
      expect(OrganizeProvider.anthropic.format, LlmApiFormat.anthropic);
      expect(OrganizeProvider.custom.baseUrl, isNull);
      expect(OrganizeProvider.custom.model, isNull);
      expect(OrganizeProvider.custom.format, isNull);
      expect(JudgeProvider.typesafe.baseUrl, contains('typesafe.ai'));
      expect(JudgeProvider.typesafe.model, 'jev-latest');
      expect(JudgeProvider.bailian.model, 'decision-model-preview');
    });
  });

  group('阿里百炼', () {
    test('业务空间 ID 拼出北京地址并可以再取回来', () {
      final url = JudgeProvider.bailianBaseUrl(' 123456 ');
      expect(
        url,
        'https://123456.cn-beijing.maas.aliyuncs.com'
        '/compatible-mode/v1/systemone',
      );
      expect(JudgeProvider.bailianWorkspaceId(url), '123456');
      expect(
        JudgeProvider.bailianWorkspaceId(
          'https://api.typesafe.ai/v1/systemone',
        ),
        isNull,
      );
    });

    test('只有阿里百炼地址把单次题数限制到 16', () {
      expect(
        judgeQuestionLimitForUrl(
          'https://123456.cn-beijing.maas.aliyuncs.com'
          '/compatible-mode/v1/systemone',
        ),
        16,
      );
      expect(
        judgeQuestionLimitForUrl('https://api.typesafe.ai/v1/systemone'),
        isNull,
      );
      expect(
        isBailianJudgeHost(
          'https://123456.cn-beijing.maas.aliyuncs.com'
          '/compatible-mode/v1/systemone',
        ),
        isTrue,
      );
      expect(isBailianJudgeHost('https://api.deepseek.com'), isFalse);
    });
  });
}
