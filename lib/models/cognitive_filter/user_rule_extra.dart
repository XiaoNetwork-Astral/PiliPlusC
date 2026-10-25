import 'package:PiliPlus/models/cognitive_filter/rule_scope.dart';
import 'package:PiliPlus/models/cognitive_filter/rule_type.dart';

/// 用户规则在 `blackMids` 之外的附加信息
///
/// UID 是否存在仍然只看 `blackMids`；这里只记录被禁用或被收窄范围的情况。
/// 没有记录的 UID 视为启用、范围为 [defaultScopes] 的全集。
class UserRuleExtra {
  const UserRuleExtra({this.enabled = true, this.scopes = defaultScopes});

  /// UID 规则默认生效的全部范围
  static const Set<RuleScope> defaultScopes = userRuleScopes;

  final bool enabled;

  final Set<RuleScope> scopes;

  /// 是否等同于「没有任何附加信息」
  bool get isDefault =>
      enabled &&
      scopes.length == defaultScopes.length &&
      scopes.containsAll(defaultScopes);

  UserRuleExtra copyWith({bool? enabled, Set<RuleScope>? scopes}) =>
      UserRuleExtra(
        enabled: enabled ?? this.enabled,
        scopes: scopes ?? this.scopes,
      );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'scopes': [
      for (final scope in RuleScope.values)
        if (scopes.contains(scope)) scope.name,
    ],
  };

  /// 缺字段、类型错误都按默认值容错，未知范围忽略
  static UserRuleExtra fromJson(Object? value) {
    if (value is! Map) return const UserRuleExtra();
    final rawEnabled = value['enabled'];
    final enabled = rawEnabled is bool ? rawEnabled : true;
    final parsed = <RuleScope>{};
    final rawScopes = value['scopes'];
    if (rawScopes is List) {
      for (final name in rawScopes) {
        if (name is! String) continue;
        final scope = RuleScope.byName(name);
        if (scope != null && userRuleScopes.contains(scope)) {
          parsed.add(scope);
        }
      }
    }
    if (parsed.isEmpty) return UserRuleExtra(enabled: enabled);
    return UserRuleExtra(enabled: enabled, scopes: parsed);
  }
}
