import 'package:PiliPlus/models/cognitive_filter/rule_scope.dart';

/// 关键词可用于全部范围
const Set<RuleScope> allRuleScopes = {
  RuleScope.danmaku,
  RuleScope.reply,
  RuleScope.dynamic,
  RuleScope.video,
  RuleScope.zone,
  RuleScope.whisper,
  RuleScope.live,
};

/// 正则只用于有文本正文的范围（含视频分区名、直播卡片标题/分区名/主播名）
const Set<RuleScope> textRuleScopes = {
  RuleScope.danmaku,
  RuleScope.reply,
  RuleScope.dynamic,
  RuleScope.video,
  RuleScope.zone,
  RuleScope.live,
};

/// 用户规则可用于五个内容范围
const Set<RuleScope> userRuleScopes = {
  RuleScope.danmaku,
  RuleScope.reply,
  RuleScope.dynamic,
  RuleScope.video,
  RuleScope.live,
};

/// 规则类型
enum RuleType {
  keyword('关键词', allRuleScopes),
  regex('正则', textRuleScopes),
  user('用户', userRuleScopes);

  const RuleType(this.label, this.allowedScopes);

  /// 界面显示的名称
  final String label;

  /// 该类型允许的全部范围
  final Set<RuleScope> allowedScopes;

  /// 由存储里的枚举名反查，未知名称返回 null
  static RuleType? byName(String name) => values.asNameMap()[name];
}
