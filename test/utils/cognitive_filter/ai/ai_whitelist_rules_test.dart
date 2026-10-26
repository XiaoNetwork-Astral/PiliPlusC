import 'dart:convert';

import 'package:PiliPlus/utils/cognitive_filter/ai/ai_whitelist_rules.dart';
import 'package:flutter_test/flutter_test.dart';

AiWhitelistEntry _entry(
  String content, {
  String? id,
  AiWhitelistType type = AiWhitelistType.keyword,
  bool enabled = true,
}) {
  return AiWhitelistEntry(
    id: id ?? content,
    type: type,
    content: content,
    enabled: enabled,
  );
}

void main() {
  group('AiWhitelistMatcher', () {
    test('关键词大小写不敏感匹配原文子串', () {
      final matcher = AiWhitelistMatcher([_entry('Hello')]);
      expect(matcher.matches('say hello world'), isTrue);
      expect(matcher.matches('HELLO'), isTrue);
      expect(matcher.matches('helo'), isFalse);
    });

    test('关键词匹配原文，不做规范化', () {
      final matcher = AiWhitelistMatcher([_entry('前排')]);
      expect(matcher.matches('前排'), isTrue);
      expect(matcher.matches('前 排'), isFalse);
      expect(matcher.matches('！前排！'), isTrue);
    });

    test('正则大小写不敏感', () {
      final matcher = AiWhitelistMatcher([
        _entry(r'^abc\d+$', type: AiWhitelistType.regex),
      ]);
      expect(matcher.matches('abc123'), isTrue);
      expect(matcher.matches('ABC9'), isTrue);
      expect(matcher.matches('xabc1'), isFalse);
    });

    test('停用条目不参与匹配', () {
      final matcher = AiWhitelistMatcher([_entry('广告', enabled: false)]);
      expect(matcher.isEmpty, isTrue);
      expect(matcher.matches('这是广告'), isFalse);
    });

    test('坏正则静默跳过，其他条目仍生效', () {
      final matcher = AiWhitelistMatcher([
        _entry('(', type: AiWhitelistType.regex),
        _entry('广告'),
      ]);
      expect(matcher.matches('这是广告'), isTrue);
      expect(matcher.matches('无关内容'), isFalse);
    });

    test('空集合与空文字不匹配', () {
      final matcher = AiWhitelistMatcher(const <AiWhitelistEntry>[]);
      expect(matcher.matches('任意文字'), isFalse);
      expect(matcher.matches(''), isFalse);
    });
  });

  group('validateAiWhitelistContent', () {
    test('空内容与纯空白返回错误', () {
      expect(validateAiWhitelistContent(AiWhitelistType.keyword, ''), '内容不能为空');
      expect(
        validateAiWhitelistContent(AiWhitelistType.regex, '   '),
        '内容不能为空',
      );
    });

    test('正则不合法返回错误', () {
      final error = validateAiWhitelistContent(AiWhitelistType.regex, '(');
      expect(error, isNotNull);
      expect(error, contains('正则表达式无法编译'));
    });

    test('合法关键词与正则通过', () {
      expect(
        validateAiWhitelistContent(AiWhitelistType.keyword, '前排'),
        isNull,
      );
      expect(
        validateAiWhitelistContent(AiWhitelistType.regex, r'^abc\d+$'),
        isNull,
      );
    });
  });

  group('AiWhitelistEntry', () {
    test('JSON 往返保留全部字段', () {
      const entry = AiWhitelistEntry(
        id: 'a',
        type: AiWhitelistType.regex,
        content: r'^a+$',
        enabled: false,
      );
      final restored = AiWhitelistEntry.fromJson(
        jsonDecode(jsonEncode(entry.toJson())),
      );
      expect(restored, isNotNull);
      expect(restored!.id, 'a');
      expect(restored.type, AiWhitelistType.regex);
      expect(restored.content, r'^a+$');
      expect(restored.enabled, isFalse);
    });

    test('坏数据返回 null 不抛异常', () {
      expect(AiWhitelistEntry.fromJson(null), isNull);
      expect(AiWhitelistEntry.fromJson('x'), isNull);
      expect(AiWhitelistEntry.fromJson(const <String, dynamic>{}), isNull);
      expect(
        AiWhitelistEntry.fromJson({
          'id': 'a',
          'type': 'unknown',
          'content': 'x',
        }),
        isNull,
      );
      expect(
        AiWhitelistEntry.fromJson({
          'id': 1,
          'type': 'keyword',
          'content': 'x',
        }),
        isNull,
      );
      expect(
        AiWhitelistEntry.fromJson({'id': 'a', 'type': 'keyword'}),
        isNull,
      );
    });

    test('enabled 缺失或类型错误按启用恢复', () {
      final missing = AiWhitelistEntry.fromJson({
        'id': 'a',
        'type': 'keyword',
        'content': 'x',
      });
      expect(missing?.enabled, isTrue);
      final wrong = AiWhitelistEntry.fromJson({
        'id': 'a',
        'type': 'keyword',
        'content': 'x',
        'enabled': 'no',
      });
      expect(wrong?.enabled, isTrue);
    });

    test('listFromJson 跳过坏数据与重复 id', () {
      final list = AiWhitelistEntry.listFromJson([
        {'id': 'a', 'type': 'keyword', 'content': 'x'},
        {'id': 'a', 'type': 'keyword', 'content': 'y'},
        null,
        {'id': '', 'type': 'keyword', 'content': 'z'},
        {'id': 'b', 'type': 'regex', 'content': 'y'},
      ]);
      expect(list.length, 2);
      expect(list[0].id, 'a');
      expect(list[1].id, 'b');
    });
  });
}
