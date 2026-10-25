import 'package:PiliPlus/models/cognitive_filter/filter_rule.dart';
import 'package:PiliPlus/models/cognitive_filter/rule_migration.dart';
import 'package:PiliPlus/models/cognitive_filter/rule_scope.dart';
import 'package:PiliPlus/models/cognitive_filter/rule_set.dart';
import 'package:PiliPlus/models/cognitive_filter/rule_type.dart';
import 'package:flutter_test/flutter_test.dart';

List<(RuleType, String)> _segments(String pattern) => [
  for (final segment in splitLegacyPattern(pattern))
    (segment.type, segment.content),
];

FilterRule? _find(
  List<FilterRule> rules,
  RuleType type,
  String content, {
  String? midHash,
}) {
  for (final rule in rules) {
    if (rule.type == type &&
        rule.content == content &&
        (midHash == null || rule.midHash == midHash)) {
      return rule;
    }
  }
  return null;
}

void main() {
  group('splitLegacyPattern', () {
    test('普通竖线串拆成关键词', () {
      expect(_segments('甲|乙'), [
        (RuleType.keyword, '甲'),
        (RuleType.keyword, '乙'),
      ]);
    });

    test('括号与字符类里的竖线不拆', () {
      expect(_segments('(a|b)|c'), [
        (RuleType.regex, '(a|b)'),
        (RuleType.keyword, 'c'),
      ]);
      expect(_segments('[a|b]|c'), [
        (RuleType.regex, '[a|b]'),
        (RuleType.keyword, 'c'),
      ]);
      // 字符类里的括号只是字面字符，不影响顶层括号深度
      expect(_segments('[(]|c'), [
        (RuleType.regex, '[(]'),
        (RuleType.keyword, 'c'),
      ]);
    });

    test(r'\| 是被转义的字面竖线，不拆', () {
      expect(_segments(r'a\|b|c'), [
        (RuleType.keyword, 'a|b'),
        (RuleType.keyword, 'c'),
      ]);
      expect(_segments(r'\.'), [(RuleType.keyword, '.')]);
      expect(_segments(r'\[abc\]'), [(RuleType.keyword, '[abc]')]);
    });

    test('RegExp.escape 生成的转义串还原为关键词', () {
      final escaped = RegExp.escape('a.b(c)');
      expect(_segments('$escaped|普通'), [
        (RuleType.keyword, 'a.b(c)'),
        (RuleType.keyword, '普通'),
      ]);
      expect(_segments(RegExp.escape('a|b')), [(RuleType.keyword, 'a|b')]);
    });

    test('普通字符与正则混排时分别归类', () {
      expect(_segments(r'字面|a.*b|\d+'), [
        (RuleType.keyword, '字面'),
        (RuleType.regex, 'a.*b'),
        (RuleType.regex, r'\d+'),
      ]);
    });

    test('单段编译失败时放弃拆分，整串作为一条正则', () {
      expect(_segments('a|('), [(RuleType.regex, 'a|(')]);
      expect(_segments('a|[b'), [(RuleType.regex, 'a|[b')]);
      expect(_segments('('), [(RuleType.regex, '(')]);
    });

    test('空串、空段与重复段', () {
      expect(splitLegacyPattern(''), isEmpty);
      expect(splitLegacyPattern('   '), isEmpty);
      expect(splitLegacyPattern('||'), isEmpty);
      expect(_segments('重复|重复'), [(RuleType.keyword, '重复')]);
      expect(_segments('a|'), [(RuleType.keyword, 'a')]);
      expect(_segments('|a'), [(RuleType.keyword, 'a')]);
    });
  });

  group('migrateLegacy', () {
    const source = LegacyRuleSource(
      replyPattern: 'r1|r2',
      dynamicPattern: 'd1',
      videoPattern: 'v1',
      zonePattern: '动画|(电影)',
      danmakuKeywords: ['弹幕词'],
      danmakuRegexps: ['ab+c'],
      danmakuUidHashes: {'ABC123'},
    );

    test('旧键映射到正确类型与范围', () {
      final rules = migrateLegacy(source);
      expect(rules.length, 9);
      expect(rules.every((rule) => rule.enabled), isTrue);

      final r1 = _find(rules, RuleType.keyword, 'r1');
      expect(r1, isNotNull);
      expect(r1!.scopes, {RuleScope.reply});
      final r2 = _find(rules, RuleType.keyword, 'r2');
      expect(r2!.scopes, {RuleScope.reply});

      expect(
        _find(rules, RuleType.keyword, 'd1')!.scopes,
        {RuleScope.dynamic},
      );
      expect(
        _find(rules, RuleType.keyword, 'v1')!.scopes,
        {RuleScope.video},
      );

      final zone1 = _find(rules, RuleType.zone, '动画');
      expect(zone1, isNotNull);
      expect(zone1!.scopes, {RuleScope.video});
      final zone2 = _find(rules, RuleType.zone, '(电影)');
      expect(zone2, isNotNull);
      expect(zone2!.scopes, {RuleScope.video});

      expect(
        _find(rules, RuleType.keyword, '弹幕词')!.scopes,
        {RuleScope.danmaku},
      );
      expect(
        _find(rules, RuleType.regex, 'ab+c')!.scopes,
        {RuleScope.danmaku},
      );

      final user = _find(rules, RuleType.user, '', midHash: 'abc123');
      expect(user, isNotNull);
      expect(user!.content, isEmpty);
      expect(user.scopes, {RuleScope.danmaku});
      expect(user.isHashOnly, isTrue);
    });

    test('迁移 id 稳定，重复调用与合并都不会产生重复', () {
      final first = migrateLegacy(source);
      final second = migrateLegacy(source);
      expect(
        first.map((rule) => rule.id).toList(),
        second.map((rule) => rule.id).toList(),
      );
      expect(mergeMigrated(first, second).length, first.length);
    });

    test('合并已有同语义规则时按类型、范围与内容去重', () {
      const existing = FilterRule(
        id: 'custom-id',
        type: RuleType.keyword,
        content: 'r1',
        scopes: {RuleScope.reply},
      );
      final merged = mergeMigrated([existing], migrateLegacy(source));
      expect(merged.length, 9);
      expect(merged.where((rule) => rule.content == 'r1').length, 1);
      expect(merged.first.id, 'custom-id');
    });

    test('分区里的转义字面量仍按正则语义匹配', () {
      final rules = migrateLegacy(const LegacyRuleSource(zonePattern: r'\.'));
      expect(rules.length, 1);
      final rule = rules.single;
      expect(rule.type, RuleType.zone);
      expect(rule.content, r'\.');
      final set = RuleSet.text(rules, RuleScope.video);
      expect(set.matchesZone('电影.区'), isTrue);
      expect(set.matchesZone('电影X区'), isFalse);
    });

    test('整串回退产生的坏正则留在列表里，但引擎跳过', () {
      final rules = migrateLegacy(
        const LegacyRuleSource(replyPattern: 'ok|('),
      );
      expect(rules.length, 1);
      expect(rules.single.type, RuleType.regex);
      expect(rules.single.content, 'ok|(');
      expect(rules.single.validate(), isNotNull);
      expect(RuleSet.text(rules, RuleScope.reply).isEmpty, isTrue);
    });

    test('空来源不产生规则', () {
      expect(migrateLegacy(const LegacyRuleSource()), isEmpty);
      expect(const LegacyRuleSource().isEmpty, isTrue);
    });
  });
}
