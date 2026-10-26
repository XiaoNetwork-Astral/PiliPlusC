import 'package:PiliPlus/models/cognitive_filter/filter_rule.dart';
import 'package:PiliPlus/models/cognitive_filter/filter_surface.dart';
import 'package:PiliPlus/models/cognitive_filter/rule_scope.dart';
import 'package:PiliPlus/models/cognitive_filter/rule_set.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/ai_runtime.dart';
import 'package:PiliPlus/utils/cognitive_filter/rule_store.dart';
import 'package:PiliPlus/utils/global_data.dart';
import 'package:PiliPlus/utils/storage_pref.dart';

/// 规则匹配的统一入口，所有公开查询都尊重总开关 `Pref.cfRuleFilterEnabled`
class RuleEngine {
  RuleEngine._();

  static final RuleEngine instance = RuleEngine._();

  final Map<RuleScope, RuleSet> _textCache = {};

  final Map<RuleScope, UserRuleSet> _userCache = {};

  int _cachedVersion = -1;

  int _cachedMidCount = -1;

  int _cachedMidHash = 0;

  /// version 变化、`blackMids` 长度或内容变化时失效
  void _ensureCache() {
    final mids = GlobalData().blackMids;
    final version = RuleStore.instance.version.value;
    final midHash = Object.hashAllUnordered(mids);
    if (version == _cachedVersion &&
        mids.length == _cachedMidCount &&
        midHash == _cachedMidHash) {
      return;
    }
    _cachedVersion = version;
    _cachedMidCount = mids.length;
    _cachedMidHash = midHash;
    _textCache.clear();
    _userCache.clear();
  }

  RuleSet _textOf(RuleScope scope) =>
      _textCache[scope] ??= RuleSet.text(RuleStore.instance.rules, scope);

  UserRuleSet _usersOf(RuleScope scope) => _userCache[scope] ??= RuleSet.users(
    scope: scope,
    blackMids: GlobalData().blackMids,
    extras: Pref.cfRuleUserExtras,
    rules: RuleStore.instance.rules,
  );

  /// 文本是否命中关键词或正则，命中时记一条规则屏蔽
  bool matchText(RuleScope scope, String text) {
    if (text.isEmpty) return false;
    return snapshot(scope).matchText(text);
  }

  /// 取某个范围当前规则的快照，适合在循环里反复判断
  ///
  /// 总开关与编译结果只在取快照时读取一次；总开关关闭时返回的快照不屏蔽任何内容。
  RuleSnapshot snapshot(RuleScope scope) {
    if (!Pref.cfRuleFilterEnabled) return RuleSnapshot.off;
    _ensureCache();
    return RuleSnapshot._(scope, _textOf(scope), _usersOf(scope));
  }
}

/// 某个范围规则的只读快照，见 [RuleEngine.snapshot]
///
/// 命中时自动写入屏蔽历史，同一内容的重复命中由记录入口去重与限速。
class RuleSnapshot {
  const RuleSnapshot._(this._scope, this._text, this._users);

  /// 不屏蔽任何内容的快照，用于总开关关闭时
  static const RuleSnapshot off = RuleSnapshot._(null, null, null);

  final RuleScope? _scope;
  final RuleSet? _text;
  final UserRuleSet? _users;

  bool matchText(String text) {
    if (text.isEmpty) return false;
    final rule = _text?.firstMatch(text);
    if (rule == null) return false;
    _record(rule, text);
    return true;
  }

  /// [text] 是命中的内容，拿不到时记录 UID
  bool userBlocked(int mid, {String? text}) {
    if (mid <= 0) return false;
    final rule = _users?.ruleOfMid(mid);
    if (rule == null) return false;
    _record(rule, text == null || text.isEmpty ? mid.toString() : text);
    return true;
  }

  /// [text] 是命中的弹幕内容，拿不到时记录固定说明
  bool hashBlocked(String midHash, {String? text}) {
    if (midHash.isEmpty) return false;
    final rule = _users?.ruleOfHash(midHash);
    if (rule == null) return false;
    _record(rule, text == null || text.isEmpty ? 'B 站弹幕用户' : text);
    return true;
  }

  void _record(FilterRule rule, String text) {
    final surface = _surfaceOf(_scope);
    if (surface == null) return;
    AiFilterRuntime.instance.recordRuleBlock(
      surface: surface,
      text: text,
      ruleType: rule.type.label,
      content: rule.isHashOnly
          ? 'B 站弹幕用户${_hashPrefix(rule.midHash!)}'
          : rule.content,
      ruleId: rule.id,
    );
  }
}

/// 规则范围到屏蔽历史适用面的映射，私信不记录
FilterSurface? _surfaceOf(RuleScope? scope) => switch (scope) {
  RuleScope.danmaku => FilterSurface.danmaku,
  RuleScope.reply => FilterSurface.reply,
  RuleScope.dynamic => FilterSurface.dynamic,
  RuleScope.video || RuleScope.zone => FilterSurface.video,
  RuleScope.live => FilterSurface.live,
  _ => null,
};

String _hashPrefix(String hash) =>
    hash.length <= 8 ? hash : hash.substring(0, 8);
