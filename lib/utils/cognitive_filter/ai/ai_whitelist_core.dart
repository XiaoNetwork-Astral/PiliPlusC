import 'package:PiliPlus/models/cognitive_filter/filter_rule.dart';
import 'package:PiliPlus/models/cognitive_filter/filter_surface.dart';
import 'package:PiliPlus/models/cognitive_filter/rule_scope.dart';
import 'package:PiliPlus/models/cognitive_filter/rule_set.dart';
import 'package:PiliPlus/models/cognitive_filter/rule_type.dart';

/// 白名单可用的适用范围，比规则系统少了视频分区与私信
const Set<RuleScope> aiWhitelistScopes = {
  RuleScope.danmaku,
  RuleScope.reply,
  RuleScope.dynamic,
  RuleScope.video,
  RuleScope.live,
};

/// 适用面到白名单范围的映射，两者一一对应
RuleScope? aiWhitelistScopeOf(FilterSurface surface) => switch (surface) {
  FilterSurface.danmaku => RuleScope.danmaku,
  FilterSurface.reply => RuleScope.reply,
  FilterSurface.dynamic => RuleScope.dynamic,
  FilterSurface.video => RuleScope.video,
  FilterSurface.live => RuleScope.live,
};

/// 校验白名单规则，通过时返回 null
///
/// 先走 [FilterRule.validate]，再限制到白名单支持的五个范围；用户规则
/// 不接受只有哈希的条目，UID 必须直接存在列表里。
String? validateAiWhitelistRule(FilterRule rule) {
  final error = rule.validate();
  if (error != null) return error;
  if (rule.isHashOnly) return '用户 UID 必须是正整数';
  for (final scope in rule.scopes) {
    if (!aiWhitelistScopes.contains(scope)) {
      return '白名单不能用于「${scope.label}」';
    }
  }
  return null;
}

/// 解析新存储键里的规则
///
/// 无法识别的项、重复 id 和不在白名单范围内的规则直接跳过；坏正则保留在
/// 列表里，由匹配器静默跳过。
List<FilterRule> whitelistRulesFromJson(Object? value) {
  final parsed = FilterRule.listFromJson(value);
  final result = <FilterRule>[];
  final ids = <String>{};
  for (final rule in parsed) {
    if (rule.isHashOnly) continue;
    final scopes = rule.scopes.intersection(aiWhitelistScopes);
    if (scopes.isEmpty) continue;
    final next = scopes.length == rule.scopes.length
        ? rule
        : rule.copyWith(scopes: scopes);
    if (ids.add(next.id)) result.add(next);
  }
  return result;
}

/// 把旧版白名单条目（id/type/content/enabled）转成新规则
///
/// 旧版只有关键词与正则，迁移后范围是全部五个适用面。
List<FilterRule> legacyAiWhitelistRules(Object? value) {
  if (value is! List) return const <FilterRule>[];
  final result = <FilterRule>[];
  final ids = <String>{};
  for (final item in value) {
    if (item is! Map) continue;
    final id = _stringOf(item['id']).trim();
    if (id.isEmpty) continue;
    final typeName = _stringOf(item['type']);
    final type = switch (typeName) {
      'keyword' => RuleType.keyword,
      'regex' => RuleType.regex,
      _ => null,
    };
    if (type == null) continue;
    final content = _stringOf(item['content']);
    if (content.trim().isEmpty) continue;
    final rawEnabled = item['enabled'];
    final rule = FilterRule(
      id: id,
      type: type,
      content: content,
      scopes: Set<RuleScope>.of(aiWhitelistScopes),
      enabled: rawEnabled is bool ? rawEnabled : true,
    );
    if (validateAiWhitelistRule(rule) != null) continue;
    if (ids.add(id)) result.add(rule);
  }
  return result;
}

/// 白名单的纯逻辑存储，读写由调用方注入
///
/// 首次读取时若新键为空而旧键有数据，就把旧条目迁到新键并清掉旧键；
/// 此后不再读取旧键。
class AiWhitelistStore {
  AiWhitelistStore({
    required this.read,
    required this.write,
    this.readLegacy,
    this.clearLegacy,
    this.onChanged,
  });

  /// 读取新键，坏数据应返回空列表
  final List<FilterRule> Function() read;

  /// 写入新键
  final void Function(List<FilterRule> rules) write;

  /// 读取旧键并转成新规则
  final List<FilterRule> Function()? readLegacy;

  /// 迁移完成后清掉旧键
  final void Function()? clearLegacy;

  /// 数据变化后的回调，用于自增版本
  final void Function()? onChanged;

  List<FilterRule>? _cached;

  /// 当前规则，首次访问时顺带完成迁移
  List<FilterRule> get rules => _cached ??= _load();

  List<FilterRule> _load() {
    final stored = read();
    if (stored.isEmpty) {
      final legacy = readLegacy?.call() ?? const <FilterRule>[];
      if (legacy.isNotEmpty) {
        write(legacy);
        clearLegacy?.call();
        return legacy;
      }
    }
    // 新键已经有数据或旧键本来就不存在，之后都不再读旧键
    clearLegacy?.call();
    return stored;
  }

