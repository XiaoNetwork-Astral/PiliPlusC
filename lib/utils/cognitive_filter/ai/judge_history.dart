import 'dart:convert';

/// 一条被屏蔽内容的历史记录
class JudgeHistoryEntry {
  JudgeHistoryEntry({
    required this.time,
    required this.surface,
    required String text,
    this.categoryId,
    required this.score,
    required this.source,
    this.kind = ai,
    this.label = '',
    this.ruleType = '',
    this.ruleId,
    this.scores,
    this.meta,
    Map<String, dynamic>? snapshot,
  }) : text = _truncate(text),
       _snapshot = snapshot;

  /// 来源：AI 屏蔽
  static const String ai = 'ai';

  /// 来源：规则屏蔽
  static const String rule = 'rule';

  /// 文本最多保留的字数
  static const int maxTextLength = 2000;

  final DateTime time;
  final String surface;
  final String text;
  final String? categoryId;
  final double score;
  final String source;

  /// AI 判定的各选项概率，旧数据或规则屏蔽为空
  final Map<String, double>? scores;

  /// 原始内容的简单快照，键与值都是简单类型
  final Map<String, dynamic>? meta;

  Map<String, dynamic>? _snapshot;

  /// 可选的重快照，只有最近少量 AI 条目保留
  Map<String, dynamic>? get snapshot => _snapshot;

  /// 快照超出保留窗口时置空
  void dropSnapshot() {
    _snapshot = null;
  }

  /// 屏蔽来源，`ai` 或 `rule`
  final String kind;

  /// AI 屏蔽是判定类别名，规则屏蔽是命中的规则内容，创建时记下，之后改名也不变
  final String label;

  /// 命中的规则类型名（关键词、正则、用户），仅规则屏蔽有
  final String ruleType;

  /// 命中的规则 id，仅规则屏蔽有
  final String? ruleId;

  bool get isRule => kind == rule;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'time': time.millisecondsSinceEpoch,
    'surface': surface,
    'text': text,
    if (categoryId != null) 'categoryId': categoryId,
    'score': score,
    'source': source,
    'kind': kind,
    'label': label,
    if (ruleType.isNotEmpty) 'ruleType': ruleType,
    if (ruleId != null) 'ruleId': ruleId,
    if (scores != null && scores!.isNotEmpty) 'scores': scores,
    if (meta != null && meta!.isNotEmpty) 'meta': meta,
    if (_snapshot != null) 'snapshot': _snapshot,
  };

  /// 缺字段、类型错误都按缺省值处理，不抛异常
  factory JudgeHistoryEntry.fromJson(Map<String, dynamic> json) {
    final rawTime = json['time'];
    final millis = rawTime is num ? rawTime.toInt() : 0;
    final rawScore = json['score'];
    final score = rawScore is num ? rawScore.toDouble() : 0.0;
    final categoryId = json['categoryId'];
    return JudgeHistoryEntry(
      time: DateTime.fromMillisecondsSinceEpoch(millis),
      surface: _stringOf(json['surface']),
      text: _stringOf(json['text']),
      categoryId: categoryId is String ? categoryId : null,
      score: score.isFinite ? score : 0.0,
      source: _stringOf(json['source']),
      kind: json['kind'] == rule ? rule : ai,
      label: _stringOf(json['label']),
      ruleType: _stringOf(json['ruleType']),
      ruleId: json['ruleId'] is String ? json['ruleId'] as String : null,
      scores: _scoresOf(json['scores']),
      meta: _mapOf(json['meta']),
      snapshot: _mapOf(json['snapshot']),
    );
  }

  static String _stringOf(Object? value) => value is String ? value : '';

  static Map<String, double>? _scoresOf(Object? value) {
    if (value is! Map) {
      return null;
    }
    final result = <String, double>{};
    value.forEach((key, item) {
      if (key is String && item is num && item.isFinite) {
        result[key] = item.toDouble();
      }
    });
    return result.isEmpty ? null : result;
  }

  static Map<String, dynamic>? _mapOf(Object? value) {
    if (value is! Map) {
      return null;
    }
    final result = <String, dynamic>{};
    value.forEach((key, item) {
      if (key is String) {
        result[key] = item;
      }
    });
    return result.isEmpty ? null : result;
  }

  static String _truncate(String text) {
    final runes = text.runes.toList(growable: false);
    if (runes.length <= maxTextLength) {
      return text;
    }
    return String.fromCharCodes(runes.take(maxTextLength));
  }
}

/// 屏蔽历史环形缓冲，最新在前
class JudgeHistory {
  JudgeHistory({this.capacity = 300}) : assert(capacity > 0);

  static const int _version = 1;

  /// 只保留最近这么多条 AI 条目的重快照
  static const int _snapshotWindow = 100;

  final int capacity;
  final List<JudgeHistoryEntry> _entries = <JudgeHistoryEntry>[];
  bool _dirty = false;

  /// 是否有尚未落盘的改动
  bool get dirty => _dirty;

  /// 历史记录，最新在前
  List<JudgeHistoryEntry> get entries =>
      List<JudgeHistoryEntry>.unmodifiable(_entries);

  void add(JudgeHistoryEntry entry) {
    _entries.insert(0, entry);
    while (_entries.length > capacity) {
      _entries.removeLast();
    }
    _trimSnapshots();
    _dirty = true;
  }

  /// 超出保留窗口的 AI 条目丢掉重快照，meta 与 scores 不动
  void _trimSnapshots() {
    var aiCount = 0;
    for (final entry in _entries) {
      if (entry.isRule) {
        continue;
      }
      aiCount++;
      if (aiCount > _snapshotWindow) {
        entry.dropSnapshot();
      }
    }
  }

  void clear() {
    _entries.clear();
    _dirty = true;
  }

  /// 标记已落盘
  void markClean() {
    _dirty = false;
  }

  /// 序列化为带版本号的 JSON 文本
  String toJson() => jsonEncode(<String, dynamic>{
    'version': _version,
    'entries': <Map<String, dynamic>>[
      for (final entry in _entries) entry.toJson(),
    ],
  });

  /// 从 JSON 文本恢复；解析失败或结构不对时当作空历史
  void loadJson(String raw) {
    _entries.clear();
    try {
      final decoded = jsonDecode(raw);
      final list = _entriesOf(decoded);
      if (list != null) {
        for (final item in list) {
          if (item is! Map) {
            continue;
          }
          final json = <String, dynamic>{};
          item.forEach((key, value) {
            if (key is String) {
              json[key] = value;
            }
          });
          _entries.add(JudgeHistoryEntry.fromJson(json));
        }
      }
    } catch (_) {
      _entries.clear();
    }
    if (_entries.length > capacity) {
      _entries.removeRange(capacity, _entries.length);
    }
    _trimSnapshots();
    _dirty = false;
  }

  static List<dynamic>? _entriesOf(Object? decoded) {
    if (decoded is List) {
      return decoded;
    }
    if (decoded is Map) {
      final entries = decoded['entries'];
      if (entries is List) {
        return entries;
      }
    }
    return null;
  }
}
