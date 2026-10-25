import 'package:PiliPlus/models/cognitive_filter/filter_rule.dart';
import 'package:PiliPlus/models/cognitive_filter/rule_scope.dart';
import 'package:PiliPlus/models/cognitive_filter/rule_type.dart';
import 'package:flutter_test/flutter_test.dart';

FilterRule _rule({
  String id = 'r',
  RuleType type = RuleType.keyword,
  String content = '示例',
  Set<RuleScope> scopes = const {RuleScope.reply},
  bool enabled = true,
  String? midHash,
}) => FilterRule(
  id: id,
  type: type,
  content: content,
  scopes: scopes,
  enabled: enabled,
  midHash: midHash,
);

void main() {
  group('允许范围', () {
    test('各类型范围表与规格一致', () {
      expect(RuleType.keyword.allowedScopes, RuleScope.values.toSet());
      expect(RuleType.regex.allowedScopes, {
        RuleScope.danmaku,
        RuleScope.reply,
        RuleScope.dynamic,
        RuleScope.video,
        RuleScope.zone,
        RuleScope.live,
      });
      expect(RuleType.user.allowedScopes, {
        RuleScope.danmaku,
        RuleScope.reply,
        RuleScope.dynamic,
        RuleScope.video,
        RuleScope.live,
      });
      expect(
        {for (final type in RuleType.values) type.label},
        {'关键词', '正则', '用户'},
      );
      expect(
        {for (final scope in RuleScope.values) scope.label},
        {'弹幕', '评论', '动态', '视频', '视频分区', '私信', '直播'},
      );
    });
  });

  group('JSON 往返', () {
    test('四种规则往返保持字段', () {
      final rules = [
        _rule(
          id: 'k1',
          content: '示例词',
          scopes: {RuleScope.reply, RuleScope.live},
        ),
        _rule(
          id: 'r1',
          type: RuleType.regex,
          content: 'a.*b',
          scopes: {RuleScope.video},
          enabled: false,
        ),
        _rule(
          id: 'z1',
          type: RuleType.regex,
          content: '动画|电影',
          scopes: {RuleScope.zone},
        ),
        _rule(
          id: 'u1',
          type: RuleType.user,
          content: '12345',
          scopes: {RuleScope.reply},
        ),
        _rule(
          id: 'h1',
          type: RuleType.user,
          content: '',
          scopes: {RuleScope.danmaku},
          midHash: 'abcdef',
        ),
      ];
      for (final rule in rules) {
        final decoded = FilterRule.fromJson(rule.toJson());
        expect(decoded, isNotNull, reason: rule.id);
        expect(decoded!.id, rule.id);
        expect(decoded.type, rule.type);
        expect(decoded.content, rule.content);
        expect(decoded.scopes, rule.scopes);
        expect(decoded.enabled, rule.enabled);
        expect(decoded.midHash, rule.midHash);
      }
    });

    test('缺字段与类型错误不抛异常', () {
      expect(FilterRule.fromJson(null), isNull);
      expect(FilterRule.fromJson('not a map'), isNull);
      expect(FilterRule.fromJson(<String, dynamic>{}), isNull);
      // 缺 id
      expect(
        FilterRule.fromJson({
          'type': 'keyword',
          'content': 'a',
          'scopes': ['reply'],
        }),
        isNull,
      );
      // 未知类型
      expect(
        FilterRule.fromJson({'id': '1', 'type': 'nope', 'content': 'a'}),
        isNull,
      );
      // enabled 类型错误时默认启用，缺 scopes 时按该类型全部范围恢复
      final fallback = FilterRule.fromJson({
        'id': '2',
        'type': 'keyword',
        'content': 'a',
        'enabled': 'yes',
      });
      expect(fallback, isNotNull);
      expect(fallback!.enabled, isTrue);
      expect(fallback.scopes, RuleType.keyword.allowedScopes);
      // 明确给了范围但全部非法，视为无法恢复
      expect(
        FilterRule.fromJson({
          'id': '3',
          'type': 'regex',
          'content': 'a',
          'scopes': ['whisper', 'unknown'],
        }),
        isNull,
      );
    });

    test('只有哈希的用户规则范围固定为弹幕', () {
      final rule = FilterRule.fromJson({
        'id': 'h',
        'type': 'user',
        'content': '',
        'midHash': 'ABC123',
        'scopes': ['reply'],
      });
      expect(rule, isNotNull);
      expect(rule!.isHashOnly, isTrue);
      expect(rule.scopes, {RuleScope.danmaku});
      expect(rule.midHash, 'ABC123');
    });

    test('UID 与哈希同时存在时以 UID 为准', () {
      final rule = FilterRule.fromJson({
        'id': 'u',
        'type': 'user',
        'content': '42',
        'midHash': 'abc',
        'scopes': ['reply'],
      });
      expect(rule, isNotNull);
      expect(rule!.midHash, isNull);
      expect(rule.content, '42');
      expect(rule.isUidRule, isTrue);
    });

    test('无法编译的正则仍从 JSON 恢复，交给校验/引擎处理', () {
      final rule = FilterRule.fromJson({
        'id': 'bad',
        'type': 'regex',
        'content': '(',
        'scopes': ['reply'],
      });
      expect(rule, isNotNull);
      expect(rule!.content, '(');
      expect(rule.validate(), contains('正则表达式无法编译'));
    });

    test('用户 UID 的空白与非法内容被容错处理', () {
      final trimmed = FilterRule.fromJson({
        'id': 'u',
        'type': 'user',
        'content': ' 42 ',
        'scopes': ['reply'],
      });
      expect(trimmed, isNotNull);
      expect(trimmed!.content, '42');

      final hashOnly = FilterRule.fromJson({
        'id': 'h',
        'type': 'user',
        'content': '   ',
        'midHash': 'abc',
      });
      expect(hashOnly, isNotNull);
      expect(hashOnly!.isHashOnly, isTrue);
      expect(hashOnly.content, isEmpty);

      expect(
        FilterRule.fromJson({
          'id': 'bad',
          'type': 'user',
          'content': 'not-a-uid',
          'scopes': ['reply'],
        }),
        isNull,
      );
    });

    test('列表跳过无法恢复项与重复 id', () {
      final list = FilterRule.listFromJson([
        {'id': 'a', 'type': 'keyword', 'content': 'x', 'scopes': ['reply']},
        {'id': 'a', 'type': 'keyword', 'content': 'y', 'scopes': ['reply']},
        {'id': 'b', 'type': 'missing', 'content': 'z'},
        null,
      ]);
      expect(list.length, 1);
      expect(list.single.content, 'x');
      expect(FilterRule.listFromJson('bad'), isEmpty);
    });
  });

  group('校验', () {
    test('空内容、空范围、非法范围都有中文说明', () {
      expect(_rule(content: '').validate(), '内容不能为空');
      expect(_rule(scopes: const {}).validate(), contains('至少选择'));
      expect(
        _rule(type: RuleType.user, content: '1', scopes: {RuleScope.zone})
            .validate(),
        contains('不能用于'),
      );
      expect(
        _rule(
          type: RuleType.regex,
          content: 'a',
          scopes: {RuleScope.whisper},
        ).validate(),
        contains('不能用于'),
      );
    });

    test('用户 UID 必须是正整数，哈希规则范围固定', () {
      expect(
        _rule(type: RuleType.user, content: 'abc').validate(),
        contains('正整数'),
      );
      expect(_rule(type: RuleType.user, content: '0').validate(), contains('正整数'));
      expect(
        _rule(
          type: RuleType.user,
          content: '',
          scopes: {RuleScope.reply},
          midHash: 'abc',
        ).validate(),
        contains('只能用于弹幕'),
      );
      expect(
        _rule(
          type: RuleType.user,
          content: '42',
          midHash: 'abc',
        ).validate(),
        contains('不能同时'),
      );
      expect(
        _rule(
          type: RuleType.user,
          content: '',
          scopes: const {RuleScope.danmaku},
          midHash: 'abc',
        ).validate(),
        isNull,
      );
    });

    test('直播范围允许正则与用户规则，私信仍只允许关键词', () {
      expect(
        _rule(
          type: RuleType.regex,
          content: 'a.*b',
          scopes: {RuleScope.live},
        ).validate(),
        isNull,
      );
      expect(
        _rule(
          type: RuleType.user,
          content: '42',
          scopes: {RuleScope.live},
        ).validate(),
        isNull,
      );
      expect(
        _rule(
          type: RuleType.user,
          content: '42',
          scopes: {RuleScope.whisper},
        ).validate(),
        contains('不能用于'),
      );
    });

    test('正则编译失败给出中文说明，合法正则通过', () {
      expect(
        _rule(type: RuleType.regex, content: '(', scopes: {RuleScope.reply})
            .validate(),
        contains('正则表达式无法编译'),
      );
      expect(
        _rule(type: RuleType.regex, content: '[', scopes: {RuleScope.zone})
            .validate(),
        contains('正则表达式无法编译'),
      );
      expect(
        _rule(type: RuleType.regex, content: 'a.*b', scopes: {RuleScope.reply})
            .validate(),
        isNull,
      );
      expect(
        _rule(type: RuleType.regex, content: '动画|电影', scopes: {RuleScope.zone})
            .validate(),
        isNull,
      );
    });

    test('旧版本的分区类型读成正则加视频分区范围', () {
      final rule = FilterRule.fromJson({
        'id': 'old-zone',
        'type': 'zone',
        'content': '动画',
        'scopes': ['video'],
      });
      expect(rule, isNotNull);
      expect(rule!.type, RuleType.regex);
      expect(rule.scopes, {RuleScope.zone});
      expect(rule.content, '动画');
      expect(rule.validate(), isNull);
    });

    test('copyWith 能清空 midHash', () {
      final rule = _rule(
        type: RuleType.user,
        content: '',
        scopes: const {RuleScope.danmaku},
        midHash: 'abc',
      );
      expect(rule.copyWith(midHash: null).midHash, isNull);
      expect(rule.copyWith(content: 'x').midHash, 'abc');
    });
  });

  group('稳定 id 与哈希', () {
    test('稳定 id 可重复，范围或内容变化时不同', () {
      final a = FilterRule.stableId(
        type: RuleType.keyword,
        scopes: const {RuleScope.reply},
        content: '示例',
      );
      final b = FilterRule.stableId(
        type: RuleType.keyword,
        scopes: const {RuleScope.reply},
        content: '示例',
      );
      final c = FilterRule.stableId(
        type: RuleType.keyword,
        scopes: const {RuleScope.dynamic},
        content: '示例',
      );
      expect(a, b);
      expect(a, isNot(c));
      expect(FilterRule.userRuleId(42), 'user-mid-42');
      expect(FilterRule.midOfUserId('user-mid-42'), 42);
      expect(FilterRule.midOfUserId('other'), isNull);
    });

    test('UID 哈希与 CRC32 标准值一致', () {
      // 来源：Python `zlib.crc32(b'1')` 等，标准 CRC-32/ISO-HDLC，可离线核对：
      // "1" -> 83dcefb7，"123" -> 884863d2，"123456789" -> cbf43926
      expect(FilterRule.midToHash(1), '83dcefb7');
      expect(FilterRule.midToHash(123), '884863d2');
      expect(FilterRule.midToHash(123456789), 'cbf43926');
    });
  });
}
