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

  /// 视频分区名是否命中分区规则
  bool matchZone(String zoneName) {
    final enabled = Pref.cfRuleFilterEnabled;
    if (!enabled || zoneName.isEmpty) return false;
    _ensureCache();
    return _textOf(RuleScope.video).matchesZone(zoneName, enabled: enabled);
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
}
