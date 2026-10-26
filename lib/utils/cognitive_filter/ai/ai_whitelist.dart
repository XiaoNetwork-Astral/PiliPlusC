import 'package:PiliPlus/models/cognitive_filter/filter_rule.dart';
import 'package:PiliPlus/models/cognitive_filter/filter_surface.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/ai_whitelist_core.dart';
import 'package:PiliPlus/utils/cognitive_filter/rule_source.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/foundation.dart';

/// AI 屏蔽白名单的读写入口
///
/// 存的是和屏蔽规则一样的 [FilterRule] 列表，只影响 AI 屏蔽；命中白名单的
/// 内容既不屏蔽也不送去判定，规则屏蔽仍然照常生效。
class AiWhitelist implements RuleSource {
  AiWhitelist._();

  static final AiWhitelist instance = AiWhitelist._();

  /// 任何改动都会自增，供编译缓存失效与界面刷新
  @override
  final ValueNotifier<int> version = ValueNotifier<int>(0);

  late final AiWhitelistStore _store = AiWhitelistStore(
    read: () => Pref.cfAiWhitelistRules,
    write: (rules) => Pref.cfAiWhitelistRules = rules,
    onChanged: _bump,
  );

  AiWhitelistMatcher? _matcher;
  int _matcherVersion = -1;

  @override
  List<FilterRule> get rules => _store.rules;

  @override
  void add(FilterRule rule) {
    _store.add(rule);
  }

  @override
  void update(FilterRule rule) {
    _store.update(rule);
  }

  @override
  void remove(String id) {
    _store.remove(id);
  }

  @override
  void setEnabled(String id, bool enabled) {
    _store.setEnabled(id, enabled);
  }

  /// 把整段文字当关键词加入，空文本返回 false
  ///
  /// [surface] 非空时范围只含该适用面，为空时范围是全部五个适用面。
  bool addKeywordFromText(String text, {FilterSurface? surface}) =>
      _store.addKeywordFromText(text, surface: surface);

  /// 文字、UID 或弹幕哈希是否命中启用中的白名单
  bool matches({
    required FilterSurface surface,
    required String text,
    int? mid,
    String? midHash,
  }) {
    try {
      final currentVersion = version.value;
      if (_matcher == null || _matcherVersion != currentVersion) {
        _matcher = AiWhitelistMatcher(rules);
        _matcherVersion = currentVersion;
      }
      return _matcher!.matches(
        surface: surface,
        text: text,
        mid: mid,
        midHash: midHash,
      );
    } catch (_) {
      return false;
    }
  }

  void _bump() {
    version.value = version.value + 1;
  }
}
