import 'dart:convert';

import 'package:PiliPlus/models/cognitive_filter/filter_category.dart';

/// 判定缓存的持久化接口，真正的文件/Hive 实现由调用方提供
abstract class JudgeCacheStore {
  Future<String?> read();

  Future<void> write(String json);
}

/// 测试用的内存缓存存储
class MemoryJudgeCacheStore implements JudgeCacheStore {
  MemoryJudgeCacheStore([this._value = '']);

  String? _value;

  /// 最近一次写入的内容，便于测试断言
  String? get value => _value;

  @override
  Future<String?> read() async => _value;

  @override
  Future<void> write(String json) async {
    _value = json;
  }
}

/// 一次缓存查询的结果，缺失的部分为 null / 空
class CacheHit {
  const CacheHit({required this.options, required this.scores});

  /// 八个固定选项的概率；没有可用内容时为 null
  final Map<String, double>? options;

  /// 通过指纹校验的自定义类别概率，键为类别 id
  final Map<String, double> scores;
}

class _ScoreEntry {
  const _ScoreEntry(this.score, this.fp);

  final double score;
  final String fp;
}

class _CacheEntry {
  _CacheEntry({
    required this.ts,
    Map<String, double>? options,
    Map<String, _ScoreEntry>? scores,
  }) : options = options ?? <String, double>{},
       scores = scores ?? <String, _ScoreEntry>{};

  int ts;

  /// 选项名（正常/攻击/…）到概率，与当前启用了哪些类别、阈值无关
  final Map<String, double> options;

  /// 自定义类别 id 到带指纹的概率
  final Map<String, _ScoreEntry> scores;
}

/// 判定分数缓存：容量与过期时间可调，按 LRU 淘汰，读取命中会刷新顺序
///
/// 选项概率不依赖用户启用的类别与阈值，因此改开关后仍可复用；但说明里的
/// 内置定义会变，所以键里并入内置定义指纹。自定义类别的答案按类别指纹
/// 单独校验。落盘版本变化时整份丢弃重建。
class JudgeCache {
  JudgeCache({
    required JudgeCacheStore store,
    this.capacity = 5000,
    this.ttl = const Duration(days: 7),
    DateTime Function()? now,
  }) : _store = store,
       _now = now ?? DateTime.now;

  /// 缓存格式版本，读取到不同版本时整份丢弃重建
  static const int _version = 2;

  final JudgeCacheStore _store;
  final int capacity;
  final Duration ttl;
  final DateTime Function() _now;

  /// Dart 的 Map 字面量保持插入顺序，正好用作 LRU 队列
  final Map<String, _CacheEntry> _entries = <String, _CacheEntry>{};

  bool _dirty = false;

  /// 是否有尚未写入 store 的改动
  bool get dirty => _dirty;

  /// 读取 store；解析失败或版本不匹配当作空缓存
  Future<void> load() async {
    try {
      final raw = await _store.read();
      if (raw == null || raw.trim().isEmpty) {
        _clear();
        return;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['version'] != _version) {
        _clear();
        return;
      }
      final rawEntries = decoded['entries'];
      if (rawEntries is! Map) {
        _clear();
        return;
      }
      final loaded = <String, _CacheEntry>{};
      rawEntries.forEach((key, value) {
        if (key is! String) {
          return;
        }
        final entry = _decodeEntry(value);
        if (entry != null) {
          loaded[key] = entry;
        }
      });
      _entries
        ..clear()
        ..addAll(loaded);
      _pruneExpired();
      _dirty = false;
    } catch (_) {
      _clear();
    }
  }

  /// 查缓存，只返回指纹仍匹配的自定义类别；没有可用内容时返回 null
  CacheHit? lookup(
    String key, {
    required List<FilterCategory> customCategories,
  }) {
    final entry = _entries[key];
    if (entry == null) {
      return null;
    }
    if (_isExpired(entry)) {
      _entries.remove(key);
      return null;
    }

    final options = entry.options.isEmpty
        ? null
        : Map<String, double>.from(entry.options);
    final scores = <String, double>{};
    for (final category in customCategories) {
      final score = entry.scores[category.id];
      if (score != null && score.fp == categoryFingerprint(category)) {
        scores[category.id] = score.score;
      }
    }
    if (options == null && scores.isEmpty) {
      _entries.remove(key);
      return null;
    }
    _touch(key);
    return CacheHit(options: options, scores: scores);
  }

  /// 写入八个选项的概率，保留已有的自定义类别答案
  void putOptions(String key, Map<String, double> options) {
    final entry = _entries.remove(key) ?? _CacheEntry(ts: 0);
    entry.ts = _now().millisecondsSinceEpoch;
    entry.options
      ..clear()
      ..addAll(<String, double>{
        for (final item in options.entries)
          if (item.value.isFinite) item.key: _clamp(item.value),
      });
    _entries[key] = entry;
    _dirty = true;
  }

  /// 写入自定义类别答案，只保存传入类别里存在的项
  void putCustomScores(
    String key,
    Map<String, double> scores,
    List<FilterCategory> categories,
  ) {
    final entry = _entries.remove(key) ?? _CacheEntry(ts: 0);
    entry.ts = _now().millisecondsSinceEpoch;
    for (final category in categories) {
      final score = scores[category.id];
      if (score == null) {
        continue;
      }
      entry.scores[category.id] = _ScoreEntry(
        _clamp(score),
        categoryFingerprint(category),
      );
    }
    _entries[key] = entry;
    _dirty = true;
  }

