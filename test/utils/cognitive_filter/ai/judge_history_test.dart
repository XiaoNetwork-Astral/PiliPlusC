import 'package:PiliPlus/utils/cognitive_filter/ai/judge_history.dart';
import 'package:flutter_test/flutter_test.dart';

String _repeat(String unit, int count) => List.filled(count, unit).join();

JudgeHistoryEntry _entry(
  String text, {
  String? categoryId,
  Map<String, double>? scores,
  Map<String, dynamic>? meta,
  Map<String, dynamic>? snapshot,
  String kind = JudgeHistoryEntry.ai,
}) {
  return JudgeHistoryEntry(
    time: DateTime.fromMillisecondsSinceEpoch(1700000000000),
    surface: '弹幕',
    text: text,
    categoryId: categoryId,
    score: 0.82,
    kind: kind,
    scores: scores,
    meta: meta,
    snapshot: snapshot,
  );
}

void main() {
  group('JudgeHistoryEntry', () {
    test('文本超过 2000 字时截断', () {
      final entry = _entry(_repeat('a', 2050));
      expect(entry.text.length, 2000);
      expect(entry.text, _repeat('a', 2000));
    });

    test('序列化往返保留字段', () {
      final entry = _entry(
        '测试文本',
        categoryId: 'attack',
        scores: const <String, double>{'攻击': 0.82, '正常': 0.18},
        meta: const <String, dynamic>{
          'type': 'danmaku',
          'videoTitle': '标题',
          'progressMs': 1234,
        },
        snapshot: const <String, dynamic>{
          'reply': 'c29tZQ==',
          'nested': <String, dynamic>{'ok': true},
        },
      );
      final restored = JudgeHistoryEntry.fromJson(entry.toJson());

      expect(
        restored.time.millisecondsSinceEpoch,
        entry.time.millisecondsSinceEpoch,
      );
      expect(restored.surface, '弹幕');
      expect(restored.text, '测试文本');
      expect(restored.categoryId, 'attack');
      expect(restored.score, 0.82);
      expect(restored.scores, entry.scores);
      expect(restored.meta, entry.meta);
      expect(restored.snapshot, entry.snapshot);
    });

    test('缺字段时按缺省值处理', () {
      final entry = JudgeHistoryEntry.fromJson(const <String, dynamic>{});
      expect(entry.time.millisecondsSinceEpoch, 0);
      expect(entry.surface, '');
      expect(entry.text, '');
      expect(entry.categoryId, isNull);
      expect(entry.score, 0);
      expect(entry.scores, isNull);
      expect(entry.meta, isNull);
      expect(entry.snapshot, isNull);
    });

    test('旧数据没有新字段也能读取', () {
      final entry = JudgeHistoryEntry.fromJson(const <String, dynamic>{
        'time': 1700000000000,
        'surface': '评论',
        'text': '旧记录',
        'score': 0.5,
        'kind': 'ai',
        'label': '攻击',
      });
      expect(entry.text, '旧记录');
      expect(entry.surface, '评论');
      expect(entry.label, '攻击');
      expect(entry.scores, isNull);
      expect(entry.meta, isNull);
      expect(entry.snapshot, isNull);
    });

    test('新字段类型不对时按缺省值处理', () {
      final entry = JudgeHistoryEntry.fromJson(const <String, dynamic>{
        'scores': 'bad',
        'meta': 1,
        'snapshot': <dynamic>['bad'],
      });
      expect(entry.scores, isNull);
      expect(entry.meta, isNull);
      expect(entry.snapshot, isNull);
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
        ..add(
          _entry(
            '第一条',
            categoryId: 'mock',
            scores: const <String, double>{'嘲讽': 0.7},
            meta: const <String, dynamic>{'type': 'reply'},
            snapshot: const <String, dynamic>{'reply': 'YQ=='},
          ),
        )
        ..add(_entry('第二条'));
      final raw = history.toJson();
      expect(history.dirty, isTrue);

      final restored = JudgeHistory(capacity: 3)..loadJson(raw);

      expect(restored.dirty, isFalse);
      expect(restored.entries.length, 2);
      expect(restored.entries.first.text, '第二条');
      expect(restored.entries.last.text, '第一条');
      expect(restored.entries.last.categoryId, 'mock');
      expect(restored.entries.last.scores, history.entries.last.scores);
      expect(restored.entries.last.meta, history.entries.last.meta);
      expect(restored.entries.last.snapshot, history.entries.last.snapshot);
    });

    test('只保留最近 100 条 AI 条目的快照', () {
      final history = JudgeHistory(capacity: 300);
      for (var i = 1; i <= 105; i++) {
        history.add(
          _entry(
            '$i',
            scores: const <String, double>{'攻击': 0.9},
            meta: <String, dynamic>{'type': 'reply', 'rpid': i},
            snapshot: <String, dynamic>{'reply': '$i'},
          ),
        );
      }

      final entries = history.entries;
      expect(entries.length, 105);
      expect(entries.take(100).every((entry) => entry.snapshot != null), isTrue);
      expect(entries.skip(100).every((entry) => entry.snapshot == null), isTrue);
      // meta 与 scores 一直保留
      expect(entries.every((entry) => entry.meta != null), isTrue);
      expect(entries.every((entry) => entry.scores != null), isTrue);
    });

    test('规则条目与 AI 条目各自有快照窗口', () {
      final history = JudgeHistory(capacity: 300);
      for (var i = 1; i <= 100; i++) {
        history.add(
          _entry('ai$i', snapshot: <String, dynamic>{'reply': '$i'}),
        );
      }
      for (var i = 1; i <= 105; i++) {
        history.add(
          _entry(
            'rule$i',
            kind: JudgeHistoryEntry.rule,
            snapshot: <String, dynamic>{'reply': 'r$i'},
          ),
        );
      }

      int count(bool rule) => history.entries
          .where((entry) => entry.isRule == rule && entry.snapshot != null)
          .length;
      expect(count(false), 100);
      expect(count(true), 100);
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
