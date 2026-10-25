import 'package:PiliPlus/models/cognitive_filter/filter_rule.dart';
import 'package:PiliPlus/models/cognitive_filter/rule_scope.dart';
import 'package:PiliPlus/models/cognitive_filter/rule_type.dart';
import 'package:PiliPlus/models/cognitive_filter/user_rule_extra.dart';

/// 针对某个范围编译好的文本规则
///
/// 正则编译失败只在构造时静默跳过，规则本身仍留在规则列表里。
class RuleSet {
  RuleSet._(this._entries);

  final List<_CompiledRule> _entries;

  bool get isEmpty => _entries.isEmpty;

  /// 编译某个范围的文本规则，视频分区也是一个范围
  factory RuleSet.text(Iterable<FilterRule> rules, RuleScope scope) {
    final entries = <_CompiledRule>[];
    for (final rule in rules) {
      if (!rule.enabled || !rule.scopes.contains(scope)) continue;
      // 防御式跳过类型不允许的范围（例如私信范围的正则）
      if (!rule.type.allowedScopes.contains(scope)) continue;
      switch (rule.type) {
        case RuleType.keyword:
          if (rule.content.isNotEmpty) {
            entries.add(
              _CompiledRule.keyword(rule, rule.content.toLowerCase()),
            );
          }
          break;
        case RuleType.regex:
          final regexp = _compile(rule.content);
          if (regexp != null) entries.add(_CompiledRule.regexp(rule, regexp));
          break;
        case RuleType.user:
          // 用户规则不参与文本匹配
          break;
      }
    }
    return RuleSet._(entries);
  }

  /// 关键词按大小写不敏感的子串匹配，正则按大小写不敏感匹配
  ///
  /// [enabled] 对应总开关，关闭时一律返回 false。
  bool matchesText(String text, {bool enabled = true}) =>
      enabled && firstMatch(text) != null;

  /// 返回第一条命中的规则，未命中返回 null
  FilterRule? firstMatch(String text) {
    if (text.isEmpty) return null;
    final lower = text.toLowerCase();
    for (final entry in _entries) {
      if (entry.matches(text, lower)) return entry.rule;
    }
    return null;
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

/// 一条编译后的文本规则，保留来源规则以便记录屏蔽历史
class _CompiledRule {
  _CompiledRule.keyword(this.rule, this._keyword) : _regexp = null;

  _CompiledRule.regexp(this.rule, this._regexp) : _keyword = null;

  final FilterRule rule;

  final String? _keyword;

  final RegExp? _regexp;

  bool matches(String text, String lower) {
    final keyword = _keyword;
    return keyword != null ? lower.contains(keyword) : _regexp!.hasMatch(text);
  }
}

/// 某个范围下真正生效的用户屏蔽集合
///
/// UID 来源是 `blackMids`，附加信息可以禁用或收窄范围；只有哈希的规则
/// 直接贡献哈希。被禁用或范围不含当前范围的 UID 不会进入任何一个集合。
class UserRuleSet {
  UserRuleSet._(
    this._scope,
    Set<int> mids,
    Map<String, FilterRule> hashRules,
  ) : blockedMids = Set.unmodifiable(mids),
      blockedHashes = Set.unmodifiable(hashRules.keys),
      _hashRules = Map.unmodifiable(hashRules);

  final RuleScope _scope;

  final Set<int> blockedMids;

  final Set<String> blockedHashes;

  /// 哈希到用户规则的映射，用于记录命中的是哪条规则
  final Map<String, FilterRule> _hashRules;

  bool get isEmpty => blockedMids.isEmpty && blockedHashes.isEmpty;

  factory UserRuleSet.compute({
    required RuleScope scope,
    required Set<int> blackMids,
    required Map<int, UserRuleExtra> extras,
    required Iterable<FilterRule> rules,
  }) {
    final mids = <int>{};
    final hashRules = <String, FilterRule>{};
    if (userRuleScopes.contains(scope)) {
      for (final mid in blackMids) {
        final extra = extras[mid] ?? const UserRuleExtra();
        if (!extra.enabled || !extra.scopes.contains(scope)) continue;
        mids.add(mid);
        if (scope == RuleScope.danmaku) {
          hashRules.putIfAbsent(
            FilterRule.midToHash(mid),
            () => FilterRule(
              id: FilterRule.userRuleId(mid),
              type: RuleType.user,
              content: mid.toString(),
              scopes: {scope},
            ),
          );
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
        if (hash.isNotEmpty) hashRules[hash] = rule;
      }
    }
    return UserRuleSet._(scope, mids, hashRules);
  }

  /// UID 命中时对应的用户规则；UID 规则不在规则列表里，这里即时构造
  FilterRule? ruleOfMid(int mid) {
    if (!blockedMids.contains(mid)) return null;
    return FilterRule(
      id: FilterRule.userRuleId(mid),
      type: RuleType.user,
      content: mid.toString(),
      scopes: {_scope},
    );
  }

  /// 弹幕发送者哈希命中时对应的用户规则
  FilterRule? ruleOfHash(String midHash) =>
      midHash.isEmpty ? null : _hashRules[midHash.toLowerCase()];

  bool blocksMid(int mid, {bool enabled = true}) =>
      enabled && blockedMids.contains(mid);

  bool blocksHash(String midHash, {bool enabled = true}) {
    if (!enabled || midHash.isEmpty) return false;
    return blockedHashes.contains(midHash.toLowerCase());
  }
}
