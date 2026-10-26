/// 白名单条目的类型
enum AiWhitelistType {
  keyword('关键词'),
  regex('正则');

  const AiWhitelistType(this.label);

  /// 界面显示的名称
  final String label;

  /// 由存储里的枚举名反查，未知名称返回 null
  static AiWhitelistType? byName(String name) => values.asNameMap()[name];
}

/// 一条 AI 屏蔽白名单
///
/// 命中白名单的文字不会送去 AI 判定，规则屏蔽不受影响
class AiWhitelistEntry {
  const AiWhitelistEntry({
    required this.id,
    required this.type,
    required this.content,
    this.enabled = true,
  });

  /// 条目 id，存储与界面刷新都靠它定位
  final String id;

  final AiWhitelistType type;

  /// 关键词或正则表达式
  final String content;

  final bool enabled;

  AiWhitelistEntry copyWith({
    String? id,
    AiWhitelistType? type,
    String? content,
    bool? enabled,
  }) {
    return AiWhitelistEntry(
      id: id ?? this.id,
      type: type ?? this.type,
      content: content ?? this.content,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'content': content,
    'enabled': enabled,
  };

  /// 缺字段、类型错误都按缺省值恢复，无法恢复时返回 null
  static AiWhitelistEntry? fromJson(Object? value) {
    try {
      if (value is! Map) return null;
      final id = _stringOf(value['id']).trim();
      if (id.isEmpty) return null;
      final type = AiWhitelistType.byName(_stringOf(value['type']));
      if (type == null) return null;
      final content = _stringOf(value['content']);
      if (content.trim().isEmpty) return null;
      final rawEnabled = value['enabled'];
      return AiWhitelistEntry(
        id: id,
        type: type,
        content: content,
        enabled: rawEnabled is bool ? rawEnabled : true,
      );
    } catch (_) {
      return null;
    }
  }

  /// 解析白名单列表，无法识别的项和重复 id 直接跳过
  static List<AiWhitelistEntry> listFromJson(Object? value) {
    if (value is! List) return const <AiWhitelistEntry>[];
    final result = <AiWhitelistEntry>[];
    final ids = <String>{};
    for (final item in value) {
      final entry = fromJson(item);
      if (entry != null && ids.add(entry.id)) result.add(entry);
    }
    return result;
  }

  static String _stringOf(Object? value) => value is String ? value : '';

  static int _nextId = 0;

  /// 新建白名单时使用的 id，只要求本次运行内不重复
  static String nextId() =>
      'whitelist-${DateTime.now().microsecondsSinceEpoch}-${_nextId++}';
}

/// 校验白名单内容，通过时返回 null，否则返回中文错误说明
String? validateAiWhitelistContent(AiWhitelistType type, String content) {
  if (content.trim().isEmpty) return '内容不能为空';
  if (type == AiWhitelistType.regex) {
    try {
      RegExp(content, caseSensitive: false);
    } on FormatException catch (e) {
      return '正则表达式无法编译：${e.message}';
    }
  }
  return null;
}

/// 用启用的条目编译出的匹配器
///
/// 关键词按原文做大小写不敏感的子串匹配，正则大小写不敏感；正则编译失败
/// 的条目静默跳过
class AiWhitelistMatcher {
  AiWhitelistMatcher(Iterable<AiWhitelistEntry> entries) {
    for (final entry in entries) {
      if (!entry.enabled || entry.content.isEmpty) continue;
      switch (entry.type) {
        case AiWhitelistType.keyword:
          _keywords.add(entry.content.toLowerCase());
          break;
        case AiWhitelistType.regex:
          try {
            _regexps.add(RegExp(entry.content, caseSensitive: false));
          } on FormatException {
            // 坏正则不影响其他条目
          }
          break;
      }
    }
  }

  final List<String> _keywords = <String>[];
  final List<RegExp> _regexps = <RegExp>[];

  /// 没有任何可用的启用条目
  bool get isEmpty => _keywords.isEmpty && _regexps.isEmpty;

  bool matches(String text) {
    if (text.isEmpty) return false;
    final lower = text.toLowerCase();
    for (final keyword in _keywords) {
      if (lower.contains(keyword)) return true;
    }
    for (final regexp in _regexps) {
      if (regexp.hasMatch(text)) return true;
    }
    return false;
  }
}
