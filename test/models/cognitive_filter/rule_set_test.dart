import 'package:PiliPlus/models/cognitive_filter/filter_rule.dart';
import 'package:PiliPlus/models/cognitive_filter/rule_scope.dart';
import 'package:PiliPlus/models/cognitive_filter/rule_set.dart';
import 'package:PiliPlus/models/cognitive_filter/rule_type.dart';
import 'package:PiliPlus/models/cognitive_filter/user_rule_extra.dart';
import 'package:flutter_test/flutter_test.dart';

FilterRule _rule({
  String id = 'r',
  RuleType type = RuleType.keyword,
  String content = '',
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
  group('文本匹配', () {
    test('关键词是大小写不敏感的子串包含', () {
      final set = RuleSet.text([
        _rule(content: 'AbC', scopes: const {RuleScope.reply}),
      ], RuleScope.reply);
      expect(set.matchesText('xxabcxx'), isTrue);
      expect(set.matchesText('xxABCxx'), isTrue);
      expect(set.matchesText('xxabxx'), isFalse);
      expect(set.matchesText(''), isFalse);
    });

    test('中文关键词按子串匹配', () {
      final set = RuleSet.text([
        _rule(content: '示例', scopes: const {RuleScope.dynamic}),
      ], RuleScope.dynamic);
      expect(set.matchesText('这是一条示例文本'), isTrue);
      expect(set.matchesText('这是一条文本'), isFalse);
    });

    test('只匹配当前范围且忽略已禁用规则', () {
      final rules = [
        _rule(content: '只在评论', scopes: const {RuleScope.reply}),
        _rule(
          id: 'off',
          content: '已关闭',
          scopes: const {RuleScope.reply},
          enabled: false,
        ),
        _rule(
          id: 'video',
          content: '只在视频',
          scopes: const {RuleScope.video},
        ),
      ];
      final reply = RuleSet.text(rules, RuleScope.reply);
      expect(reply.matchesText('只在评论'), isTrue);
      expect(reply.matchesText('已关闭'), isFalse);
      expect(reply.matchesText('只在视频'), isFalse);
    });

    test('正则是大小写不敏感的，编译失败被静默跳过', () {
      final set = RuleSet.text([
        _rule(
          id: 'bad',
          type: RuleType.regex,
          content: '(',
          scopes: const {RuleScope.reply},
        ),
        _rule(
          id: 'good',
          type: RuleType.regex,
          content: 'ab+c',
          scopes: const {RuleScope.reply},
        ),
      ], RuleScope.reply);
      expect(set.matchesText('ABBBC'), isTrue);
      expect(() => set.matchesText('('), returnsNormally);
      expect(set.matchesText('('), isFalse);

      final onlyBad = RuleSet.text([
        _rule(
          id: 'bad2',
          type: RuleType.regex,
          content: '[',
          scopes: const {RuleScope.reply},
        ),
      ], RuleScope.reply);
      expect(onlyBad.isEmpty, isTrue);
    });
    test('总开关关闭时文本与用户查询一律不命中', () {
      final textSet = RuleSet.text([
        _rule(content: 'abc', scopes: const {RuleScope.reply}),
      ], RuleScope.reply);
      expect(textSet.matchesText('abc'), isTrue);
      expect(textSet.matchesText('abc', enabled: false), isFalse);

      final zoneSet = RuleSet.text([
        _rule(
          id: 'z',
          type: RuleType.regex,
          content: '动画',
          scopes: const {RuleScope.zone},
        ),
      ], RuleScope.zone);
      expect(zoneSet.matchesText('动画区', enabled: false), isFalse);

      final users = UserRuleSet.compute(
        scope: RuleScope.reply,
        blackMids: const {9},
        extras: const {},
        rules: const [],
      );
      expect(users.blocksMid(9, enabled: false), isFalse);
    });
  });

  group('分区匹配', () {
    test('视频分区范围的规则只匹配分区名', () {
      final rules = [
        _rule(
          id: 'z',
          type: RuleType.regex,
          content: '动画|电影',
          scopes: const {RuleScope.zone},
        ),
      ];
      final zone = RuleSet.text(rules, RuleScope.zone);
      expect(zone.matchesText('新番动画区'), isTrue);
      expect(zone.matchesText('电影区'), isTrue);
      expect(zone.matchesText('游戏区'), isFalse);
      expect(zone.matchesText(''), isFalse);

      final video = RuleSet.text(rules, RuleScope.video);
      expect(video.matchesText('动画区'), isFalse);
    });

    test('分区正则大小写不敏感，但不参与视频标题匹配', () {
      final rules = [
        _rule(
          id: 'z',
          type: RuleType.regex,
          content: 'cook',
          scopes: const {RuleScope.zone},
        ),
      ];
      final zone = RuleSet.text(rules, RuleScope.zone);
      expect(zone.matchesText('COOK区'), isTrue);
      final video = RuleSet.text(rules, RuleScope.video);
      expect(video.matchesText('cook 内容'), isFalse);
    });

    test('分区规则不会进入直播或评论范围', () {
      final rules = [
        _rule(
          id: 'z',
          type: RuleType.regex,
          content: '动画',
          scopes: const {RuleScope.zone},
        ),
      ];
      expect(RuleSet.text(rules, RuleScope.live).isEmpty, isTrue);
      expect(RuleSet.text(rules, RuleScope.reply).isEmpty, isTrue);
    });
  });

  group('直播范围', () {
    test('关键词与正则都可用于直播标题/分区/主播名', () {
      final rules = [
        _rule(
          id: 'k',
          content: '示例主播',
          scopes: const {RuleScope.live},
        ),
        _rule(
          id: 'r',
          type: RuleType.regex,
          content: 'spam+',
          scopes: const {RuleScope.live},
        ),
        // 私信不允许正则，即使写进列表也不该生效
        _rule(
          id: 'bad',
          type: RuleType.regex,
          content: 'whisper',
          scopes: const {RuleScope.whisper},
        ),
      ];
      final live = RuleSet.text(rules, RuleScope.live);
      expect(live.matchesText('关注示例主播'), isTrue);
      expect(live.matchesText('SPAMMM'), isTrue);
      expect(live.matchesText('whisper'), isFalse);
      expect(
        RuleSet.text(rules, RuleScope.whisper).matchesText('whisper'),
        isFalse,
      );
    });

    test('用户规则默认在直播范围也生效', () {
      final users = UserRuleSet.compute(
        scope: RuleScope.live,
        blackMids: const {1, 2},
        extras: const {2: UserRuleExtra(enabled: false)},
        rules: const [],
      );
      expect(users.blocksMid(1), isTrue);
      expect(users.blocksMid(2), isFalse);
      expect(users.blockedHashes, isEmpty);
    });
  });

  group('用户规则集合', () {
    test('默认启用，禁用后不屏蔽，收窄范围只在指定范围生效', () {
      final blackMids = {1, 2, 3};
      final extras = <int, UserRuleExtra>{
        2: const UserRuleExtra(enabled: false),
        3: const UserRuleExtra(scopes: {RuleScope.reply}),
      };
      final reply = UserRuleSet.compute(
        scope: RuleScope.reply,
        blackMids: blackMids,
        extras: extras,
        rules: const [],
      );
      expect(reply.blocksMid(1), isTrue);
      expect(reply.blocksMid(2), isFalse);
      expect(reply.blocksMid(3), isTrue);
      expect(reply.blockedMids, {1, 3});
      expect(reply.blockedHashes, isEmpty);

      final video = UserRuleSet.compute(
        scope: RuleScope.video,
        blackMids: blackMids,
        extras: extras,
        rules: const [],
      );
      expect(video.blocksMid(3), isFalse);
      expect(video.blocksMid(1), isTrue);

      final whisper = UserRuleSet.compute(
        scope: RuleScope.whisper,
        blackMids: blackMids,
        extras: extras,
        rules: const [],
      );
      expect(whisper.isEmpty, isTrue);
    });

    test('弹幕范围同时产出 UID 哈希，被禁用的 UID 不产出', () {
      final blackMids = {1, 2};
      final extras = <int, UserRuleExtra>{
        2: const UserRuleExtra(enabled: false),
      };
      final danmaku = UserRuleSet.compute(
        scope: RuleScope.danmaku,
        blackMids: blackMids,
        extras: extras,
        rules: const [],
      );
      expect(
        danmaku.blockedHashes,
        contains(FilterRule.midToHash(1)),
      );
      expect(
        danmaku.blockedHashes,
        isNot(contains(FilterRule.midToHash(2))),
      );
      expect(danmaku.blocksHash(FilterRule.midToHash(1).toUpperCase()), isTrue);
      expect(danmaku.blocksHash(''), isFalse);
    });

    test('只有哈希的规则直接贡献哈希，并尊重启用状态', () {
      final rules = [
        _rule(
          id: 'h',
          type: RuleType.user,
          content: '',
          scopes: const {RuleScope.danmaku},
          midHash: 'A1B2',
        ),
        _rule(
          id: 'off',
          type: RuleType.user,
          content: '',
          scopes: const {RuleScope.danmaku},
          midHash: 'c3d4',
          enabled: false,
        ),
      ];
      final danmaku = UserRuleSet.compute(
        scope: RuleScope.danmaku,
        blackMids: const {},
        extras: const {},
        rules: rules,
      );
      expect(danmaku.blocksHash('a1b2'), isTrue);
      expect(danmaku.blocksHash('A1B2'), isTrue);
      expect(danmaku.blocksHash('c3d4'), isFalse);
      expect(danmaku.blockedMids, isEmpty);

      final viaRuleSet = RuleSet.users(
        scope: RuleScope.danmaku,
        blackMids: const {},
        extras: const {},
        rules: rules,
      );
      expect(viaRuleSet.blocksHash('a1b2'), isTrue);
    });

    test('UID 范围收窄为评论后，不再命中弹幕哈希', () {
      final blackMids = {7};
      final extras = <int, UserRuleExtra>{
        7: const UserRuleExtra(scopes: {RuleScope.reply}),
      };
      final danmaku = UserRuleSet.compute(
        scope: RuleScope.danmaku,
        blackMids: blackMids,
        extras: extras,
        rules: const [],
      );
      expect(danmaku.isEmpty, isTrue);
      final reply = UserRuleSet.compute(
        scope: RuleScope.reply,
        blackMids: blackMids,
        extras: extras,
        rules: const [],
      );
      expect(reply.blocksMid(7), isTrue);
    });

    test('附加信息默认值与 JSON 容错', () {
      expect(const UserRuleExtra().isDefault, isTrue);
      expect(const UserRuleExtra(enabled: false).isDefault, isFalse);
      final decoded = UserRuleExtra.fromJson({
        'enabled': 'bad',
        'scopes': ['reply', 'whisper'],
      });
      expect(decoded.enabled, isTrue);
      expect(decoded.scopes, {RuleScope.reply});
      expect(UserRuleExtra.fromJson('bad').isDefault, isTrue);
      final roundTrip = const UserRuleExtra(
        enabled: false,
        scopes: {RuleScope.dynamic},
      );
      final again = UserRuleExtra.fromJson(roundTrip.toJson());
      expect(again.enabled, isFalse);
      expect(again.scopes, {RuleScope.dynamic});
    });
  });
}
