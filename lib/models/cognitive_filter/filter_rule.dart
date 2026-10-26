import 'dart:convert';

import 'package:PiliPlus/models/cognitive_filter/rule_scope.dart';
import 'package:PiliPlus/models/cognitive_filter/rule_type.dart';
import 'package:archive/archive.dart' show getCrc32;

/// 一条过滤规则
///
/// 用户 UID 规则由 `blackMids` 派生，不存进规则列表；只有「只有哈希、没有
/// UID」的弹幕用户规则完整存放在列表里，[midHash] 就是这种规则。
class FilterRule {
  const FilterRule({
    required this.id,
    required this.type,
    required this.content,
    required this.scopes,
    this.enabled = true,
    this.midHash,
  });

  /// 只有哈希的弹幕用户规则
  bool get isHashOnly =>
      type == RuleType.user &&
      content.isEmpty &&
      (midHash?.isNotEmpty ?? false);

  /// 以 UID 为内容的用户规则
  bool get isUidRule => type == RuleType.user && content.isNotEmpty;

  /// 规则 id，迁移与存储都靠它去重
  final String id;

  final RuleType type;

  /// 关键词、正则，或用户 UID 的十进制字符串
  final String content;

  /// 生效范围，非空且必须是 [type] 允许的子集
  final Set<RuleScope> scopes;

  final bool enabled;

  /// 仅用于只有哈希、没有 UID 的弹幕用户规则
  final String? midHash;

  /// 校验并给出中文错误说明，通过时返回 null
  String? validate() {
    if (id.trim().isEmpty) return '规则 id 不能为空';
    if (type == RuleType.user) {
      if (isHashOnly) {
        if (scopes.length != 1 || !scopes.contains(RuleScope.danmaku)) {
          return '只有哈希的用户规则只能用于弹幕';
        }
        return null;
      }
      if (content.isEmpty) return '内容不能为空';
      final mid = int.tryParse(content);
      if (mid == null || mid <= 0) return '用户 UID 必须是正整数';
      if (midHash != null && midHash!.isNotEmpty) {
        return '用户规则不能同时填写 UID 和哈希';
      }
    } else {
      if (content.isEmpty) return '内容不能为空';
      if (midHash != null && midHash!.isNotEmpty) {
        return '只有用户规则可以填写哈希';
      }
    }
    if (scopes.isEmpty) return '至少选择一个适用范围';
    for (final scope in scopes) {
      if (!type.allowedScopes.contains(scope)) {
        return '「${type.label}」规则不能用于「${scope.label}」';
      }
    }
    if (type == RuleType.regex) {
      try {
        RegExp(content, caseSensitive: false);
      } on FormatException catch (e) {
        return '正则表达式无法编译：${e.message}';
      }
    }
    return null;
  }

  static const Object _unset = Object();

