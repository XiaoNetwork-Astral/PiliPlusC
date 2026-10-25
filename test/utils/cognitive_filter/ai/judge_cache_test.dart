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
    test('自定义类别指纹是稳定的 FNV-1a 8 位十六进制', () {
      expect(JudgeCache.categoryFingerprint(categoryA), 'c589b2a2');
      expect(JudgeCache.categoryFingerprint(categoryB), '47ab4e46');
    });

    test('题面变化后指纹变化', () {
      final changed = _category('a', question: '换了题面？');
      expect(
        JudgeCache.categoryFingerprint(changed),
        isNot(JudgeCache.categoryFingerprint(categoryA)),
      );
    });
  });

  group('读写与 LRU', () {
    test('putOptions / putCustomScores 后 lookup 返回对应值并置 dirty', () {
      final cache = JudgeCache(store: MemoryJudgeCacheStore());
      cache.putOptions('k', <String, double>{'正常': 0.9, '攻击': 0.1});
      cache.putCustomScores('k', <String, double>{'a': 0.8}, <FilterCategory>[
        categoryA,
      ]);
      expect(cache.dirty, isTrue);
      final hit = cache.lookup('k', customCategories: <FilterCategory>[
        categoryA,
      ]);
      expect(hit, isNotNull);
      expect(hit!.options, <String, double>{'正常': 0.9, '攻击': 0.1});
      expect(hit.scores, <String, double>{'a': 0.8});
    });

    test('选项概率不依赖启用了哪些类别', () {
      final cache = JudgeCache(store: MemoryJudgeCacheStore());
      cache.putOptions('k', <String, double>{'正常': 0.9, '攻击': 0.1});
      final hit = cache.lookup('k', customCategories: <FilterCategory>[
        categoryB,
      ]);
      expect(hit!.options, <String, double>{'正常': 0.9, '攻击': 0.1});
      expect(hit.scores, isEmpty);
    });

    test('分数序列化保留两位小数', () async {
      final store = MemoryJudgeCacheStore();
      final cache = JudgeCache(store: store);
      cache.putOptions('k', <String, double>{'攻击': 0.126});
      cache.putCustomScores('k', <String, double>{'a': 0.126}, <FilterCategory>[
        categoryA,
      ]);
      // 内存里保留原始精度，写盘时才取两位小数
      expect(
        cache.lookup('k', customCategories: <FilterCategory>[categoryA])!
            .options!['攻击'],
        0.126,
      );
      await cache.flush();

      final loaded = JudgeCache(store: store);
      await loaded.load();
      final hit = loaded.lookup(
        'k',
        customCategories: <FilterCategory>[categoryA],
      );
      expect(hit!.options!['攻击'], 0.13);
      expect(hit.scores['a'], 0.13);
    });

    test('flush 前按 LRU 淘汰，读取命中会刷新顺序', () async {
      final cache = JudgeCache(
        store: MemoryJudgeCacheStore(),
        capacity: 2,
      );
      cache.putOptions('a', <String, double>{'正常': 0.5});
      cache.putOptions('b', <String, double>{'正常': 0.6});
      // 读取 a 刷新顺序，a 变成最新，b 是最旧
      expect(
        cache.lookup('a', customCategories: const <FilterCategory>[]),
        isNotNull,
      );
      cache.putOptions('c', <String, double>{'正常': 0.7});
      await cache.flush();
      expect(
        cache.lookup('b', customCategories: const <FilterCategory>[]),
        isNull,
      );
      expect(
        cache.lookup('a', customCategories: const <FilterCategory>[]),
        isNotNull,
      );
      expect(
        cache.lookup('c', customCategories: const <FilterCategory>[]),
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
        cache.putOptions('k$i', <String, double>{'正常': 0.5});
      }
      await cache.flush();
      final loaded = JudgeCache(
        store: store,
        capacity: 2,
      );
      await loaded.load();
      expect(
        loaded.lookup('k3', customCategories: const <FilterCategory>[]),
        isNotNull,
      );
      expect(
        loaded.lookup('k4', customCategories: const <FilterCategory>[]),
        isNotNull,
      );
      expect(
        loaded.lookup('k0', customCategories: const <FilterCategory>[]),
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
      cache.putOptions('old', <String, double>{'正常': 0.5});
      cache.putOptions('new', <String, double>{'正常': 0.5});
      now = now.add(const Duration(days: 8));
      cache.putOptions('new', <String, double>{'正常': 0.6});
      expect(
        cache.lookup('old', customCategories: const <FilterCategory>[]),
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
    test('自定义类别题面变化后只丢弃该类别分数', () {
      final cache = JudgeCache(store: MemoryJudgeCacheStore());
      cache.putOptions('k', <String, double>{'正常': 0.9});
      cache.putCustomScores(
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
        customCategories: <FilterCategory>[categoryA, changedB],
      );
      expect(hit, isNotNull);
      expect(hit!.options, <String, double>{'正常': 0.9});
      expect(hit.scores, <String, double>{'a': 0.8});
    });

    test('选项与自定义分数都不可用时返回 null', () {
      final cache = JudgeCache(store: MemoryJudgeCacheStore());
      cache.putCustomScores('k', <String, double>{'a': 0.8}, <FilterCategory>[
        categoryA,
      ]);
      final changed = _category('a', question: '换了题面？');
      expect(cache.lookup('k', customCategories: <FilterCategory>[changed]), isNull);
    });
  });

  group('序列化', () {
    test('flush / load 往返保留选项与自定义分数', () async {
      final store = MemoryJudgeCacheStore();
      final cache = JudgeCache(store: store);
      cache.putOptions('k', <String, double>{'正常': 0.7, '攻击': 0.2});
      cache.putCustomScores('k', <String, double>{'a': 0.8}, <FilterCategory>[
        categoryA,
      ]);
      await cache.flush();
      expect(cache.dirty, isFalse);

      final decoded = jsonDecode(store.value!) as Map<String, dynamic>;
      expect(decoded['version'], 2);
      final entry = (decoded['entries'] as Map<String, dynamic>)['k']
          as Map<String, dynamic>;
      expect(entry['options'], <String, dynamic>{'正常': 0.7, '攻击': 0.2});
      expect(entry['scores'], <String, dynamic>{
        'a': <dynamic>[0.8, JudgeCache.categoryFingerprint(categoryA)],
      });

      final loaded = JudgeCache(store: store);
      await loaded.load();
      final hit = loaded.lookup(
        'k',
        customCategories: <FilterCategory>[categoryA],
      );
      expect(hit!.options, <String, double>{'正常': 0.7, '攻击': 0.2});
      expect(hit.scores, <String, double>{'a': 0.8});
    });

    test('旧版本缓存直接丢弃重建', () async {
      final store = MemoryJudgeCacheStore(
        jsonEncode(<String, dynamic>{
          'version': 1,
          'entries': <String, dynamic>{
            'k': <String, dynamic>{
              'ts': DateTime(2026).millisecondsSinceEpoch,
              'gate': 0.9,
              'gateFp': 'deadbeef',
              'scores': <String, dynamic>{
                'a': <dynamic>[0.8, JudgeCache.categoryFingerprint(categoryA)],
              },
            },
          },
        }),
      );
      final cache = JudgeCache(store: store);
      await cache.load();
      expect(cache.dirty, isFalse);
      expect(
        cache.lookup('k', customCategories: <FilterCategory>[categoryA]),
        isNull,
      );
      cache.putOptions('k', <String, double>{'正常': 0.5});
      expect(cache.dirty, isTrue);
    });

    test('没有版本号或结构不符时当作空缓存', () async {
      for (final raw in <String>[
        '{"entries":{"k":{"ts":1,"options":{"正常":1}}}}',
        '{"version":2,"entries":[]}',
        '{not json',
      ]) {
        final cache = JudgeCache(store: MemoryJudgeCacheStore(raw));
        await cache.load();
        expect(
          cache.lookup('k', customCategories: const <FilterCategory>[]),
          isNull,
        );
      }
    });

    test('只保存传入类别里存在的自定义分数', () {
      final cache = JudgeCache(store: MemoryJudgeCacheStore());
      cache.putCustomScores(
        'k',
        <String, double>{'a': 0.8, 'unknown': 0.9},
        <FilterCategory>[categoryA],
      );
      final hit = cache.lookup('k', customCategories: <FilterCategory>[
        categoryA,
      ]);
      expect(hit!.scores, <String, double>{'a': 0.8});
    });

    test('非有限选项概率不写入缓存', () {
      final cache = JudgeCache(store: MemoryJudgeCacheStore());
      cache.putOptions('k', <String, double>{
        '正常': 0.5,
        '攻击': double.nan,
        '嘲讽': double.infinity,
      });
      final hit = cache.lookup('k', customCategories: const <FilterCategory>[]);
      expect(hit!.options, <String, double>{'正常': 0.5});
    });

    test('没有写入时 flush 仍是空对象且 dirty 为 false', () async {
      final store = MemoryJudgeCacheStore();
      final cache = JudgeCache(store: store);
      expect(cache.dirty, isFalse);
      await cache.flush();
      final decoded = jsonDecode(store.value!) as Map<String, dynamic>;
      expect(decoded['version'], 2);
      expect(decoded['entries'], isEmpty);
      expect(cache.dirty, isFalse);
    });
  });
}
