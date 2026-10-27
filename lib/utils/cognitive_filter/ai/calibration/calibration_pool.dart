import 'dart:convert';

import 'package:PiliPlus/utils/cognitive_filter/ai/calibration/calibration_models.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/judge_cache.dart';

/// 平时静默收集的高分内容池，供校准向导取样本
///
/// 池满后暂停收集，不淘汰旧内容；同一段规范化文字只保留一条，重复命中时
/// 只在新的得分更高时更新得分。落盘格式带版本号，未知版本按空池处理。
class CalibrationPool {
  CalibrationPool({
    required JudgeCacheStore store,
    required this.isBlockedForUpload,
    this.capacity = 400,
    this.minScore = 0.5,
    DateTime Function()? now,
  }) : _store = store,
       _now = now ?? DateTime.now;

  /// 落盘格式版本，结构为 `{"v":1,"next":N,"items":[...]}`。
  static const int _version = 1;

  final JudgeCacheStore _store;

  /// 不外传判定，返回 true 的内容不进入池
  final bool Function(String text) isBlockedForUpload;

  /// 池容量上限，达到后不再收新内容
  final int capacity;

  /// 进入池的最低得分
  final double minScore;

  final DateTime Function() _now;

  /// 键是规范化后的文字，值保持插入顺序，便于生成只读副本
  final Map<String, PoolItem> _items = <String, PoolItem>{};

  int _next = 1;
  bool _dirty = false;

  int get length => _items.length;

  bool get isFull => _items.length >= capacity;

  /// 同一来源在池里最多留多少条，约为容量的十分之一
  int get maxPerSource => capacity < 100 ? 10 : capacity ~/ 10;

  int _sourceCount(String source) {
    var count = 0;
    for (final item in _items.values) {
      if (item.source == source) count++;
    }
    return count;
  }

  /// 池内条目的只读副本
  List<PoolItem> get items => List<PoolItem>.unmodifiable(_items.values);

  /// 读取并恢复收集池；内容损坏、为空或版本未知时当作空池，不抛异常
  Future<void> load() async {
    try {
      final raw = await _store.read();
      if (raw == null || raw.trim().isEmpty) {
        _reset();
        return;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['v'] != _version) {
        _reset();
        return;
      }
      final rawItems = decoded['items'];
      if (rawItems is! List) {
        _reset();
        return;
      }
      final loaded = <String, PoolItem>{};
      for (final value in rawItems) {
        if (value is! Map) {
          continue;
        }
        try {
          final item = PoolItem.fromJson(Map<String, dynamic>.from(value));
          if (!item.score.isFinite) {
            continue;
          }
          loaded[flattenText(item.text)] = item;
        } catch (_) {
          // 单条损坏只丢弃该条
        }
      }
      final rawNext = decoded['next'];
      var next = rawNext is int && rawNext > 0 ? rawNext : 1;
      for (final item in loaded.values) {
        final id = int.tryParse(item.id);
        if (id != null && id >= next) {
          next = id + 1;
        }
      }
      _items
        ..clear()
        ..addAll(loaded);
      _next = next;
      _dirty = false;
    } catch (_) {
      _reset();
    }
  }

  /// 有改动时把收集池写入 store
  Future<void> flush() async {
    if (!_dirty) {
      return;
    }
    await _store.write(
      jsonEncode(<String, dynamic>{
        'v': _version,
        'next': _next,
        'items': <dynamic>[
          for (final item in _items.values) item.toJson(),
        ],
      }),
    );
    _dirty = false;
  }

  /// 尝试收集一条内容；真正新增时返回 true
  bool add({
    required String text,
    required String surface,
    required double score,
    String category = '',
    String categoryId = '',
    String source = '',
  }) {
    final normalized = flattenText(text);
    if (normalized.isEmpty) {
      return false;
    }
    if (!score.isFinite || score < minScore) {
      return false;
    }
    if (isBlockedForUpload(normalized)) {
      return false;
    }

    final existing = _items[normalized];
    if (existing != null) {
      if (score > existing.score) {
        _items[normalized] = PoolItem(
          id: existing.id,
          text: normalized,
          surface: existing.surface,
          score: score,
          time: existing.time,
          category: category.isEmpty ? existing.category : category,
          categoryId: categoryId.isEmpty ? existing.categoryId : categoryId,
          source: existing.source,
        );
        _dirty = true;
      }
      return false;
    }

    if (isFull) {
      return false;
    }
    // 同一来源最多占池容量的一小部分，免得一个视频把池填满
    final key = flattenText(source);
    if (key.isNotEmpty && _sourceCount(key) >= maxPerSource) {
      return false;
    }

    final id = _next.toString();
    _next++;
    _items[normalized] = PoolItem(
      id: id,
      text: normalized,
      surface: surface,
      score: score,
      time: _now().millisecondsSinceEpoch,
      category: category,
      categoryId: categoryId,
      source: key,
    );
    _dirty = true;
    return true;
  }

  /// 按 id 删除条目
  void removeIds(Iterable<String> ids) {
    final targets = ids.toSet();
    if (targets.isEmpty) {
      return;
    }
    final keys = <String>[
      for (final entry in _items.entries)
        if (targets.contains(entry.value.id)) entry.key,
    ];
    if (keys.isEmpty) {
      return;
    }
    for (final key in keys) {
      _items.remove(key);
    }
    _dirty = true;
  }

  /// 清空收集池
  void clear() {
    if (_items.isEmpty) {
      return;
    }
    _items.clear();
    _dirty = true;
  }

  void _reset() {
    _items.clear();
    _next = 1;
    _dirty = false;
  }
}