  FilterRule copyWith({
    String? id,
    RuleType? type,
    String? content,
    Set<RuleScope>? scopes,
    bool? enabled,
    Object? midHash = _unset,
  }) {
    return FilterRule(
      id: id ?? this.id,
      type: type ?? this.type,
      content: content ?? this.content,
      scopes: scopes ?? this.scopes,
      enabled: enabled ?? this.enabled,
      midHash: identical(midHash, _unset)
          ? this.midHash
          : midHash as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'content': content,
    'scopes': [
      for (final scope in RuleScope.values)
        if (scopes.contains(scope)) scope.name,
    ],
    'enabled': enabled,
    if (midHash != null) 'midHash': midHash,
  };

  /// 缺字段、类型错误都按缺省值恢复，无法恢复时返回 null
  static FilterRule? fromJson(Object? value) {
    if (value is! Map) return null;
    final json = <String, dynamic>{};
    value.forEach((key, val) {
      if (key is String) json[key] = val;
    });

    final id = _stringOf(json['id']).trim();
    if (id.isEmpty) return null;
    final type = RuleType.byName(_stringOf(json['type']));
    if (type == null) return null;

    var content = _stringOf(json['content']);
    final contentTrimmed = content.trim();
    final rawMidHash = _stringOf(json['midHash']).trim();
    String? midHash = rawMidHash.isEmpty ? null : rawMidHash;
    final rawEnabled = json['enabled'];
    final enabled = rawEnabled is bool ? rawEnabled : true;

    Set<RuleScope> scopes;
    if (type == RuleType.user &&
        contentTrimmed.isEmpty &&
        midHash != null) {
      // 只有哈希的规则范围固定为弹幕
      scopes = {RuleScope.danmaku};
    } else {
      final rawScopes = json['scopes'];
      if (rawScopes is List) {
        scopes = _scopesOf(rawScopes).intersection(type.allowedScopes);
        if (scopes.isEmpty) return null;
      } else {
        // 缺字段时按该类型的全部范围恢复
        scopes = type.allowedScopes;
      }
    }

    if (type == RuleType.user) {
      if (contentTrimmed.isEmpty) {
        if (midHash == null) return null;
        return FilterRule(
          id: id,
          type: type,
          content: '',
          scopes: scopes,
          enabled: enabled,
          midHash: midHash,
        );
      }
      // UID 与哈希同时出现时以 UID 为准
      final mid = int.tryParse(contentTrimmed);
      if (mid == null || mid <= 0) return null;
      content = contentTrimmed;
      midHash = null;
    } else {
      midHash = null;
      if (content.isEmpty) return null;
    }

    return FilterRule(
      id: id,
      type: type,
      content: content,
      scopes: scopes,
      enabled: enabled,
      midHash: midHash,
    );
  }

  /// 解析规则列表，无法识别的项和重复 id 直接跳过
  static List<FilterRule> listFromJson(Object? value) {
    if (value is! List) return const <FilterRule>[];
    final result = <FilterRule>[];
    final ids = <String>{};
    for (final item in value) {
      final rule = fromJson(item);
      if (rule != null && ids.add(rule.id)) result.add(rule);
    }
    return result;
  }

  static String _stringOf(Object? value) => value is String ? value : '';

  static Set<RuleScope> _scopesOf(List<dynamic> value) {
    final result = <RuleScope>{};
    for (final item in value) {
      if (item is String) {
        final scope = RuleScope.byName(item);
        if (scope != null) result.add(scope);
      }
    }
    return result;
  }

  /// UID 规则在存储里没有独立记录，id 由 UID 直接派生
  static String userRuleId(int mid) => 'user-mid-$mid';

  /// 由类型、范围与内容生成稳定 id，重复迁移不会产生新 id
  static String stableId({
    required RuleType type,
    required Set<RuleScope> scopes,
    required String content,
    String? midHash,
  }) {
    final scopeNames = scopes.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    final payload =
        '${type.name}|${scopeNames.map((e) => e.name).join('+')}|'
        '$content|${midHash ?? ''}';
    final bytes = utf8.encode(payload);
    // 两个独立初值各取 32 位，拼成稳定的 64 位标识；CRC32 的入参是上一段
    // 校验值，因此 0 与 1 会得到不同结果，不能把 0xFFFFFFFF 当作“另一个种子”
    // （archive 内部会先异或掉它，结果与 0 相同）。
    final low = getCrc32(bytes, 0).toRadixString(16).padLeft(8, '0');
    final high = getCrc32(bytes, 1).toRadixString(16).padLeft(8, '0');
    return 'rule-${type.name}-$low$high';
  }

  static int _nextId = 0;

  /// 新建规则时使用的 id，只要求本次运行内不重复
  static String nextId() =>
      'rule-${DateTime.now().microsecondsSinceEpoch}-${_nextId++}';

  /// 用户 UID 对应的弹幕发送者哈希
  ///
  /// UID 十进制 ASCII 字节的 CRC32 小写十六进制，不补前导零；纯核心实现，
  /// 不依赖 canvas_danmaku。
  static String midToHash(int mid) =>
      getCrc32(ascii.encode(mid.toString()), 0).toRadixString(16);
}
