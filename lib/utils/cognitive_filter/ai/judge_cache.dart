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

/// 一次缓存查询的结果，缺失的部分为 null
class CacheHit {
  const CacheHit({required this.gate, required this.scores});

  final double? gate;
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
    required this.scores,
    this.gate,
    this.gateFp,
  });

  int ts;
  double? gate;
  String? gateFp;
  final Map<String, _ScoreEntry> scores;
}

/// 判定分数缓存：容量与过期时间可调，按 LRU 淘汰，读取命中会刷新顺序
class JudgeCache {
  JudgeCache({
    required JudgeCacheStore store,
    this.capacity = 5000,
    this.ttl = const Duration(days: 7),
    DateTime Function()? now,
  }) : _store = store,
       _now = now ?? DateTime.now;

  static const int _version = 1;

  final JudgeCacheStore _store;
  final int capacity;
  final Duration ttl;
  final DateTime Function() _now;

  /// Dart 的 Map 字面量保持插入顺序，正好用作 LRU 队列
  final Map<String, _CacheEntry> _entries = <String, _CacheEntry>{};

  bool _dirty = false;

  /// 是否有尚未写入 store 的改动
  bool get dirty => _dirty;

  /// 读取 store；解析失败当作空缓存
  Future<void> load() async {
    try {
      final raw = await _store.read();
      if (raw == null || raw.trim().isEmpty) {
        _entries.clear();
        _dirty = false;
        return;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        _entries.clear();
        _dirty = false;
        return;
      }
      // 兼容带 version/entries 外壳与直接以文字为键两种格式
      final rawEntries = decoded['entries'] is Map
          ? decoded['entries'] as Map
          : decoded;
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
      _entries.clear();
      _dirty = false;
    }
  }

  /// 查缓存，只返回指纹仍匹配的部分；没有可用内容时返回 null
  CacheHit? lookup(
    String key, {
    required List<FilterCategory> categories,
  }) {
    final entry = _entries[key];
    if (entry == null) {
      return null;
    }
    if (_isExpired(entry)) {
      _entries.remove(key);
      return null;
    }

    final gateFp = gateFingerprint(categories);
    final gate = entry.gate != null && entry.gateFp == gateFp
        ? entry.gate
        : null;
    final scores = <String, double>{};
    for (final category in categories) {
      final score = entry.scores[category.id];
      if (score != null && score.fp == categoryFingerprint(category)) {
        scores[category.id] = score.score;
      }
    }
    if (gate == null && scores.isEmpty) {
      _entries.remove(key);
      return null;
    }
    _touch(key);
    return CacheHit(gate: gate, scores: scores);
  }

  /// 写入总问题分数
  void putGate(
    String key,
    double score,
    List<FilterCategory> categories,
  ) {
    final entry = _entries.remove(key) ??
        _CacheEntry(ts: 0, scores: <String, _ScoreEntry>{});
    entry.ts = _now().millisecondsSinceEpoch;
    entry.gate = _clamp(score);
    entry.gateFp = gateFingerprint(categories);
    _entries[key] = entry;
    _dirty = true;
  }

  /// 写入逐类别分数，只保存传入类别里存在的项
  void putScores(
    String key,
    Map<String, double> scores,
    List<FilterCategory> categories,
  ) {
    final entry = _entries.remove(key) ??
        _CacheEntry(ts: 0, scores: <String, _ScoreEntry>{});
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

  /// 类别指纹：name + question + trueCriteria + falseCriteria 的 FNV-1a
  static String categoryFingerprint(FilterCategory category) {
    return _hex(
      _fnv1a(
        category.name +
            category.question +
            category.trueCriteria +
            category.falseCriteria,
      ),
    );
  }

  /// 总问题指纹：当前启用类别指纹排序后拼接再哈希
  static String gateFingerprint(List<FilterCategory> categories) {
    final fingerprints = <String>[
      for (final category in categories) categoryFingerprint(category),
    ]..sort();
    return _hex(_fnv1a(fingerprints.join()));
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

  bool _isExpired(_CacheEntry entry) {
    final age = _now().millisecondsSinceEpoch - entry.ts;
    return age >= ttl.inMilliseconds;
  }

  Map<String, dynamic> _encodeEntry(_CacheEntry entry) {
    return <String, dynamic>{
      'ts': entry.ts,
      if (entry.gate != null) 'gate': _round2(entry.gate!),
      if (entry.gateFp != null) 'gateFp': entry.gateFp,
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
    final rawGate = value['gate'];
    double? gate;
    if (rawGate is num) {
      final number = rawGate.toDouble();
      if (number.isFinite) {
        gate = number.clamp(0.0, 1.0).toDouble();
      }
    }
    final rawGateFp = value['gateFp'];
    final gateFp = rawGateFp is String ? rawGateFp : null;
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
    return _CacheEntry(
      ts: ts.toInt(),
      gate: gate,
      gateFp: gateFp,
      scores: scores,
    );
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
