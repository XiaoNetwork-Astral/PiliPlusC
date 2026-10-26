import 'package:PiliPlus/models/cognitive_filter/filter_rule.dart';
import 'package:PiliPlus/models/cognitive_filter/rule_scope.dart';
import 'package:PiliPlus/models/cognitive_filter/rule_type.dart';
import 'package:PiliPlus/models/cognitive_filter/user_rule_extra.dart';

/// 可同步到 B 站云端的屏蔽数据类型
enum CloudSyncKind {
  danmakuRules('弹幕屏蔽规则', '条'),
  whisperRules('私信屏蔽词', '条'),
  blacklist('黑名单', '个');

  const CloudSyncKind(this.label, this.unit);

  /// 界面显示的名称
  final String label;

  /// 数量单位
  final String unit;
}

/// 单项同步的数量结果
class CloudSyncResult {
  const CloudSyncResult({
    this.success = 0,
    this.skipped = 0,
    this.failed = 0,
    this.note,
  });

  /// 成功写入云端或本地的新增数量
  final int success;

  /// 因上限、已存在、格式无效或中途停止而未处理的数量
  final int skipped;

  /// 请求失败的数量
  final int failed;

  /// 附加说明，例如直播屏蔽词结果、限流停止原因
  final String? note;

  /// 带单位的数量摘要
  String summary(String unit) {
    final text = '成功 $success $unit，跳过 $skipped $unit，失败 $failed $unit';
    final note = this.note;
    return note == null || note.isEmpty ? text : '$text（$note）';
  }
}

/// 一次同步中各项的结果
class CloudSyncReport {
  const CloudSyncReport(this.results);

  final Map<CloudSyncKind, CloudSyncResult> results;

  bool get hasFailure => results.values.any((result) => result.failed > 0);

  String get summary => [
    for (final entry in results.entries)
      '${entry.key.label}：${entry.value.summary(entry.key.unit)}',
  ].join('；');
}

/// 云端弹幕规则，[type] 0 关键词、1 正则、2 用户哈希
class DanmakuCloudRule {
  const DanmakuCloudRule({required this.type, required this.filter});

  final int type;

  final String filter;
}

/// 弹幕下载计划
class DanmakuPullPlan {
  const DanmakuPullPlan({required this.rules, required this.skipped});

  final List<FilterRule> rules;

  final int skipped;
}

/// 私信屏蔽词上传计划
class WhisperPushPlan {
  const WhisperPushPlan({
    required this.toAdd,
    required this.tooLong,
    required this.overLimit,
  });

  final List<String> toAdd;

  /// 超过单条字符上限
  final int tooLong;

  /// 超过列表条数上限
  final int overLimit;

  int get skipped => tooLong + overLimit;
}

/// 私信屏蔽词下载计划
class WhisperPullPlan {
  const WhisperPullPlan({required this.rules, required this.skipped});

  final List<FilterRule> rules;

  final int skipped;
}

/// 去掉云端正则首尾斜杠，其它类型原样返回
String normalizeDanmakuFilter(int type, String filter) {
  if (type != 1) return filter;
  final match = RegExp(r'^/(.*)/$', dotAll: true).firstMatch(filter);
  return match?.group(1) ?? filter;
}

/// 弹幕规则的比对键：类型 + 规范化内容
String danmakuRuleKey(int type, String filter) =>
    '$type|${normalizeDanmakuFilter(type, filter)}';

/// 本地可用于弹幕的规则：关键词、正则与只有哈希的用户规则
List<FilterRule> danmakuRulesOf(Iterable<FilterRule> rules) => [
  for (final rule in rules)
    if (!rule.isUidRule &&
        rule.scopes.contains(RuleScope.danmaku) &&
        (rule.type == RuleType.keyword ||
            rule.type == RuleType.regex ||
            rule.isHashOnly))
      rule,
];

/// 本地可用于私信的规则：关键词
List<FilterRule> whisperRulesOf(Iterable<FilterRule> rules) => [
  for (final rule in rules)
    if (rule.type == RuleType.keyword && rule.scopes.contains(RuleScope.whisper))
      rule,
];

/// 本地需要上传到弹幕云端的规则，默认只推启用的规则
List<DanmakuCloudRule> danmakuPushRulesOf(
  Iterable<FilterRule> rules, {
  bool onlyEnabled = true,
}) {
  final result = <DanmakuCloudRule>[];
  final seen = <String>{};
  for (final rule in rules) {
    if (onlyEnabled && !rule.enabled) continue;
    if (rule.isUidRule || !rule.scopes.contains(RuleScope.danmaku)) continue;
    final mapped = switch (rule.type) {
      RuleType.keyword => (0, rule.content),
      RuleType.regex => (1, normalizeDanmakuFilter(1, rule.content)),
      RuleType.user when rule.isHashOnly => (2, rule.midHash!),
      _ => null,
    };
    if (mapped == null) continue;
    final (type, content) = mapped;
    if (content.isEmpty) continue;
    if (!seen.add(danmakuRuleKey(type, content))) continue;
    result.add(DanmakuCloudRule(type: type, filter: content));
  }
  return result;
}

/// 云端缺少、需要上传的弹幕规则
List<DanmakuCloudRule> diffDanmakuPush({
  required Iterable<DanmakuCloudRule> cloud,
  required Iterable<FilterRule> local,
  bool onlyEnabled = true,
}) {
  final seen = {
    for (final rule in cloud) danmakuRuleKey(rule.type, rule.filter),
  };
  return [
    for (final rule in danmakuPushRulesOf(local, onlyEnabled: onlyEnabled))
      if (seen.add(danmakuRuleKey(rule.type, rule.filter))) rule,
  ];
}

