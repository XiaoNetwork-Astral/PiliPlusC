import 'package:PiliPlus/models/cognitive_filter/filter_rule.dart';
import 'package:PiliPlus/models/cognitive_filter/rule_scope.dart';
import 'package:PiliPlus/models/cognitive_filter/rule_type.dart';

/// 旧设置里的一条拆分结果，只会是关键词或正则
class LegacySegment {
  const LegacySegment(this.type, this.content);

  final RuleType type;

  final String content;

  @override
  bool operator ==(Object other) =>
      other is LegacySegment && other.type == type && other.content == content;

  @override
  int get hashCode => Object.hash(type, content);

  @override
  String toString() => 'LegacySegment(${type.name}, $content)';
}

/// 旧设置的纯数据快照，由存储层读取后传入
class LegacyRuleSource {
  const LegacyRuleSource({
    this.replyPattern = '',
    this.dynamicPattern = '',
    this.videoPattern = '',
    this.zonePattern = '',
    this.danmakuKeywords = const <String>[],
    this.danmakuRegexps = const <String>[],
    this.danmakuUidHashes = const <String>{},
  });

  /// 旧评论关键词，竖线分隔
  final String replyPattern;

  /// 旧动态关键词，竖线分隔
  final String dynamicPattern;

  /// 旧视频标题关键词，竖线分隔
  final String videoPattern;

  /// 旧视频分区关键词，整串是正则
  final String zonePattern;

  /// 旧弹幕关键词
  final List<String> danmakuKeywords;

  /// 旧弹幕正则
  final List<String> danmakuRegexps;

  /// 旧弹幕用户哈希
  final Set<String> danmakuUidHashes;

  bool get isEmpty =>
      replyPattern.trim().isEmpty &&
      dynamicPattern.trim().isEmpty &&
      videoPattern.trim().isEmpty &&
      zonePattern.trim().isEmpty &&
      danmakuKeywords.isEmpty &&
      danmakuRegexps.isEmpty &&
      danmakuUidHashes.isEmpty;
}

/// 按顶层竖线拆分旧设置串
///
/// 只在 `()`、`[]` 之外、且不是 `\|` 的位置拆。每段若只含普通字符和被反斜杠
/// 转义的字面字符，就还原转义后作为关键词；否则作为正则。任一段正则编译失败
/// 时放弃拆分，把整串作为一条正则。
List<LegacySegment> splitLegacyPattern(String pattern) {
  final whole = pattern.trim();
  if (whole.isEmpty) return const <LegacySegment>[];

  final result = <LegacySegment>[];
  final seen = <String>{};
  var regexFailed = false;
  for (final part in _splitTopLevel(whole)) {
    if (part.isEmpty) continue;
    final literal = _literalOf(part);
    if (literal != null) {
      if (seen.add('k\u0000$literal')) {
        result.add(LegacySegment(RuleType.keyword, literal));
      }
      continue;
    }
    if (!_compiles(part)) {
      regexFailed = true;
      break;
    }
    if (seen.add('r\u0000$part')) {
      result.add(LegacySegment(RuleType.regex, part));
    }
  }
  if (regexFailed) {
    return <LegacySegment>[LegacySegment(RuleType.regex, whole)];
  }
  return result;
}

