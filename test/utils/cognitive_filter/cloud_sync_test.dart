import 'package:PiliPlus/models/cognitive_filter/filter_rule.dart';
import 'package:PiliPlus/models/cognitive_filter/rule_scope.dart';
import 'package:PiliPlus/models/cognitive_filter/rule_type.dart';
import 'package:PiliPlus/utils/backup/backup_item.dart';
import 'package:PiliPlus/utils/backup/backup_method.dart';
import 'package:PiliPlus/utils/cognitive_filter/cloud_sync_plan.dart';
import 'package:flutter_test/flutter_test.dart';

FilterRule _rule({
  String id = 'r',
  RuleType type = RuleType.keyword,
  String content = '示例',
  Set<RuleScope> scopes = const {RuleScope.danmaku},
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

FilterRule _hashRule({
  String id = 'h',
  String hash = 'h1',
  bool enabled = true,
}) => FilterRule(
  id: id,
  type: RuleType.user,
  content: '',
  scopes: const {RuleScope.danmaku},
  enabled: enabled,
  midHash: hash,
);

List<String> _keys(Iterable<DanmakuCloudRule> rules) => [
  for (final rule in rules) danmakuRuleKey(rule.type, rule.filter),
];

void main() {
  group('正则斜杠规范化', () {
    test('只去掉正则的首尾斜杠', () {
      expect(normalizeDanmakuFilter(1, '/abc/'), 'abc');
      expect(normalizeDanmakuFilter(1, '/a/b/'), 'a/b');
      expect(normalizeDanmakuFilter(1, '/abc'), '/abc');
      expect(normalizeDanmakuFilter(1, 'abc/'), 'abc/');
      expect(normalizeDanmakuFilter(0, '/abc/'), '/abc/');
      expect(normalizeDanmakuFilter(2, '/abc/'), '/abc/');
    });

    test('比对键按类型区分', () {
      expect(danmakuRuleKey(1, '/abc/'), '1|abc');
      expect(danmakuRuleKey(1, '/abc/'), isNot(danmakuRuleKey(0, 'abc')));
    });
  });

  group('本地数据筛选', () {
    test('弹幕规则包含关键词、正则和只有哈希的用户规则', () {
      final rules = [
        _rule(content: 'a', scopes: {RuleScope.danmaku, RuleScope.reply}),
        _rule(type: RuleType.regex, content: 'b'),
        _rule(type: RuleType.regex, content: 'c', scopes: {RuleScope.reply}),
        _hashRule(),
        _rule(content: 'd', scopes: {RuleScope.whisper}),
        _rule(type: RuleType.user, content: '12345'),
      ];
      final result = danmakuRulesOf(rules);
      expect(result.map((rule) => rule.id), ['r', 'r', 'h']);
    });

    test('私信规则只包含关键词', () {
      final rules = [
        _rule(content: 'a', scopes: {RuleScope.whisper}),
        _rule(
          type: RuleType.regex,
          content: 'b',
          scopes: {RuleScope.whisper},
        ),
        _rule(content: 'c', scopes: {RuleScope.danmaku}),
      ];
      expect(whisperRulesOf(rules).map((rule) => rule.content), ['a']);
    });
  });

  group('弹幕上传差异', () {
    test('只补云端缺少的启用规则，正则先规范化', () {
      final cloud = [
        const DanmakuCloudRule(type: 0, filter: 'a'),
        const DanmakuCloudRule(type: 1, filter: '/b/'),
        const DanmakuCloudRule(type: 2, filter: 'h1'),
      ];
      final local = [
        _rule(id: 'a', content: 'a'),
        _rule(id: 'c', content: 'c'),
        _rule(id: 'd', content: 'd', enabled: false),
        _rule(id: 'b', type: RuleType.regex, content: 'b'),
        _rule(id: 'e', type: RuleType.regex, content: 'e'),
        _rule(
          id: 'f',
          type: RuleType.regex,
          content: 'f',
          scopes: {RuleScope.reply},
        ),
        _hashRule(id: 'h1', hash: 'h1'),
        _hashRule(id: 'h2', hash: 'h2'),
        _rule(
          id: 'g',
          content: 'g',
          scopes: {RuleScope.danmaku, RuleScope.reply},
        ),
        _rule(id: 'uid', type: RuleType.user, content: '12345'),
        _rule(
          id: 'zone',
          type: RuleType.zone,
          content: '动画',
          scopes: {RuleScope.video},
        ),
      ];
      expect(
        _keys(diffDanmakuPush(cloud: cloud, local: local)),
        ['0|c', '1|e', '2|h2', '0|g'],
      );
      expect(
        _keys(diffDanmakuPush(cloud: cloud, local: local, onlyEnabled: false)),
        ['0|c', '0|d', '1|e', '2|h2', '0|g'],
      );
    });

    test('本地重复规则只上传一次', () {
      final local = [
        _rule(id: 'a', content: 'a'),
        _rule(id: 'b', content: 'a'),
        _rule(id: 'c', type: RuleType.regex, content: '/a/'),
      ];
      expect(
        _keys(diffDanmakuPush(cloud: const [], local: local)),
        ['0|a', '1|a'],
      );
    });
  });

  group('弹幕下载计划', () {
    test('跳过本地已有、重复和无效的云端规则', () {
      final local = [
        _rule(content: 'a'),
        _rule(type: RuleType.regex, content: 'b'),
        _hashRule(hash: 'h1'),
      ];
      final cloud = [
        const DanmakuCloudRule(type: 0, filter: 'a'),
        const DanmakuCloudRule(type: 1, filter: '/b/'),
        const DanmakuCloudRule(type: 0, filter: 'c'),
        const DanmakuCloudRule(type: 1, filter: '/[/'),
        const DanmakuCloudRule(type: 2, filter: 'h1'),
        const DanmakuCloudRule(type: 2, filter: ''),
        const DanmakuCloudRule(type: 9, filter: 'x'),
        const DanmakuCloudRule(type: 0, filter: ''),
      ];
      final plan = planDanmakuPull(cloud: cloud, local: local);
      expect(plan.rules.length, 1);
      expect(plan.rules.single.type, RuleType.keyword);
      expect(plan.rules.single.content, 'c');
      expect(plan.rules.single.scopes, {RuleScope.danmaku});
      expect(
        plan.rules.single.id,
        FilterRule.stableId(
          type: RuleType.keyword,
          scopes: const {RuleScope.danmaku},
          content: 'c',
        ),
      );
      expect(plan.skipped, 7);

      // 再拉一次时，已合并的规则全部跳过
      final again = planDanmakuPull(
        cloud: cloud,
        local: [...local, ...plan.rules],
      );
      expect(again.rules, isEmpty);
      expect(again.skipped, 8);
    });

    test('正则去斜杠后带范围 danmaku', () {
      final plan = planDanmakuPull(
        cloud: const [DanmakuCloudRule(type: 1, filter: '/a+b/')],
        local: const [],
      );
      expect(plan.rules.single.content, 'a+b');
      expect(plan.rules.single.type, RuleType.regex);
      expect(plan.rules.single.scopes, {RuleScope.danmaku});
    });
  });

  group('私信屏蔽词计划', () {
    test('按列表与字符上限跳过并统计', () {
      final plan = planWhisperPush(
        local: ['b', 'c', 'd', 'e', 'toolong'],
        cloud: ['a', 'b'],
        listLimit: 4,
        charLimit: 5,
      );
      expect(plan.toAdd, ['c', 'd']);
      expect(plan.tooLong, 1);
      expect(plan.overLimit, 1);
      expect(plan.skipped, 2);
    });

    test('上限为 0 表示不限制', () {
      final plan = planWhisperPush(
        local: ['a', 'b'],
        cloud: const [],
        listLimit: 0,
        charLimit: 0,
      );
      expect(plan.toAdd, ['a', 'b']);
      expect(plan.skipped, 0);
    });

    test('下载只补本地私信关键词', () {
      final local = [
        _rule(content: 'b', scopes: {RuleScope.whisper}),
        _rule(content: 'a', scopes: {RuleScope.reply}),
      ];
      final plan = planWhisperPull(
        cloud: ['a', 'b', 'c', 'c'],
        local: local,
      );
      expect(plan.rules.map((rule) => rule.content), ['a', 'c']);
      expect(plan.skipped, 2);
      expect(plan.rules.first.scopes, {RuleScope.whisper});
      expect(
        plan.rules.first.id,
        FilterRule.stableId(
          type: RuleType.keyword,
          scopes: const {RuleScope.whisper},
          content: 'a',
        ),
      );
    });
  });

  group('黑名单', () {
    test('上传只补云端缺少的 UID', () {
      expect(
        missingBlacklistMids(local: [3, 1, 2], cloud: [2, 3, 4]),
        {1},
      );
    });

    test('下载只补本地缺少的 UID，保持附加信息默认值', () {
      final plan = planBlacklistPull(
        cloud: [3, 1, 2, 2],
        local: {2, 4},
      );
      expect(plan.map((rule) => rule.content), ['3', '1']);
      expect(plan.first.type, RuleType.user);
      expect(plan.first.id, FilterRule.userRuleId(3));
      expect(plan.first.scopes, {RuleScope.danmaku, RuleScope.reply,
        RuleScope.dynamic, RuleScope.video, RuleScope.live});
      expect(plan.first.midHash, isNull);
    });
  });

  group('错误识别', () {
    test('“已存在”类提示按成功处理', () {
      expect(isAlreadyExistsMessage('该关键词已存在'), isTrue);
      expect(isAlreadyExistsMessage('已添加过'), isTrue);
      expect(isAlreadyExistsMessage('请勿重复添加'), isTrue);
      expect(isAlreadyExistsMessage('网络错误'), isFalse);
      expect(isAlreadyExistsMessage(null), isFalse);
    });

    test('限流与风控提示', () {
      expect(isRateLimitedMessage('请求过于频繁'), isTrue);
      expect(isRateLimitedMessage('操作太快了'), isTrue);
      expect(isRateLimitedMessage('触发风控'), isTrue);
      expect(isRateLimitedMessage('请完成安全验证'), isTrue);
      expect(isRateLimitedMessage('未知错误'), isFalse);
      expect(isRateLimitedMessage(null), isFalse);
    });
  });

  group('结果摘要', () {
    test('包含成功、跳过、失败数量与附加说明', () {
      const result = CloudSyncResult(
        success: 2,
        skipped: 1,
        failed: 3,
        note: '直播屏蔽词 成功 1 条',
      );
      expect(
        result.summary('条'),
        '成功 2 条，跳过 1 条，失败 3 条（直播屏蔽词 成功 1 条）',
      );
      const report = CloudSyncReport({
        CloudSyncKind.danmakuRules: CloudSyncResult(success: 1),
        CloudSyncKind.blacklist: CloudSyncResult(skipped: 2),
      });
      expect(report.hasChange, isTrue);
      expect(
        report.summary,
        '弹幕屏蔽规则：成功 1 条，跳过 0 条，失败 0 条；'
        '黑名单：成功 0 个，跳过 2 个，失败 0 个',
      );
    });
  });

  group('备份枚举接入', () {
    test('云端方式只支持三个屏蔽项', () {
      expect(
        BackupItem.cloudItems,
        {BackupItem.danmakuRules, BackupItem.whisperRules, BackupItem.blacklist},
      );
      for (final item in BackupItem.cloudItems) {
        expect(item.isSupportedBy(BackupMethod.cloud), isTrue);
        expect(item.syncWithCloud, isTrue);
      }
      expect(BackupItem.setting.isSupportedBy(BackupMethod.cloud), isFalse);
      expect(BackupItem.account.isSupportedBy(BackupMethod.cloud), isFalse);
      expect(BackupItem.customFont.isSupportedBy(BackupMethod.cloud), isFalse);
      expect(
        BackupItem.defaultSelectedFor(BackupMethod.cloud),
        BackupItem.cloudItems,
      );
    });

    test('其它方式仍然支持这三个屏蔽项', () {
      for (final method in BackupMethod.values) {
        if (method == BackupMethod.cloud) continue;
        for (final item in BackupItem.cloudItems) {
          expect(item.isSupportedBy(method), isTrue);
        }
      }
      expect(
        BackupItem.defaultSelectedFor(BackupMethod.webdav),
        BackupItem.defaultSelected,
      );
      expect(BackupMethod.cloud.label, 'B 站云端同步');
    });
  });
}
