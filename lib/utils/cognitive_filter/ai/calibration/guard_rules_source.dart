import 'package:PiliPlus/models/cognitive_filter/filter_rule.dart';
import 'package:PiliPlus/models/cognitive_filter/rule_scope.dart';
import 'package:PiliPlus/models/cognitive_filter/rule_type.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/ai_whitelist_core.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/calibration/upload_guard.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/calibration/upload_guard_data.dart';
import 'package:PiliPlus/utils/cognitive_filter/rule_source.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/foundation.dart';

/// 用户自己维护的「不外传规则」数据源
///
/// 与白名单共用同一套规则模型与列表页，存进 [Pref.cfGuardRules]。规则
/// 不区分适用面，范围固定为 [aiWhitelistScopes] 全部，匹配时也不看范围。
class GuardRulesSource implements RuleSource {
  GuardRulesSource._();

  static final GuardRulesSource instance = GuardRulesSource._();

  /// 任何改动都会自增，供上传检查器与界面刷新
  @override
  final ValueNotifier<int> version = ValueNotifier<int>(0);

  late final AiWhitelistStore _store = AiWhitelistStore(
    read: () => Pref.cfGuardRules,
    write: (rules) => Pref.cfGuardRules = rules,
    onChanged: _bump,
  );

  @override
  List<FilterRule> get rules => _store.rules;

  @override
  void add(FilterRule rule) {
    _store.add(_withAllScopes(rule));
  }

  @override
  void update(FilterRule rule) {
    _store.update(_withAllScopes(rule));
  }

  @override
  void remove(String id) {
    _store.remove(id);
  }

  @override
  void setEnabled(String id, bool enabled) {
    _store.setEnabled(id, enabled);
  }

  /// 把内置规则与用户启用中的关键词、正则合成一个上传检查器
  ///
  /// 用户 UID 规则不参与文本匹配，直接忽略
  UploadGuard buildGuard() {
    final rules = <GuardRule>[...defaultGuardRules()];
    for (final rule in this.rules) {
      if (!rule.enabled || rule.type == RuleType.user) {
        continue;
      }
      if (rule.content.isEmpty) {
        continue;
      }
      rules.add(
        GuardRule(regex: rule.type == RuleType.regex, content: rule.content),
      );
    }
    return UploadGuard(rules);
  }

  /// 不外传规则不分适用面，统一补成全部五个范围
  FilterRule _withAllScopes(FilterRule rule) {
    if (rule.scopes.length == aiWhitelistScopes.length &&
        rule.scopes.containsAll(aiWhitelistScopes)) {
      return rule;
    }
    return rule.copyWith(scopes: Set<RuleScope>.of(aiWhitelistScopes));
  }

  void _bump() {
    version.value = version.value + 1;
  }
}
