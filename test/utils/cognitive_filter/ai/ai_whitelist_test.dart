import 'package:PiliPlus/models/cognitive_filter/filter_rule.dart';
import 'package:PiliPlus/models/cognitive_filter/filter_surface.dart';
import 'package:PiliPlus/models/cognitive_filter/rule_scope.dart';
import 'package:PiliPlus/models/cognitive_filter/rule_type.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/ai_whitelist_core.dart';
import 'package:flutter_test/flutter_test.dart';

FilterRule _rule({
  String id = 'r',
  RuleType type = RuleType.keyword,
  String content = '',
  Set<RuleScope> scopes = const {RuleScope.reply},
  bool enabled = true,
}) => FilterRule(
  id: id,
  type: type,
  content: content,
  scopes: scopes,
  enabled: enabled,
);

void main() {
  group('AiWhitelistMatcher', () {
    test('关键词大小写不敏感，且只在该适用面生效', () {
      final matcher = AiWhitelistMatcher([
        _rule(content: 'Hello', scopes: const {RuleScope.reply}),
      ]);
      expect(
        matcher.matches(surface: FilterSurface.reply, text: 'say hello'),
        isTrue,
      );
      expect(
        matcher.matches(surface: FilterSurface.reply, text: 'HELLO'),
        isTrue,
      );
      expect(
        matcher.matches(surface: FilterSurface.danmaku, text: 'say hello'),
        isFalse,
      );
      expect(
        matcher.matches(surface: FilterSurface.reply, text: 'helo'),
        isFalse,
      );
    });

    test('正则大小写不敏感', () {
      final matcher = AiWhitelistMatcher([
        _rule(
          type: RuleType.regex,
          content: r'^abc\d+$',
          scopes: const {RuleScope.dynamic},
        ),
      ]);
      expect(
        matcher.matches(surface: FilterSurface.dynamic, text: 'ABC9'),
        isTrue,
      );
      expect(
        matcher.matches(surface: FilterSurface.dynamic, text: 'xabc1'),
        isFalse,
      );
    });

    test('用户规则按 UID 匹配，并尊重范围', () {
      final matcher = AiWhitelistMatcher([
        _rule(
          type: RuleType.user,
          content: '123',
          scopes: const {RuleScope.video},
        ),
      ]);
      expect(
        matcher.matches(surface: FilterSurface.video, text: '', mid: 123),
        isTrue,
      );
      expect(
        matcher.matches(surface: FilterSurface.video, text: '', mid: 456),
        isFalse,
      );
      expect(
        matcher.matches(surface: FilterSurface.reply, text: '', mid: 123),
        isFalse,
      );
    });

    test('弹幕用户规则可以用 UID 派生的哈希命中', () {
      final mid = 123456;
      final matcher = AiWhitelistMatcher([
        _rule(
          type: RuleType.user,
          content: '$mid',
          scopes: const {RuleScope.danmaku},
        ),
      ]);
      final hash = FilterRule.midToHash(mid);
      expect(
        matcher.matches(
          surface: FilterSurface.danmaku,
          text: '',
          midHash: hash,
        ),
        isTrue,
      );
      expect(
        matcher.matches(
          surface: FilterSurface.danmaku,
          text: '',
          midHash: hash.toUpperCase(),
        ),
        isTrue,
      );
      expect(
        matcher.matches(
          surface: FilterSurface.danmaku,
          text: '',
          midHash: FilterRule.midToHash(mid + 1),
        ),
        isFalse,
      );
    });

    test('停用规则不参与匹配', () {
      final matcher = AiWhitelistMatcher([
        _rule(content: '广告', enabled: false),
        _rule(
          id: 'u',
          type: RuleType.user,
          content: '123',
          scopes: const {RuleScope.danmaku},
          enabled: false,
        ),
      ]);
      expect(
        matcher.matches(surface: FilterSurface.reply, text: '这是广告'),
        isFalse,
      );
      expect(
        matcher.matches(surface: FilterSurface.danmaku, text: '', mid: 123),
        isFalse,
      );
    });

    test('坏正则静默跳过，其他规则仍生效', () {
      final matcher = AiWhitelistMatcher([
        _rule(type: RuleType.regex, content: '('),
        _rule(id: 'k', content: '广告'),
      ]);
      expect(
        matcher.matches(surface: FilterSurface.reply, text: '这是广告'),
        isTrue,
      );
      expect(
        matcher.matches(surface: FilterSurface.reply, text: '无关内容'),
        isFalse,
      );
    });

    test('空文字与空规则不匹配', () {
      final matcher = AiWhitelistMatcher(const <FilterRule>[]);
      expect(
        matcher.matches(surface: FilterSurface.reply, text: '任意文字'),
        isFalse,
      );
      expect(
        matcher.matches(surface: FilterSurface.reply, text: ''),
        isFalse,
      );
    });
  });

  group('存储', () {
    test('新存储的坏数据当空，越界范围与哈希规则被丢弃', () {
      expect(whitelistRulesFromJson('bad'), isEmpty);
      expect(whitelistRulesFromJson(null), isEmpty);
      expect(
        whitelistRulesFromJson([
          {'id': 'a', 'type': 'keyword', 'content': 'ok'},
          {'id': 'b', 'type': 'keyword', 'content': ''},
          {
            'id': 'c',
            'type': 'keyword',
            'content': 'zone',
            'scopes': ['zone'],
          },
          {
            'id': 'd',
            'type': 'user',
            'content': '',
            'midHash': 'abc',
            'scopes': ['danmaku'],
          },
          {'id': 'e', 'type': 'unknown', 'content': 'x'},
        ]).map((rule) => rule.id),
        ['a'],
      );
    });

    test('关键词规则支持范围与去重合并', () {
      var stored = <FilterRule>[];
      final store = AiWhitelistStore(
        read: () => stored,
        write: (rules) => stored = rules,
      );

      expect(
        store.addKeywordFromText(' Hello ', surface: FilterSurface.reply),
        isTrue,
      );
      expect(store.rules.single.content, 'Hello');
      expect(store.rules.single.scopes, const {RuleScope.reply});

      expect(
        store.addKeywordFromText('Hello', surface: FilterSurface.dynamic),
        isTrue,
      );
      expect(store.rules.length, 1);
      expect(store.rules.single.scopes, const {
        RuleScope.reply,
        RuleScope.dynamic,
      });

      expect(store.addKeywordFromText('Hello'), isTrue);
      expect(store.rules.single.scopes, aiWhitelistScopes);
      expect(store.addKeywordFromText('   '), isFalse);
    });

    test('按 id 启停与删除', () {
      var stored = <FilterRule>[];
      final store = AiWhitelistStore(
        read: () => stored,
        write: (rules) => stored = rules,
      );
      store.add(_rule(id: 'a', content: '广告'));
      expect(store.setEnabled('a', false), isTrue);
      expect(store.rules.single.enabled, isFalse);
      expect(store.setEnabled('a', false), isFalse);
      expect(store.remove('a'), isTrue);
      expect(store.rules, isEmpty);
      expect(() => store.remove('a'), throwsArgumentError);
    });

    test('按 id 更新内容与启停状态', () {
      var stored = <FilterRule>[];
      final store = AiWhitelistStore(
        read: () => stored,
        write: (rules) => stored = rules,
      );
      store.add(_rule(id: 'a', content: '旧'));
      expect(
        store.update(_rule(id: 'a', content: '新', enabled: false)),
        isTrue,
      );
      expect(store.rules.single.content, '新');
      expect(store.rules.single.enabled, isFalse);
      expect(
        store.update(_rule(id: 'a', content: '新', enabled: false)),
        isFalse,
      );
    });

    test('校验空内容、坏正则、越界范围与非 UID 用户规则', () {
      final store = AiWhitelistStore(read: () => [], write: (_) {});
      expect(() => store.add(_rule(content: '')), throwsArgumentError);
      expect(
        () => store.add(_rule(type: RuleType.regex, content: '(')),
        throwsArgumentError,
      );
      expect(
        () => store.add(
          _rule(content: 'x', scopes: const {RuleScope.whisper}),
        ),
        throwsArgumentError,
      );
      expect(
        () => store.add(_rule(type: RuleType.user, content: 'abc')),
        throwsArgumentError,
      );
    });
  });
}
