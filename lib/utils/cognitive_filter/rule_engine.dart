import 'package:PiliPlus/models/cognitive_filter/rule_scope.dart';
import 'package:PiliPlus/models/cognitive_filter/rule_set.dart';
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

  /// 文本是否命中关键词或正则
  bool matchText(RuleScope scope, String text) {
    final enabled = Pref.cfRuleFilterEnabled;
    if (!enabled || text.isEmpty) return false;
    _ensureCache();
    return _textOf(scope).matchesText(text, enabled: enabled);
  }

  /// 某个范围内该 UID 是否被屏蔽，被禁用或被收窄的 UID 返回 false
  bool userBlocked(RuleScope scope, int mid) {
    final enabled = Pref.cfRuleFilterEnabled;
    if (!enabled || mid <= 0) return false;
    _ensureCache();
    return _usersOf(scope).blocksMid(mid, enabled: enabled);
  }

  /// 弹幕发送者哈希是否被屏蔽，包含 UID 派生哈希与只有哈希的规则
  bool danmakuHashBlocked(String midHash) {
    final enabled = Pref.cfRuleFilterEnabled;
    if (!enabled || midHash.isEmpty) return false;
    _ensureCache();
    return _usersOf(RuleScope.danmaku).blocksHash(midHash, enabled: enabled);
  }

  /// 取某个范围当前规则的快照，适合在循环里反复判断
  ///
  /// 总开关与编译结果只在取快照时读取一次；总开关关闭时返回的快照不屏蔽任何内容。
  RuleSnapshot snapshot(RuleScope scope) {
    if (!Pref.cfRuleFilterEnabled) return RuleSnapshot.off;
    _ensureCache();
    return RuleSnapshot._(_textOf(scope), _usersOf(scope));
  }
}

/// 某个范围规则的只读快照，见 [RuleEngine.snapshot]
class RuleSnapshot {
  const RuleSnapshot._(this._text, this._users);

  /// 不屏蔽任何内容的快照，用于总开关关闭时
  static const RuleSnapshot off = RuleSnapshot._(null, null);

  final RuleSet? _text;
  final UserRuleSet? _users;

  bool matchText(String text) =>
      text.isNotEmpty && (_text?.matchesText(text) ?? false);

  bool userBlocked(int mid) => mid > 0 && (_users?.blocksMid(mid) ?? false);

  bool hashBlocked(String midHash) =>
      midHash.isNotEmpty && (_users?.blocksHash(midHash) ?? false);
}
