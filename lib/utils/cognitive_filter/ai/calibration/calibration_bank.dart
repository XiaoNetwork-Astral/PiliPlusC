import 'dart:convert';

import 'package:PiliPlus/utils/cognitive_filter/ai/calibration/calibration_models.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/judge_cache.dart';

/// 已整理好、还没答的题目，供校准向导直接取题
///
/// 按加入先后保存，取题不删除，答完后按题目编号精确删除；落盘格式带版本号，
/// 坏文件或未知版本按空题库处理
class CalibrationBank {
  CalibrationBank({required JudgeCacheStore store}) : _store = store;

  /// 落盘格式版本，结构为 `{"v":1,"questions":[...]}`
  static const int _version = 1;

  final JudgeCacheStore _store;

  /// 保持加入顺序，取题时按这个顺序取最早的
  final List<CalibrationQuestion> _questions = <CalibrationQuestion>[];

  bool _dirty = false;

  int get length => _questions.length;

  /// 题库内题目的只读副本，按加入先后排列
  List<CalibrationQuestion> get questions =>
      List<CalibrationQuestion>.unmodifiable(_questions);

  /// 读取并恢复题库；内容损坏、为空或版本未知时当作空题库，不抛异常
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
      final rawQuestions = decoded['questions'];
      if (rawQuestions is! List) {
        _reset();
        return;
      }
      final loaded = <CalibrationQuestion>[];
      for (final value in rawQuestions) {
        if (value is! Map) {
          continue;
        }
        try {
          loaded.add(
            CalibrationQuestion.fromJson(Map<String, dynamic>.from(value)),
          );
        } catch (_) {
          // 单条损坏只丢弃该题
        }
      }
      _questions
        ..clear()
        ..addAll(loaded);
      _dirty = false;
    } catch (_) {
      _reset();
    }
  }

  /// 有改动时把题库写入 store
  Future<void> flush() async {
    if (!_dirty) {
      return;
    }
    await _store.write(
      jsonEncode(<String, dynamic>{
        'v': _version,
        'questions': <dynamic>[
          for (final question in _questions) question.toJson(),
        ],
      }),
    );
    _dirty = false;
  }

  /// 把整理好的题目按顺序加入题库
  void add(List<CalibrationQuestion> questions) {
    if (questions.isEmpty) {
      return;
    }
    _questions.addAll(questions);
    _dirty = true;
  }

  /// 按加入先后取最早的至多 [count] 道题，不删除
  List<CalibrationQuestion> take(int count) {
    if (count <= 0 || _questions.isEmpty) {
      return const <CalibrationQuestion>[];
    }
    return _questions.take(count).toList(growable: false);
  }

  /// 删除已经答过的题，按题目编号精确匹配
  void removeAnswered(Iterable<CalibrationQuestion> answered) {
    final ids = <String>{for (final question in answered) question.id};
    if (ids.isEmpty) {
      return;
    }
    final before = _questions.length;
    _questions.removeWhere((question) => ids.contains(question.id));
    if (_questions.length != before) {
      _dirty = true;
    }
  }

  /// 清空题库
  void clear() {
    if (_questions.isEmpty) {
      return;
    }
    _questions.clear();
    _dirty = true;
  }

  void _reset() {
    _questions.clear();
    _dirty = false;
  }
}
