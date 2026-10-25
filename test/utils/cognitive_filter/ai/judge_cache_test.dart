import 'dart:convert';

import 'package:PiliPlus/models/cognitive_filter/filter_category.dart';
import 'package:PiliPlus/models/cognitive_filter/filter_surface.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/judge_cache.dart';
import 'package:flutter_test/flutter_test.dart';

FilterCategory _category(
  String id, {
  String name = '测试',
  String question = '是否属于测试类别？',
  String trueCriteria = '算作是',
  String falseCriteria = '算作否',
}) {
  return FilterCategory(
    id: id,
    name: name,
    summary: '合成类别',
    question: question,
    trueCriteria: trueCriteria,
    falseCriteria: falseCriteria,
    threshold: 0.7,
    enabled: true,
    surfaces: const {FilterSurface.danmaku},
    builtin: false,
  );
}

void main() {
  final categoryA = _category('a');
  final categoryB = _category(
    'b',
    name: '另一个',
    question: '是否属于另一个类别？',
  );

  group('指纹', () {
    test('类别指纹是稳定的 FNV-1a 8 位十六进制', () {
      expect(JudgeCache.categoryFingerprint(categoryA), 'c589b2a2');
      expect(JudgeCache.categoryFingerprint(categoryB), '47ab4e46');
    });

    test('总问题指纹与类别顺序无关', () {
      expect(
        JudgeCache.gateFingerprint(<FilterCategory>[categoryA, categoryB]),
        '795f82f2',
      );
      expect(
        JudgeCache.gateFingerprint(<FilterCategory>[categoryB, categoryA]),
        '795f82f2',
      );
      expect(
        JudgeCache.gateFingerprint(<FilterCategory>[categoryA]),
        '1f7794dd',
      );
    });

    test('题面变化后指纹变化', () {
      final changed = _category('a', question: '换了题面？');
      expect(
        JudgeCache.categoryFingerprint(changed),
        isNot(JudgeCache.categoryFingerprint(categoryA)),
      );
      expect(
        JudgeCache.gateFingerprint(<FilterCategory>[changed]),
        isNot(JudgeCache.gateFingerprint(<FilterCategory>[categoryA])),
      );
    });
  });

  group('读写与 LRU', () {
    test('putGate / putScores 后 lookup 返回对应值并置 dirty', () {
      final cache = JudgeCache(store: MemoryJudgeCacheStore());
      cache.putGate('k', 0.9, <FilterCategory>[categoryA]);
      cache.putScores('k', <String, double>{'a': 0.8}, <FilterCategory>[
        categoryA,
      ]);
      expect(cache.dirty, isTrue);
      final hit = cache.lookup('k', categories: <FilterCategory>[categoryA]);
      expect(hit, isNotNull);
      expect(hit!.gate, 0.9);
      expect(hit.scores, <String, double>{'a': 0.8});
    });

    test('分数序列化保留两位小数', () async {
      final store = MemoryJudgeCacheStore();
      final cache = JudgeCache(store: store);
      cache.putGate('k', 0.836, <FilterCategory>[categoryA]);
      cache.putScores('k', <String, double>{'a': 0.126}, <FilterCategory>[
        categoryA,
      ]);
      // 内存里保留原始精度，写盘时才取两位小数
      expect(
        cache.lookup('k', categories: <FilterCategory>[categoryA])!.gate,
        0.836,
      );
      await cache.flush();

      final loaded = JudgeCache(store: store);
      await loaded.load();
      final hit = loaded.lookup('k', categories: <FilterCategory>[categoryA]);
      expect(hit!.gate, 0.84);
      expect(hit.scores['a'], 0.13);
    });

    test('flush 前按 LRU 淘汰，读取命中会刷新顺序', () async {
      final cache = JudgeCache(
        store: MemoryJudgeCacheStore(),
        capacity: 2,
      );
      cache.putGate('a', 0.5, <FilterCategory>[categoryA]);
      cache.putGate('b', 0.6, <FilterCategory>[categoryA]);
      // 读取 a 刷新顺序，a 变成最新，b 是最旧
      expect(
        cache.lookup('a', categories: <FilterCategory>[categoryA]),
        isNotNull,
      );
      cache.putGate('c', 0.7, <FilterCategory>[categoryA]);
      await cache.flush();
      expect(
        cache.lookup('b', categories: <FilterCategory>[categoryA]),
        isNull,
      );
      expect(
        cache.lookup('a', categories: <FilterCategory>[categoryA]),
        isNotNull,
      );
      expect(
        cache.lookup('c', categories: <FilterCategory>[categoryA]),
        isNotNull,
      );
    });

    test('计数超出容量时淘汰最旧项', () async {
      final store = MemoryJudgeCacheStore();
      final cache = JudgeCache(
        store: store,
        capacity: 2,
      );
      for (var i = 0; i < 5; i++) {
        cache.putGate('k$i', 0.5, <FilterCategory>[categoryA]);
      }
      await cache.flush();
      final loaded = JudgeCache(
        store: store,
        capacity: 2,
      );
      await loaded.load();
      expect(
        loaded.lookup('k3', categories: <FilterCategory>[categoryA]),
        isNotNull,
      );
      expect(
        loaded.lookup('k4', categories: <FilterCategory>[categoryA]),
        isNotNull,
      );
      expect(
        loaded.lookup('k0', categories: <FilterCategory>[categoryA]),
        isNull,
      );
    });
  });

  group('过期', () {
    test('超过 ttl 后 lookup 失效并在 flush 时清理', () async {
      var now = DateTime(2026);
      final store = MemoryJudgeCacheStore();
      final cache = JudgeCache(
        store: store,
        ttl: const Duration(days: 7),
        now: () => now,
      );
      cache.putGate('old', 0.5, <FilterCategory>[categoryA]);
      cache.putGate('new', 0.5, <FilterCategory>[categoryA]);
      now = now.add(const Duration(days: 8));
      cache.putGate('new', 0.6, <FilterCategory>[categoryA]);
      expect(
        cache.lookup('old', categories: <FilterCategory>[categoryA]),
        isNull,
      );
      await cache.flush();
      final decoded = jsonDecode(store.value!) as Map<String, dynamic>;
      final entries = decoded['entries'] as Map<String, dynamic>;
      expect(entries.containsKey('old'), isFalse);
      expect(entries.containsKey('new'), isTrue);
    });
  });

  group('指纹失效', () {
    test('类别题面变化后只丢弃该类别与总问题分数', () {
      final cache = JudgeCache(store: MemoryJudgeCacheStore());
      cache.putGate('k', 0.9, <FilterCategory>[categoryA, categoryB]);
      cache.putScores(
        'k',
        <String, double>{'a': 0.8, 'b': 0.7},
        <FilterCategory>[categoryA, categoryB],
      );

      final changedB = _category(
        'b',
        name: '另一个',
        question: '换了题面？',
      );
      final hit = cache.lookup(
        'k',
        categories: <FilterCategory>[categoryA, changedB],
      );
      expect(hit, isNotNull);
      expect(hit!.gate, isNull);
      expect(hit.scores, <String, double>{'a': 0.8});
    });

    test('启用类别集合变化后总问题分数失效', () {
      final cache = JudgeCache(store: MemoryJudgeCacheStore());
      cache.putGate('k', 0.9, <FilterCategory>[categoryA, categoryB]);
      cache.putScores(
        'k',
        <String, double>{'a': 0.8, 'b': 0.7},
        <FilterCategory>[categoryA, categoryB],
      );
      final hit = cache.lookup('k', categories: <FilterCategory>[categoryA]);
      expect(hit, isNotNull);
      expect(hit!.gate, isNull);
      expect(hit.scores, <String, double>{'a': 0.8});
    });

    test('完全失效时返回 null', () {
      final cache = JudgeCache(store: MemoryJudgeCacheStore());
      cache.putGate('k', 0.9, <FilterCategory>[categoryA]);
      final changed = _category('a', question: '换了题面？');
      expect(cache.lookup('k', categories: <FilterCategory>[changed]), isNull);
    });
  });

  group('序列化', () {
    test('flush / load 往返保留 gate 与分数', () async {
      final store = MemoryJudgeCacheStore();
      final cache = JudgeCache(store: store);
      cache.putGate('k', 0.9, <FilterCategory>[categoryA]);
      cache.putScores('k', <String, double>{'a': 0.8}, <FilterCategory>[
        categoryA,
      ]);
      await cache.flush();
      expect(cache.dirty, isFalse);

      final decoded = jsonDecode(store.value!) as Map<String, dynamic>;
      expect(decoded['version'], 1);
      final entry = (decoded['entries'] as Map<String, dynamic>)['k']
          as Map<String, dynamic>;
      expect(entry['gate'], 0.9);
      expect(entry['gateFp'], JudgeCache.gateFingerprint([categoryA]));
      expect(entry['scores'], <String, dynamic>{
        'a': <dynamic>[0.8, JudgeCache.categoryFingerprint(categoryA)],
      });

      final loaded = JudgeCache(store: store);
      await loaded.load();
      final hit = loaded.lookup('k', categories: <FilterCategory>[categoryA]);
      expect(hit!.gate, 0.9);
      expect(hit.scores, <String, double>{'a': 0.8});
    });

    test('解析失败当作空缓存', () async {
      final store = MemoryJudgeCacheStore('{not json');
      final cache = JudgeCache(store: store);
      await cache.load();
      expect(
        cache.lookup('k', categories: <FilterCategory>[categoryA]),
        isNull,
      );
      cache.putGate('k', 0.5, <FilterCategory>[categoryA]);
      expect(cache.dirty, isTrue);
    });

    test('只保存传入类别里存在的分数', () {
      final cache = JudgeCache(store: MemoryJudgeCacheStore());
      cache.putScores(
        'k',
        <String, double>{'a': 0.8, 'unknown': 0.9},
        <FilterCategory>[categoryA],
      );
      final hit = cache.lookup('k', categories: <FilterCategory>[categoryA]);
      expect(hit!.scores, <String, double>{'a': 0.8});
    });

    test('没有写入时 flush 仍是空对象且 dirty 为 false', () async {
      final store = MemoryJudgeCacheStore();
      final cache = JudgeCache(store: store);
      expect(cache.dirty, isFalse);
      await cache.flush();
      final decoded = jsonDecode(store.value!) as Map<String, dynamic>;
      expect(decoded['entries'], isEmpty);
      expect(cache.dirty, isFalse);
    });
  });
}