/// 云端弹幕规则合并到本地的计划，已存在的规则跳过
DanmakuPullPlan planDanmakuPull({
  required Iterable<DanmakuCloudRule> cloud,
  required Iterable<FilterRule> local,
}) {
  final seen = <String>{};
  for (final rule in local) {
    final key = _localDanmakuKey(rule);
    if (key != null) seen.add(key);
  }

  final rules = <FilterRule>[];
  var skipped = 0;
  for (final item in cloud) {
    final parsed = switch (item.type) {
      0 => (RuleType.keyword, item.filter, null),
      1 => (RuleType.regex, normalizeDanmakuFilter(1, item.filter), null),
      2 => (RuleType.user, '', item.filter),
      _ => null,
    };
    if (parsed == null) {
      skipped++;
      continue;
    }
    final (type, content, midHash) = parsed;
    if (type == RuleType.user) {
      if (midHash == null || midHash.isEmpty) {
        skipped++;
        continue;
      }
    } else if (content.isEmpty) {
      skipped++;
      continue;
    }

    final key = type == RuleType.user
        ? danmakuRuleKey(2, midHash!)
        : danmakuRuleKey(type == RuleType.regex ? 1 : 0, content);
    if (!seen.add(key)) {
      skipped++;
      continue;
    }

    final rule = FilterRule(
      id: FilterRule.stableId(
        type: type,
        scopes: const {RuleScope.danmaku},
        content: content,
        midHash: midHash,
      ),
      type: type,
      content: content,
      scopes: const {RuleScope.danmaku},
      midHash: midHash,
    );
    if (rule.validate() != null) {
      skipped++;
      continue;
    }
    rules.add(rule);
  }
  return DanmakuPullPlan(rules: rules, skipped: skipped);
}

/// 私信屏蔽词上传计划，超出限制的关键词跳过
WhisperPushPlan planWhisperPush({
  required Iterable<String> local,
  required Iterable<String> cloud,
  int listLimit = 0,
  int charLimit = 0,
}) {
  final existing = cloud.toSet();
  final seen = <String>{};
  final toAdd = <String>[];
  var tooLong = 0;
  var overLimit = 0;
  for (final keyword in local) {
    if (keyword.isEmpty || !seen.add(keyword)) continue;
    if (existing.contains(keyword)) continue;
    if (charLimit > 0 && keyword.runes.length > charLimit) {
      tooLong++;
      continue;
    }
    if (listLimit > 0 && existing.length + toAdd.length >= listLimit) {
      overLimit++;
      continue;
    }
    toAdd.add(keyword);
  }
  return WhisperPushPlan(
    toAdd: toAdd,
    tooLong: tooLong,
    overLimit: overLimit,
  );
}

/// 云端私信屏蔽词合并到本地的计划
WhisperPullPlan planWhisperPull({
  required Iterable<String> cloud,
  required Iterable<FilterRule> local,
}) {
  final seen = <String>{
    for (final rule in local)
      if (rule.type == RuleType.keyword &&
          rule.scopes.contains(RuleScope.whisper))
        rule.content,
  };

  final rules = <FilterRule>[];
  var skipped = 0;
  for (final keyword in cloud) {
    if (keyword.isEmpty || !seen.add(keyword)) {
      skipped++;
      continue;
    }
    final rule = FilterRule(
      id: FilterRule.stableId(
        type: RuleType.keyword,
        scopes: const {RuleScope.whisper},
        content: keyword,
      ),
      type: RuleType.keyword,
      content: keyword,
      scopes: const {RuleScope.whisper},
    );
    if (rule.validate() != null) {
      skipped++;
      continue;
    }
    rules.add(rule);
  }
  return WhisperPullPlan(rules: rules, skipped: skipped);
}

/// 云端在线黑名单中本地缺少的 UID
Set<int> missingBlacklistMids({
  required Iterable<int> local,
  required Iterable<int> cloud,
}) => local.toSet()..removeAll(cloud.toSet());

/// 云端在线黑名单合并到本地的计划，只补不删
List<FilterRule> planBlacklistPull({
  required Iterable<int> cloud,
  required Iterable<int> local,
}) {
  final existing = local.toSet();
  return [
    for (final mid in cloud)
      if (mid > 0 && !existing.contains(mid) && existing.add(mid))
        FilterRule(
          id: FilterRule.userRuleId(mid),
          type: RuleType.user,
          content: '$mid',
          scopes: UserRuleExtra.defaultScopes,
        ),
  ];
}

/// 接口提示“已存在”时按成功处理
bool isAlreadyExistsMessage(String? message) {
  if (message == null) return false;
  return message.contains('已存在') ||
      message.contains('已添加') ||
      message.contains('重复');
}

/// 接口提示限流、风控或安全验证
bool isRateLimitedMessage(String? message) {
  if (message == null) return false;
  const words = [
    '频繁',
    '太快',
    '过快',
    '风控',
    '风险',
    '安全验证',
    '稍后再试',
    '操作被限制',
    '请求被限制',
  ];
  return words.any(message.contains);
}

String? _localDanmakuKey(FilterRule rule) {
  if (!rule.scopes.contains(RuleScope.danmaku)) return null;
  return switch (rule.type) {
    RuleType.keyword => danmakuRuleKey(0, rule.content),
    RuleType.regex => danmakuRuleKey(1, rule.content),
    RuleType.user when rule.isHashOnly => danmakuRuleKey(2, rule.midHash!),
    _ => null,
  };
}
