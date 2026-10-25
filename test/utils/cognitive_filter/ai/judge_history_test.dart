import 'package:PiliPlus/utils/cognitive_filter/ai/judge_history.dart';
import 'package:flutter_test/flutter_test.dart';

String _repeat(String unit, int count) => List.filled(count, unit).join();

JudgeHistoryEntry _entry(String text, {String? categoryId}) {
  return JudgeHistoryEntry(
    time: DateTime.fromMillisecondsSinceEpoch(1700000000000),
    surface: '弹幕',
    text: text,
    categoryId: categoryId,
    score: 0.82,
    source: 'ai',
  );
}

void main() {
  group('JudgeHistoryEntry', () {
    test('文本超过 200 字时截断', () {
      final entry = _entry(_repeat('a', 250));
      expect(entry.text.length, 200);
      expect(entry.text, _repeat('a', 200));
    });

    test('序列化往返保留字段', () {
      final entry = _entry('测试文本', categoryId: 'attack');
      final restored = JudgeHistoryEntry.fromJson(entry.toJson());

      expect(restored.time.millisecondsSinceEpoch, entry.time.millisecondsSinceEpoch);
      expect(restored.surface, '弹幕');
      expect(restored.text, '测试文本');
      expect(restored.categoryId, 'attack');
      expect(restored.score, 0.82);
      expect(restored.source, 'ai');
    });

    test('缺字段时按缺省值处理', () {
      final entry = JudgeHistoryEntry.fromJson(const <String, dynamic>{});
      expect(entry.time.millisecondsSinceEpoch, 0);
      expect(entry.surface, '');
      expect(entry.text, '');
      expect(entry.categoryId, isNull);
      expect(entry.score, 0);
      expect(entry.source, '');
    });
  });

  group('JudgeHistory', () {
    test('容量裁剪掉最旧的记录', () {
      final history = JudgeHistory(capacity: 3);
      for (var i = 1; i <= 5; i++) {
        history.add(_entry('$i'));
      }

      expect(history.entries.length, 3);
      expect(history.entries.map((entry) => entry.text), ['5', '4', '3']);
    });

    test('最新记录在前', () {
      final history = JudgeHistory();
      history.add(_entry('旧'));
      history.add(_entry('新'));

      expect(history.entries.first.text, '新');
      expect(history.entries.last.text, '旧');
    });

    test('toJson/loadJson 往返', () {
      final history = JudgeHistory(capacity: 3)
        ..add(_entry('第一条', categoryId: 'mock'))
        ..add(_entry('第二条'));
      final raw = history.toJson();
      expect(history.dirty, isTrue);

      final restored = JudgeHistory(capacity: 3)..loadJson(raw);

      expect(restored.dirty, isFalse);
      expect(restored.entries.length, 2);
      expect(restored.entries.first.text, '第二条');
      expect(restored.entries.last.text, '第一条');
      expect(restored.entries.last.categoryId, 'mock');
      expect(restored.entries.last.source, 'ai');
    });

    test('坏 JSON 当作空历史', () {
      final history = JudgeHistory()..add(_entry('会被清空'));

      history.loadJson('{not json');

      expect(history.entries, isEmpty);
      expect(history.dirty, isFalse);
    });

    test('clear 清空并标记待落盘', () {
      final history = JudgeHistory()..add(_entry('内容'));

      history.clear();

      expect(history.entries, isEmpty);
      expect(history.dirty, isTrue);
    });
  });
}