  /// 校验并添加，重复规则合并范围或忽略；有变化时返回 true
  bool add(FilterRule rule) {
    final next = _checked(rule);
    final current = rules;
    final index = current.indexWhere(
      (item) => item.id == next.id || _sameIdentity(item, next),
    );
    if (index >= 0) {
      final old = current[index];
      final scopes = <RuleScope>{...old.scopes, ...next.scopes};
      if (_sameScopes(old.scopes, scopes)) return false;
      final updated = <FilterRule>[...current];
      updated[index] = old.copyWith(scopes: scopes);
      _persist(updated);
      return true;
    }
    _persist(<FilterRule>[...current, next]);
    return true;
  }

  /// 按 id 更新，规则不存在时抛 [ArgumentError]；有变化时返回 true
  bool update(FilterRule rule) {
    final next = _checked(rule);
    final current = rules;
    final index = current.indexWhere((item) => item.id == next.id);
    if (index < 0) {
      throw ArgumentError.value(next.id, 'id', '规则不存在');
    }
    final old = current[index];
    if (_sameRule(old, next) && old.enabled == next.enabled) return false;
    final updated = <FilterRule>[...current];
    updated[index] = next;
    _persist(updated);
    return true;
  }

  /// 按 id 删除，规则不存在时抛 [ArgumentError]
  bool remove(String id) {
    final current = rules;
    final updated = <FilterRule>[
      for (final rule in current)
        if (rule.id != id) rule,
    ];
    if (updated.length == current.length) {
      throw ArgumentError.value(id, 'id', '规则不存在');
    }
    _persist(updated);
    return true;
  }

  /// 按 id 启停，规则不存在时抛 [ArgumentError]；有变化时返回 true
  bool setEnabled(String id, bool enabled) {
    final current = rules;
    final index = current.indexWhere((rule) => rule.id == id);
    if (index < 0) {
      throw ArgumentError.value(id, 'id', '规则不存在');
    }
    if (current[index].enabled == enabled) return false;
    final updated = <FilterRule>[...current];
    updated[index] = current[index].copyWith(enabled: enabled);
    _persist(updated);
    return true;
  }

  /// 把整段文字当关键词加入，空文本返回 false
  ///
  /// [surface] 非空时范围只含该适用面，为空时范围是全部五个适用面。
  bool addKeywordFromText(String text, {FilterSurface? surface}) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    final scope = surface == null ? null : aiWhitelistScopeOf(surface);
    if (surface != null && scope == null) return false;
    return add(
      FilterRule(
        id: FilterRule.nextId(),
        type: RuleType.keyword,
        content: trimmed,
        scopes: scope == null
            ? Set<RuleScope>.of(aiWhitelistScopes)
            : <RuleScope>{scope},
      ),
    );
  }

  FilterRule _checked(FilterRule rule) {
    final next = rule.id.trim().isEmpty
        ? rule.copyWith(id: FilterRule.nextId())
        : rule;
    final error = validateAiWhitelistRule(next);
    if (error != null) throw ArgumentError.value(rule, 'rule', error);
    return next;
  }

  void _persist(List<FilterRule> rules) {
    write(rules);
    _cached = rules;
    onChanged?.call();
  }

  static bool _sameIdentity(FilterRule a, FilterRule b) =>
      a.type == b.type &&
      a.content == b.content &&
      (a.midHash ?? '') == (b.midHash ?? '');

  static bool _sameRule(FilterRule a, FilterRule b) =>
      _sameIdentity(a, b) && _sameScopes(a.scopes, b.scopes);

  static bool _sameScopes(Set<RuleScope> a, Set<RuleScope> b) =>
      a.length == b.length && a.containsAll(b);
}

/// 用启用的白名单规则编译出的匹配器
///
/// 文本规则按适用面编译，用户规则按适用面收集 UID；弹幕还额外收集
/// UID 派生的发送者哈希。
class AiWhitelistMatcher {
  AiWhitelistMatcher(Iterable<FilterRule> rules) {
    final list = List<FilterRule>.of(rules);
    for (final scope in aiWhitelistScopes) {
      _texts[scope] = RuleSet.text(list, scope);
      _mids[scope] = <int>{};
    }
    for (final rule in list) {
      if (!rule.enabled || rule.type != RuleType.user) continue;
      final mid = int.tryParse(rule.content);
      if (mid == null || mid <= 0) continue;
      for (final scope in rule.scopes) {
        if (!aiWhitelistScopes.contains(scope)) continue;
        _mids[scope]!.add(mid);
        if (scope == RuleScope.danmaku) {
          _hashes.add(FilterRule.midToHash(mid));
        }
      }
    }
  }

  final Map<RuleScope, RuleSet> _texts = <RuleScope, RuleSet>{};
  final Map<RuleScope, Set<int>> _mids = <RuleScope, Set<int>>{};
  final Set<String> _hashes = <String>{};

  /// 文字、UID 或弹幕哈希任一命中启用中的白名单即为 true
  bool matches({
    required FilterSurface surface,
    required String text,
    int? mid,
    String? midHash,
  }) {
    final scope = aiWhitelistScopeOf(surface);
    if (scope == null) return false;
    if (text.isNotEmpty && (_texts[scope]?.matchesText(text) ?? false)) {
      return true;
    }
    if (mid != null && mid > 0 && (_mids[scope]?.contains(mid) ?? false)) {
      return true;
    }
    if (scope == RuleScope.danmaku &&
        midHash != null &&
        midHash.isNotEmpty &&
        _hashes.contains(midHash.toLowerCase())) {
      return true;
    }
    return false;
  }
}

String _stringOf(Object? value) => value is String ? value : '';
