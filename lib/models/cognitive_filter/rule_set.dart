import 'package:PiliPlus/models/cognitive_filter/filter_rule.dart';
import 'package:PiliPlus/models/cognitive_filter/rule_scope.dart';
import 'package:PiliPlus/models/cognitive_filter/rule_type.dart';
import 'package:PiliPlus/models/cognitive_filter/user_rule_extra.dart';

/// 针对某个范围编译好的文本规则
///
/// 正则编译失败只在构造时静默跳过，规则本身仍留在规则列表里。
class RuleSet {
  RuleSet._(this._keywords, this._regexps);

  final List<String> _keywords;

  final List<RegExp> _regexps;

  bool get isEmpty => _keywords.isEmpty && _regexps.isEmpty;

  /// 编译某个范围的文本规则，视频分区也是一个范围
  factory RuleSet.text(Iterable<FilterRule> rules, RuleScope scope) {
    final keywords = <String>[];
    final regexps = <RegExp>[];
    for (final rule in rules) {
      if (!rule.enabled || !rule.scopes.contains(scope)) continue;
      // 防御式跳过类型不允许的范围（例如私信范围的正则）
      if (!rule.type.allowedScopes.contains(scope)) continue;
      switch (rule.type) {
        case RuleType.keyword:
          if (rule.content.isNotEmpty) {
            keywords.add(rule.content.toLowerCase());
          }
          break;
        case RuleType.regex:
          final regexp = _compile(rule.content);
          if (regexp != null) regexps.add(regexp);
          break;
        case RuleType.user:
          // 用户规则不参与文本匹配
          break;
      }
    }
    return RuleSet._(keywords, regexps);
  }

  /// 关键词按大小写不敏感的子串匹配，正则按大小写不敏感匹配
  ///
  /// [enabled] 对应总开关，关闭时一律返回 false。
  bool matchesText(String text, {bool enabled = true}) {
    if (!enabled || text.isEmpty) return false;
    final lower = text.toLowerCase();
    for (final keyword in _keywords) {
      if (lower.contains(keyword)) return true;
    }
    for (final regexp in _regexps) {
      if (regexp.hasMatch(text)) return true;
    }
    return false;
  }

  /// 用户规则编译入口，见 [UserRuleSet.compute]
  static UserRuleSet users({
    required RuleScope scope,
    required Set<int> blackMids,
    required Map<int, UserRuleExtra> extras,
    required Iterable<FilterRule> rules,
  }) => UserRuleSet.compute(
    scope: scope,
    blackMids: blackMids,
    extras: extras,
    rules: rules,
  );

  static RegExp? _compile(String pattern) {
    if (pattern.isEmpty) return null;
    try {
      return RegExp(pattern, caseSensitive: false);
    } on FormatException {
      return null;
    }
  }
}

/// 某个范围下真正生效的用户屏蔽集合
///
/// UID 来源是 `blackMids`，附加信息可以禁用或收窄范围；只有哈希的规则
/// 直接贡献哈希。被禁用或范围不含当前范围的 UID 不会进入任何一个集合。
class UserRuleSet {
  UserRuleSet._(Set<int> mids, Set<String> hashes)
    : blockedMids = Set.unmodifiable(mids),
      blockedHashes = Set.unmodifiable(hashes);

  final Set<int> blockedMids;

  final Set<String> blockedHashes;

  bool get isEmpty => blockedMids.isEmpty && blockedHashes.isEmpty;

  factory UserRuleSet.compute({
    required RuleScope scope,
    required Set<int> blackMids,
    required Map<int, UserRuleExtra> extras,
    required Iterable<FilterRule> rules,
  }) {
    final mids = <int>{};
    final hashes = <String>{};
    if (userRuleScopes.contains(scope)) {
      for (final mid in blackMids) {
        final extra = extras[mid] ?? const UserRuleExtra();
        if (!extra.enabled || !extra.scopes.contains(scope)) continue;
        mids.add(mid);
        if (scope == RuleScope.danmaku) {
          hashes.add(FilterRule.midToHash(mid));
        }
      }
      for (final rule in rules) {
        // 只有哈希的规则固定只用于弹幕，不参与其他范围的用户判断
        if (scope != RuleScope.danmaku ||
            rule.type != RuleType.user ||
            !rule.enabled ||
            !rule.isHashOnly ||
            !rule.scopes.contains(scope)) {
          continue;
        }
        final hash = rule.midHash!.toLowerCase();
        if (hash.isNotEmpty) hashes.add(hash);
      }
    }
    return UserRuleSet._(mids, hashes);
  }

  bool blocksMid(int mid, {bool enabled = true}) =>
      enabled && blockedMids.contains(mid);

  bool blocksHash(String midHash, {bool enabled = true}) {
    if (!enabled || midHash.isEmpty) return false;
    return blockedHashes.contains(midHash.toLowerCase());
  }
}
