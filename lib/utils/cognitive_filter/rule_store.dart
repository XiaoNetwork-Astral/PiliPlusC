import 'package:PiliPlus/models/cognitive_filter/filter_rule.dart';
import 'package:PiliPlus/models/cognitive_filter/rule_migration.dart';
import 'package:PiliPlus/models/cognitive_filter/rule_scope.dart';
import 'package:PiliPlus/models/cognitive_filter/rule_type.dart';
import 'package:PiliPlus/models/cognitive_filter/user_rule_extra.dart';
import 'package:PiliPlus/utils/cognitive_filter/rule_source.dart';
import 'package:PiliPlus/utils/global_data.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/foundation.dart';

/// 规则的读写入口
///
/// UID 用户规则不存进规则列表：`blackMids` 是「哪些 UID 被拉黑」的唯一来源，
/// 这里只额外保存被禁用或收窄范围的信息。只有哈希的弹幕用户规则存在列表里。
class RuleStore implements RuleSource {
  RuleStore._();

  static final RuleStore instance = RuleStore._();

  /// 任何改动都会自增，供编译缓存失效与界面刷新
  final ValueNotifier<int> version = ValueNotifier<int>(0);

  /// 全部规则：列表里的规则 + 由 `blackMids` 派生的 UID 规则
  List<FilterRule> get rules {
    final extras = Pref.cfRuleUserExtras;
    final result = <FilterRule>[];
    final ids = <String>{};
    for (final rule in Pref.cfRuleList) {
      // 防御异常或导入的数据里混入 UID 规则，以 blackMids 为准，避免重复
      if (rule.isUidRule || !ids.add(rule.id)) continue;
      result.add(rule);
    }
    final mids = GlobalData().blackMids.toList()..sort();
    for (final mid in mids) {
      final extra = extras[mid] ?? const UserRuleExtra();
      final rule = FilterRule(
        id: FilterRule.userRuleId(mid),
        type: RuleType.user,
        content: '$mid',
        scopes: extra.scopes,
        enabled: extra.enabled,
      );
      if (ids.add(rule.id)) result.add(rule);
    }
    return result;
  }

  /// 校验并添加，成功后 [version] 自增；重复规则直接忽略
  void add(FilterRule rule) {
    final next = _checked(rule);
    if (next.isUidRule) {
      _addUid(next);
      return;
    }
    final stored = Pref.cfRuleList;
    if (stored.any((e) => e.id == next.id || _sameRule(e, next))) return;
    Pref.cfRuleList = [...stored, next];
    _bump();
  }

  /// 批量添加，已存在的 id 或语义相同的规则跳过
  ///
  /// 迁移时传 `validate: false`，因为旧整串回退可能产生暂时无法编译的正则，
  /// 这类规则要保留在列表里由引擎静默跳过。
  void addAll(Iterable<FilterRule> rules, {bool validate = true}) {
    final stored = <FilterRule>[...Pref.cfRuleList];
    final extras = <int, UserRuleExtra>{...Pref.cfRuleUserExtras};
    var changed = false;
    var blackChanged = false;
    for (final raw in rules) {
      final rule = raw.id.trim().isEmpty
          ? raw.copyWith(id: FilterRule.nextId())
          : raw;
      if (validate) {
        final error = rule.validate();
        if (error != null) throw ArgumentError.value(raw, 'rule', error);
      }
      if (rule.isUidRule) {
        final mid = int.tryParse(rule.content);
        if (mid == null || mid <= 0) continue;
        if (GlobalData().blackMids.add(mid)) {
          blackChanged = true;
          changed = true;
        }
        final extra = UserRuleExtra(enabled: rule.enabled, scopes: rule.scopes);
        if (extra.isDefault) {
          if (extras.remove(mid) != null) changed = true;
        } else {
          final old = extras[mid];
          if (old == null ||
              old.enabled != extra.enabled ||
              !_sameScopes(old.scopes, extra.scopes)) {
            extras[mid] = extra;
            changed = true;
          }
        }
        continue;
      }
      if (stored.any((e) => e.id == rule.id || _sameRule(e, rule))) continue;
      stored.add(rule);
      changed = true;
    }
    if (!changed) return;
    if (blackChanged) Pref.blackMids = GlobalData().blackMids;
    Pref.cfRuleList = stored;
    Pref.cfRuleUserExtras = extras;
    _bump();
  }

  /// 按 id 更新；UID 变化时同步 `blackMids` 与附加信息
  void update(FilterRule rule) {
    final next = _checked(rule);
    final current = _find(next.id);
    if (current == null) throw ArgumentError.value(next.id, 'id', '规则不存在');
    final currentUid = current.isUidRule;
    final nextUid = next.isUidRule;
    if (currentUid && nextUid) {
      final oldMid = int.parse(current.content);
      final newMid = int.parse(next.content);
      if (oldMid != newMid) {
        _removeUid(oldMid);
        _addUid(next);
      } else {
        _updateUid(next);
      }
      return;
    }
    if (!currentUid && !nextUid) {
      final stored = Pref.cfRuleList;
      final index = stored.indexWhere((e) => e.id == current.id);
      if (index < 0) throw ArgumentError.value(next.id, 'id', '规则不存在');
      final old = stored[index];
      if (_sameRule(old, next) && old.enabled == next.enabled) return;
      final updated = [...stored];
      updated[index] = next;
      Pref.cfRuleList = updated;
      _bump();
      return;
    }
    if (currentUid) {
      _removeUid(int.parse(current.content));
      // 原先的 id 是 UID 派生格式，转成普通规则时换一个 id
      _appendStored(next.copyWith(id: FilterRule.nextId()));
    } else {
      _removeStored(current.id);
      final mid = int.parse(next.content);
      _addUid(next.copyWith(id: FilterRule.userRuleId(mid)));
    }
  }