/// 把旧设置映射成规则，id 稳定，重复调用结果一致
List<FilterRule> migrateLegacy(LegacyRuleSource source) {
  final result = <FilterRule>[];
  final seen = <String>{};

  void add(
    RuleType type,
    String content,
    Set<RuleScope> scopes, {
    String? midHash,
  }) {
    final rule = FilterRule(
      id: FilterRule.stableId(
        type: type,
        scopes: scopes,
        content: content,
        midHash: midHash,
      ),
      type: type,
      content: content,
      scopes: scopes,
      midHash: midHash,
    );
    if (seen.add(_semanticKey(rule))) result.add(rule);
  }

  void addPattern(String pattern, RuleScope scope) {
    for (final segment in splitLegacyPattern(pattern)) {
      add(segment.type, segment.content, {scope});
    }
  }

  addPattern(source.replyPattern, RuleScope.reply);
  addPattern(source.dynamicPattern, RuleScope.dynamic);
  addPattern(source.videoPattern, RuleScope.video);
  addPattern(source.zonePattern, RuleScope.zone);

  for (final keyword in source.danmakuKeywords) {
    if (keyword.isEmpty) continue;
    add(RuleType.keyword, keyword, const {RuleScope.danmaku});
  }
  for (final pattern in source.danmakuRegexps) {
    if (pattern.isEmpty) continue;
    add(RuleType.regex, pattern, const {RuleScope.danmaku});
  }
  for (final raw in source.danmakuUidHashes) {
    final hash = raw.trim().toLowerCase();
    if (hash.isEmpty) continue;
    add(RuleType.user, '', const {RuleScope.danmaku}, midHash: hash);
  }
  return result;
}

/// 合并已有规则与迁移结果，按 id 和语义去重
List<FilterRule> mergeMigrated(
  List<FilterRule> existing,
  Iterable<FilterRule> migrated,
) {
  final result = <FilterRule>[...existing];
  final ids = {for (final rule in existing) rule.id};
  final keys = {for (final rule in existing) _semanticKey(rule)};
  for (final rule in migrated) {
    if (!ids.add(rule.id)) continue;
    if (!keys.add(_semanticKey(rule))) continue;
    result.add(rule);
  }
  return result;
}

String _semanticKey(FilterRule rule) {
  final scopes = rule.scopes.toList()
    ..sort((a, b) => a.index.compareTo(b.index));
  return '${rule.type.name}|${scopes.map((e) => e.name).join('+')}|'
      '${rule.content}|${rule.midHash ?? ''}';
}

List<String> _splitTopLevel(String pattern) {
  final parts = <String>[];
  final buffer = StringBuffer();
  var parenDepth = 0;
  var inClass = false;
  var escaped = false;
  for (var i = 0; i < pattern.length; i++) {
    final char = pattern[i];
    if (escaped) {
      buffer.write(char);
      escaped = false;
      continue;
    }
    if (char == '\\') {
      buffer.write(char);
      escaped = true;
      continue;
    }
    if (inClass) {
      buffer.write(char);
      if (char == ']') inClass = false;
      continue;
    }
    if (char == '[') {
      inClass = true;
      buffer.write(char);
      continue;
    }
    if (char == '(') {
      parenDepth++;
      buffer.write(char);
      continue;
    }
    if (char == ')') {
      if (parenDepth > 0) parenDepth--;
      buffer.write(char);
      continue;
    }
    if (char == '|' && parenDepth == 0) {
      parts.add(buffer.toString());
      buffer.clear();
      continue;
    }
    buffer.write(char);
  }
  parts.add(buffer.toString());
  return parts;
}

String? _literalOf(String segment) {
  final buffer = StringBuffer();
  var i = 0;
  while (i < segment.length) {
    final code = segment.codeUnitAt(i);
    final char = String.fromCharCode(code);
    if (char == '\\') {
      if (i + 1 >= segment.length) return null;
      final next = segment.codeUnitAt(i + 1);
      if (!_isEscapedLiteral(next)) return null;
      buffer.writeCharCode(next);
      i += 2;
      continue;
    }
    if (_regexMeta.contains(char)) return null;
    buffer.write(char);
    i++;
  }
  return buffer.toString();
}

/// 正则元字符；未转义出现时说明这一段是正则
const String _regexMeta = r'\^$.*+?()[]{}|';

/// 反斜杠后是非字母数字的 ASCII 字符时，视为转义的字面字符
bool _isEscapedLiteral(int code) {
  if (code > 0x7F) return false;
  if ((code >= 0x30 && code <= 0x39) ||
      (code >= 0x41 && code <= 0x5A) ||
      (code >= 0x61 && code <= 0x7A) ||
      code == 0x5F) {
    return false;
  }
  return true;
}

bool _compiles(String pattern) {
  try {
    RegExp(pattern, caseSensitive: false);
    return true;
  } on FormatException {
    return false;
  }
}
