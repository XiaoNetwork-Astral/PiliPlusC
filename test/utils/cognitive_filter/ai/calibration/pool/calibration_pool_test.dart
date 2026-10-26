import 'dart:convert';

import 'package:PiliPlus/utils/cognitive_filter/ai/calibration/calibration_pool.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/judge_cache.dart';
import 'package:flutter_test/flutter_test.dart';

CalibrationPool _build(
  JudgeCacheStore store, {
  int capacity = 400,
  double minScore = 0.5,
  bool Function(String text)? blocked,
}) {
  return CalibrationPool(
    store: store,
    isBlockedForUpload: blocked ?? ((text) => false),
    capacity: capacity,
    minScore: minScore,
    now: () => DateTime.fromMillisecondsSinceEpoch(1700000000000),
  );
}

class _CountingStore implements JudgeCacheStore {
  _CountingStore();

  String? value;
  int writes = 0;

  @override
  Future<String?> read() => Future<String?>.value(value);

  @override
  Future<void> write(String json) {
    writes++;
    value = json;
    return Future<void>.value();
  }
}

void main() {
  group('收集与去重', () {
    test('规范化空白、按规范化文字去重并只升不降', () {
      final pool = _build(MemoryJudgeCacheStore());

      expect(
        pool.add(text: '  hello   world  ', surface: '动态', score: 0.6),
        isTrue,
      );
      expect(pool.length, 1);
      expect(pool.items.single.text, 'hello world');
      expect(pool.items.single.id, '1');

      expect(
        pool.add(text: 'hello world', surface: '动态', score: 0.5),
        isFalse,
      );
      expect(pool.length, 1);
      expect(pool.items.single.score, 0.6);

      expect(
        pool.add(text: 'hello\tworld', surface: '动态', score: 0.9),
        isFalse,
      );
      expect(pool.length, 1);
      expect(pool.items.single.score, 0.9);
      expect(pool.items.single.time, 1700000000000);
    });

    test('空文本、低分、不外传内容与满池都不收', () {
      final pool = _build(
        MemoryJudgeCacheStore(),
        capacity: 2,
        blocked: (text) => text.contains('blocked'),
      );

      expect(pool.add(text: '   ', surface: '动态', score: 0.9), isFalse);
      expect(pool.add(text: 'low', surface: '动态', score: 0.49), isFalse);
      expect(
        pool.add(text: 'blocked thing', surface: '动态', score: 0.9),
        isFalse,
      );
      expect(pool.add(text: 'first', surface: '动态', score: 0.5), isTrue);
      expect(pool.add(text: 'second', surface: '评论', score: 0.6), isTrue);

      expect(pool.isFull, isTrue);
      expect(pool.add(text: 'third', surface: '动态', score: 0.9), isFalse);
      expect(pool.length, 2);
      expect(
        pool.items.map((item) => item.text),
        <String>['first', 'second'],
      );
    });
  });

  group('持久化', () {
    test('落盘带版本号，加载后编号接着往后', () async {
      final store = MemoryJudgeCacheStore();
      final pool = _build(store);
      pool.add(text: 'one', surface: '动态', score: 0.6);
      pool.add(text: 'two', surface: '评论', score: 0.7);
      await pool.flush();

      final raw = jsonDecode(store.value!) as Map<String, dynamic>;
      expect(raw['v'], 1);
      expect(raw['next'], 3);
      expect((raw['items'] as List<dynamic>).length, 2);

      final restored = _build(store);
      await restored.load();
      expect(restored.length, 2);
      expect(restored.items.map((item) => item.id), <String>['1', '2']);

      expect(
        restored.add(text: 'three', surface: '动态', score: 0.8),
        isTrue,
      );
      expect(restored.items.last.id, '3');
    });

    test('没有改动时 flush 不写盘', () async {
      final store = _CountingStore();
      final pool = _build(store);

      await pool.load();
      await pool.flush();
      expect(store.writes, 0);

      pool.add(text: 'one', surface: '动态', score: 0.6);
      await pool.flush();
      expect(store.writes, 1);

      await pool.flush();
      expect(store.writes, 1);
    });

    test('损坏内容与未知版本按空池处理', () async {
      final broken = _build(MemoryJudgeCacheStore('{not json'));
      await broken.load();
      expect(broken.length, 0);

      final unknown = _build(
        MemoryJudgeCacheStore(
          jsonEncode(<String, dynamic>{'v': 2, 'next': 5, 'items': []}),
        ),
      );
      await unknown.load();
      expect(unknown.length, 0);
      expect(unknown.add(text: 'fresh', surface: '动态', score: 0.6), isTrue);
      expect(unknown.items.single.id, '1');
    });

    test('跳过损坏条目并校正下一编号', () async {
      final store = MemoryJudgeCacheStore(
        jsonEncode(<String, dynamic>{
          'v': 1,
          'next': 2,
          'items': <dynamic>[
            <String, dynamic>{
              'id': '9',
              'text': 'kept',
              'surface': '动态',
              'score': 0.6,
              'time': 1,
            },
            <String, dynamic>{'id': 'broken'},
          ],
        }),
      );
      final pool = _build(store);
      await pool.load();
      expect(pool.length, 1);
      expect(pool.add(text: 'next', surface: '动态', score: 0.7), isTrue);
      expect(pool.items.last.id, '10');
    });
  });

  test('removeIds 与 clear', () {
    final pool = _build(MemoryJudgeCacheStore());
    pool.add(text: 'a', surface: '动态', score: 0.6);
    pool.add(text: 'b', surface: '动态', score: 0.6);
    pool.add(text: 'c', surface: '动态', score: 0.6);

    pool.removeIds(<String>['1', '3', 'missing']);
    expect(pool.items.map((item) => item.text), <String>['b']);

    pool.clear();
    expect(pool.length, 0);
    expect(pool.isFull, isFalse);
  });
}