  /// 按 id 删除，UID 规则会同时移出 `blackMids` 并清掉附加信息
  void remove(String id) {
    final current = _find(id);
    if (current == null) throw ArgumentError.value(id, 'id', '规则不存在');
    if (current.isUidRule) {
      _removeUid(int.parse(current.content));
      return;
    }
    _removeStored(id);
  }

  void setEnabled(String id, bool enabled) {
    final current = _find(id);
    if (current == null) throw ArgumentError.value(id, 'id', '规则不存在');
    if (current.isUidRule) {
      final mid = int.parse(current.content);
      final extra = Pref.cfRuleUserExtras[mid] ?? const UserRuleExtra();
      if (extra.enabled == enabled) return;
      if (_writeExtra(mid, extra.copyWith(enabled: enabled))) _bump();
      return;
    }
    final stored = Pref.cfRuleList;
    final index = stored.indexWhere((e) => e.id == id);
    if (index < 0) throw ArgumentError.value(id, 'id', '规则不存在');
    if (stored[index].enabled == enabled) return;
    final updated = [...stored];
    updated[index] = stored[index].copyWith(enabled: enabled);
    Pref.cfRuleList = updated;
    _bump();
  }

  FilterRule? _find(String id) {
    for (final rule in rules) {
      if (rule.id == id) return rule;
    }
    return null;
  }

  FilterRule _checked(FilterRule rule) {
    final next = rule.id.trim().isEmpty
        ? rule.copyWith(id: FilterRule.nextId())
        : rule;
    final error = next.validate();
    if (error != null) throw ArgumentError.value(rule, 'rule', error);
    return next;
  }

  void _addUid(FilterRule rule) {
    final mid = int.parse(rule.content);
    final isNew = GlobalData().blackMids.add(mid);
    final extraChanged = _writeExtra(
      mid,
      UserRuleExtra(enabled: rule.enabled, scopes: rule.scopes),
    );
    if (!isNew && !extraChanged) return;
    if (isNew) Pref.blackMids = GlobalData().blackMids;
    _bump();
  }

  void _updateUid(FilterRule rule) {
    final mid = int.parse(rule.content);
    final isNew = GlobalData().blackMids.add(mid);
    final extraChanged = _writeExtra(
      mid,
      UserRuleExtra(enabled: rule.enabled, scopes: rule.scopes),
    );
    if (isNew) {
      Pref.blackMids = GlobalData().blackMids;
      _bump();
    } else if (extraChanged) {
      _bump();
    }
  }

  void _removeUid(int mid) {
    var changed = GlobalData().blackMids.remove(mid);
    if (changed) Pref.blackMids = GlobalData().blackMids;
    final extras = Pref.cfRuleUserExtras;
    if (extras.containsKey(mid)) {
      Pref.cfRuleUserExtras = Map<int, UserRuleExtra>.from(extras)
        ..remove(mid);
      changed = true;
    }
    if (changed) _bump();
  }

  void _appendStored(FilterRule rule) {
    final stored = Pref.cfRuleList;
    if (stored.any((e) => e.id == rule.id || _sameRule(e, rule))) return;
    Pref.cfRuleList = [...stored, rule];
    _bump();
  }

  void _removeStored(String id) {
    final stored = Pref.cfRuleList;
    final next = stored.where((e) => e.id != id).toList();
    if (next.length == stored.length) {
      throw ArgumentError.value(id, 'id', '规则不存在');
    }
    Pref.cfRuleList = next;
    _bump();
  }

  bool _writeExtra(int mid, UserRuleExtra extra) {
    final current = Pref.cfRuleUserExtras;
    final old = current[mid];
    if (extra.isDefault) {
      if (old == null) return false;
      Pref.cfRuleUserExtras = Map<int, UserRuleExtra>.from(current)
        ..remove(mid);
      return true;
    }
    if (old != null &&
        old.enabled == extra.enabled &&
        _sameScopes(old.scopes, extra.scopes)) {
      return false;
    }
    final next = Map<int, UserRuleExtra>.from(current);
    next[mid] = extra;
    Pref.cfRuleUserExtras = next;
    return true;
  }

  void _bump() {
    version.value = version.value + 1;
  }
}

/// 一次性把旧设置迁移到规则列表
///
/// 只读旧键、不删旧键、不触发任何联网或云端同步；完成后写标记，重复调用直接
/// 返回 false。迁移出的 id 稳定，即使标记丢失也不会产生重复规则。
abstract final class RuleMigration {
  static bool runIfNeeded() {
    if (Pref.cfRuleMigrationDone) return false;
    final danmaku = Pref.danmakuFilterRule;
    final source = LegacyRuleSource(
      replyPattern: Pref.banWordForReply,
      dynamicPattern: Pref.banWordForDyn,
      videoPattern: Pref.banWordForRecommend,
      zonePattern: Pref.banWordForZone,
      danmakuKeywords: List<String>.of(danmaku.dmFilterString),
      danmakuRegexps: [
        for (final regexp in danmaku.dmRegExp) regexp.pattern,
      ],
      danmakuUidHashes: Set<String>.of(danmaku.dmUid),
    );
    RuleStore.instance.addAll(migrateLegacy(source), validate: false);
    Pref.cfRuleMigrationDone = true;
    return true;
  }
}

bool _sameRule(FilterRule a, FilterRule b) =>
    a.type == b.type &&
    a.content == b.content &&
    (a.midHash ?? '') == (b.midHash ?? '') &&
    _sameScopes(a.scopes, b.scopes);

bool _sameScopes(Set<RuleScope> a, Set<RuleScope> b) =>
    a.length == b.length && a.containsAll(b);