  /// 清空内存缓存并把空缓存落盘
  Future<void> clear() async {
    _entries.clear();
    _dirty = false;
    await _store.write(
      jsonEncode(<String, dynamic>{
        'version': _version,
        'entries': <String, dynamic>{},
      }),
    );
  }

  /// 清理过期项并按 LRU 裁到容量后写入 store
  Future<void> flush() async {
    _pruneExpired();
    if (capacity <= 0) {
      _entries.clear();
    } else {
      while (_entries.length > capacity) {
        _entries.remove(_entries.keys.first);
      }
    }
    final entries = <String, dynamic>{};
    _entries.forEach((key, entry) {
      entries[key] = _encodeEntry(entry);
    });
    await _store.write(
      jsonEncode(<String, dynamic>{'version': _version, 'entries': entries}),
    );
    _dirty = false;
  }

  /// 自定义类别指纹：name + question + trueCriteria + falseCriteria 的 FNV-1a
  static String categoryFingerprint(FilterCategory category) {
    return _hex(
      _fnv1a(
        '${category.name}${category.question}'
        '${category.trueCriteria}${category.falseCriteria}',
      ),
    );
  }

  /// 内置定义指纹：按 id 排序后拼接 question + trueCriteria + falseCriteria
  ///
  /// 只依赖字符串内容，跨运行稳定；定义变了指纹就变，旧缓存自然失效。
  static String builtinDefinitionsFingerprint(
    Iterable<FilterCategory> definitions,
  ) {
    final sorted = <FilterCategory>[...definitions]
      ..sort((a, b) => a.id.compareTo(b.id));
    final buffer = StringBuffer();
    for (final category in sorted) {
      buffer
        ..write(category.question)
        ..write(category.trueCriteria)
        ..write(category.falseCriteria);
    }
    return _hex(_fnv1a(buffer.toString()));
  }

  /// 判定缓存键：内置定义指纹 + 规范化文本，定义不同就不会互相命中
  static String cacheKey(String normalizedText, String builtinFingerprint) {
    return '$builtinFingerprint|$normalizedText';
  }

  void _touch(String key) {
    final entry = _entries.remove(key);
    if (entry != null) {
      _entries[key] = entry;
    }
  }

  void _pruneExpired() {
    _entries.removeWhere((_, entry) => _isExpired(entry));
  }

  void _clear() {
    _entries.clear();
    _dirty = false;
  }

  bool _isExpired(_CacheEntry entry) {
    final age = _now().millisecondsSinceEpoch - entry.ts;
    return age >= ttl.inMilliseconds;
  }

  Map<String, dynamic> _encodeEntry(_CacheEntry entry) {
    return <String, dynamic>{
      'ts': entry.ts,
      'options': <String, dynamic>{
        for (final item in entry.options.entries)
          item.key: _round2(item.value),
      },
      'scores': <String, dynamic>{
        for (final item in entry.scores.entries)
          item.key: <dynamic>[_round2(item.value.score), item.value.fp],
      },
    };
  }

  _CacheEntry? _decodeEntry(Object? value) {
    if (value is! Map) {
      return null;
    }
    final ts = value['ts'];
    if (ts is! num) {
      return null;
    }
    final options = <String, double>{};
    final rawOptions = value['options'];
    if (rawOptions is Map) {
      rawOptions.forEach((key, item) {
        if (key is! String || item is! num) {
          return;
        }
        final number = item.toDouble();
        if (!number.isFinite) {
          return;
        }
        options[key] = number.clamp(0.0, 1.0).toDouble();
      });
    }
    final scores = <String, _ScoreEntry>{};
    final rawScores = value['scores'];
    if (rawScores is Map) {
      rawScores.forEach((key, item) {
        if (key is! String || item is! List || item.length < 2) {
          return;
        }
        final score = item[0];
        final fp = item[1];
        if (score is! num || fp is! String) {
          return;
        }
        final number = score.toDouble();
        if (!number.isFinite) {
          return;
        }
        scores[key] = _ScoreEntry(
          number.clamp(0.0, 1.0).toDouble(),
          fp,
        );
      });
    }
    return _CacheEntry(ts: ts.toInt(), options: options, scores: scores);
  }

  static double _clamp(double value) {
    if (!value.isFinite) {
      return 0.0;
    }
    return value.clamp(0.0, 1.0).toDouble();
  }

  static double _round2(double value) {
    return (_clamp(value) * 100).round() / 100;
  }

  static String _hex(int value) => value.toRadixString(16).padLeft(8, '0');

  static int _fnv1a(String text) {
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(text)) {
      hash ^= byte;
      hash = _mul32(hash, 0x01000193);
    }
    return hash;
  }

  /// 只用 16 位分块做乘法，保证在 web 上也不丢精度
  static int _mul32(int a, int b) {
    final aLow = a & 0xffff;
    final aHigh = (a >> 16) & 0xffff;
    final bLow = b & 0xffff;
    final bHigh = (b >> 16) & 0xffff;
    final low = aLow * bLow;
    final middle = (aHigh * bLow + aLow * bHigh) & 0xffff;
    return (low + (middle << 16)) & 0xffffffff;
  }
}
