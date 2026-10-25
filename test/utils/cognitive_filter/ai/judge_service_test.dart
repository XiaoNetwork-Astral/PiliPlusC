import 'dart:convert';

import 'package:PiliPlus/models/cognitive_filter/filter_category.dart';
import 'package:PiliPlus/models/cognitive_filter/filter_surface.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/judge_cache.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/judge_service.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/judge_text.dart';
import 'package:PiliPlus/utils/cognitive_filter/jev_client.dart';
import 'package:flutter_test/flutter_test.dart';

FilterCategory _category(
  String id, {
  double threshold = 0.7,
  bool enabled = true,
  Set<FilterSurface>? surfaces,
}) {
  return FilterCategory(
    id: id,
    name: '测试类别$id',
    summary: '合成类别',
    question: '它是否属于测试类别$id？',
    trueCriteria: '符合 $id',
    falseCriteria: '不符合 $id',
    threshold: threshold,
    enabled: enabled,
    surfaces: surfaces ?? const <FilterSurface>{FilterSurface.danmaku},
    builtin: false,
  );
}

List<JudgeItem> _items(List<String> texts) {
  return <JudgeItem>[
    for (var i = 0; i < texts.length; i++) JudgeItem(id: 't$i', text: texts[i]),
  ];
}

JudgeService _service(
  _FakeTransport fake, {
  JudgeCache? cache,
  JudgeBudget? budget,
  double gateThreshold = 0.5,
  int gateBatch = 80,
  int categoryBatch = 20,
  int maxConcurrency = 3,
  int breakerFailures = 3,
  Duration breakerCooldown = const Duration(seconds: 60),
  DateTime Function()? now,
}) {
  return JudgeService(
    transport: fake.call,
    model: 'test-model',
    cache: cache ?? JudgeCache(store: MemoryJudgeCacheStore()),
    budget: budget ?? const UnlimitedJudgeBudget(),
    gateThreshold: gateThreshold,
    gateBatch: gateBatch,
    categoryBatch: categoryBatch,
    maxConcurrency: maxConcurrency,
    breakerFailures: breakerFailures,
    breakerCooldown: breakerCooldown,
    now: now,
  );
}

Map<String, dynamic> _stateOf(Map<String, dynamic> body) {
  return jsonDecode(body['state'] as String) as Map<String, dynamic>;
}

List<int> _questionCounts(Iterable<Map<String, dynamic>> bodies) {
  return <int>[
    for (final body in bodies) (body['questions'] as Map).length,
  ];
}

bool _isGateCall(Map<String, dynamic> body) {
  final questions = body['questions'] as Map;
  return questions.isNotEmpty &&
      (questions.keys.first as String).endsWith('_gate');
}

class _FakeTransport {
  _FakeTransport({
    this.gate = 0.9,
    this.categoryScores = const <String, double>{},
    this.defaultCategoryScore = 0.0,
    this.delay,
    this.failures = 0,
    this.error = const JevException(JevErrorKind.network, '模拟失败'),
  });

  double gate;
  Map<String, double> categoryScores;
  double defaultCategoryScore;
  Duration? delay;
  int failures;
  Object error;

  final List<Map<String, dynamic>> calls = <Map<String, dynamic>>[];
  int active = 0;
  int peak = 0;

  Future<Map<String, dynamic>> call(Map<String, dynamic> body) async {
    calls.add(body);
    active++;
    if (active > peak) {
      peak = active;
    }
    try {
      final wait = delay;
      if (wait != null) {
        await Future<void>.delayed(wait);
      }
      if (failures > 0) {
        failures--;
        throw error;
      }
      final questions = body['questions'] as Map<String, dynamic>;
      final answers = <String, dynamic>{};
      questions.forEach((key, _) {
        final double score;
        if (key.endsWith('_gate')) {
          score = gate;
        } else {
          final categoryId = key.substring(key.indexOf('_') + 1);
          score = categoryScores[categoryId] ?? defaultCategoryScore;
        }
        answers[key] = <String, dynamic>{'noul': score};
      });
      return <String, dynamic>{
        'answers': answers,
        'usage': <String, dynamic>{'input_tokens': 10, 'output_tokens': 5},
      };
    } finally {
      active--;
    }
  }
}

class _TestBudget implements JudgeBudget {
  _TestBudget({this.allowed = true});

  bool allowed;
  final List<(int, int)> records = <(int, int)>[];

  @override
  bool canSpend() => allowed;

  @override
  void record({required int inputTokens, required int outputTokens}) {
    records.add((inputTokens, outputTokens));
  }
}

void main() {
  group('规则与短文本', () {
    test('规则命中直接屏蔽且不发请求', () async {
      final fake = _FakeTransport();
      final service = _service(fake);
      final result = await service.judge(
        surface: FilterSurface.danmaku,
        items: _items(<String>['加vx领红包']),
        categories: <FilterCategory>[_category('attack')],
      );
      final verdict = result.verdicts['t0']!;
      expect(verdict.blocked, isTrue);
      expect(verdict.source, JudgeSource.rule);
      expect(verdict.categoryId, isNull);
      expect(fake.calls, isEmpty);
      expect(result.stats.ruleHits, 1);
      expect(result.stats.requests, 0);
    });

    test('规范化后不超过 2 个字符直接放行', () async {
      final fake = _FakeTransport();
      final service = _service(fake);
      final result = await service.judge(
        surface: FilterSurface.danmaku,
        items: _items(<String>['前排', '。。。', '好好好']),
        categories: <FilterCategory>[_category('attack')],
      );
      for (final verdict in result.verdicts.values) {
        expect(verdict.blocked, isFalse);
        expect(verdict.source, JudgeSource.skippedShort);
      }
      expect(fake.calls, isEmpty);
    });
  });

  group('去重与缓存', () {
    test('同文本只请求一次并把结果回填给所有 id', () async {
      final fake = _FakeTransport(
        gate: 0.9,
        defaultCategoryScore: 0.1,
      );
      final service = _service(fake);
      final result = await service.judge(
        surface: FilterSurface.danmaku,
        items: _items(<String>[
          '重复的弹幕内容',
          '  重复的弹幕内容  ',
          '重复的弹幕内容',
        ]),
        categories: <FilterCategory>[_category('attack')],
      );
      expect(fake.calls.length, 2);
      final gateBody = fake.calls.first;
      expect((gateBody['questions'] as Map).length, 1);
      final list = _stateOf(gateBody)['弹幕列表'] as List<dynamic>;
      expect(list.length, 1);
      expect((list.single as Map<String, dynamic>)['弹幕'], '重复的弹幕内容');
      for (final id in <String>['t0', 't1', 't2']) {
        expect(result.verdicts[id]!.source, JudgeSource.ai);
        expect(result.verdicts[id]!.blocked, isFalse);
      }
      expect(result.stats.requests, 2);
    });

    test('缓存里总问题与全部类别分数都有效时不再请求', () async {
      final category = _category('attack');
      final cache = JudgeCache(store: MemoryJudgeCacheStore());
      final key = normalizeJudgeText('缓存命中的弹幕内容');
      cache.putGate(key, 0.9, <FilterCategory>[category]);
      cache.putScores(
        key,
        <String, double>{'attack': 0.8},
        <FilterCategory>[category],
      );
      final fake = _FakeTransport();
      final service = _service(fake, cache: cache);
      final result = await service.judge(
        surface: FilterSurface.danmaku,
        items: _items(<String>['缓存命中的弹幕内容']),
        categories: <FilterCategory>[category],
      );
      final verdict = result.verdicts['t0']!;
      expect(verdict.blocked, isTrue);
      expect(verdict.categoryId, 'attack');
      expect(verdict.source, JudgeSource.cache);
      expect(fake.calls, isEmpty);
      expect(result.stats.cacheHits, 1);
    });

    test('缓存里总问题低于阈值时直接放行', () async {
      final category = _category('attack');
      final cache = JudgeCache(store: MemoryJudgeCacheStore());
      final key = normalizeJudgeText('缓存门控放行的内容');
      cache.putGate(key, 0.2, <FilterCategory>[category]);
      final fake = _FakeTransport();
      final service = _service(fake, cache: cache);
      final result = await service.judge(
        surface: FilterSurface.danmaku,
        items: _items(<String>['缓存门控放行的内容']),
        categories: <FilterCategory>[category],
      );
      final verdict = result.verdicts['t0']!;
      expect(verdict.blocked, isFalse);
      expect(verdict.source, JudgeSource.cache);
      expect(verdict.score, 0.2);
      expect(fake.calls, isEmpty);
    });
  });

  group('门控与阈值', () {
    test('门控放行的不进二级判定并写入缓存', () async {
      final category = _category('attack');
      final cache = JudgeCache(store: MemoryJudgeCacheStore());
      final fake = _FakeTransport(gate: 0.3);
      final service = _service(fake, cache: cache);
      final text = '门控放行的弹幕内容';
      final result = await service.judge(
        surface: FilterSurface.danmaku,
        items: _items(<String>[text]),
        categories: <FilterCategory>[category],
      );
      final verdict = result.verdicts['t0']!;
      expect(verdict.blocked, isFalse);
      expect(verdict.source, JudgeSource.skippedGate);
      expect(verdict.score, 0.3);
      expect(fake.calls.length, 1);
      expect(result.stats.gateSkipped, 1);
      final hit = cache.lookup(
        normalizeJudgeText(text),
        categories: <FilterCategory>[category],
      );
      expect(hit!.gate, 0.3);

      final second = await service.judge(
        surface: FilterSurface.danmaku,
        items: _items(<String>[text]),
        categories: <FilterCategory>[category],
      );
      expect(second.verdicts['t0']!.source, JudgeSource.cache);
      expect(fake.calls.length, 1);
    });

    test('阈值判定按分数/阈值最大选 categoryId', () async {
      final first = _category('a', threshold: 0.7);
      final second = _category('b', threshold: 0.8);
      final fake = _FakeTransport(
        gate: 0.9,
        categoryScores: <String, double>{'a': 0.8, 'b': 0.9},
      );
      final service = _service(fake);
      final result = await service.judge(
        surface: FilterSurface.danmaku,
        items: _items(<String>['达到阈值的弹幕内容']),
        categories: <FilterCategory>[first, second],
      );
      final verdict = result.verdicts['t0']!;
      expect(verdict.blocked, isTrue);
      expect(verdict.categoryId, 'a');
      expect(verdict.score, 0.8);
      expect(verdict.source, JudgeSource.ai);
      expect(fake.calls.length, 2);
    });

    test('没有任何类别达到阈值时不屏蔽', () async {
      final first = _category('a', threshold: 0.7);
      final second = _category('b', threshold: 0.8);
      final fake = _FakeTransport(
        gate: 0.9,
        categoryScores: <String, double>{'a': 0.6, 'b': 0.7},
      );
      final service = _service(fake);
      final result = await service.judge(
        surface: FilterSurface.danmaku,
        items: _items(<String>['未达到阈值的弹幕']),
        categories: <FilterCategory>[first, second],
      );
      final verdict = result.verdicts['t0']!;
      expect(verdict.blocked, isFalse);
      expect(verdict.categoryId, isNull);
      expect(verdict.score, 0.7);
      expect(verdict.source, JudgeSource.ai);
    });
  });

  group('分批与并发', () {
    test('总问题按 80 条、逐类别按 20 条分批', () async {
      final fake = _FakeTransport(
        gate: 0.9,
        defaultCategoryScore: 0.1,
      );
      final service = _service(fake);
      final texts = <String>[
        for (var i = 0; i < 81; i++) '普通弹幕内容${i}号',
      ];
      final result = await service.judge(
        surface: FilterSurface.danmaku,
        items: _items(texts),
        categories: <FilterCategory>[_category('attack')],
      );
      expect(result.stats.requests, 7);
      final gateCalls = fake.calls.where(_isGateCall).toList();
      final categoryCalls = fake.calls.where((body) => !_isGateCall(body))
          .toList();
      expect(_questionCounts(gateCalls), <int>[80, 1]);
      expect(_questionCounts(categoryCalls), <int>[20, 20, 20, 20, 1]);
    });

    test('并发请求数不超过 maxConcurrency', () async {
      final fake = _FakeTransport(
        gate: 0.3,
        delay: const Duration(milliseconds: 5),
      );
      final service = _service(
        fake,
        gateBatch: 1,
        maxConcurrency: 3,
      );
      final texts = <String>[
        for (var i = 0; i < 7; i++) '并发测试弹幕${i}号',
      ];
      await service.judge(
        surface: FilterSurface.danmaku,
        items: _items(texts),
        categories: <FilterCategory>[_category('attack')],
      );
      expect(fake.calls.length, 7);
      expect(fake.peak, lessThanOrEqualTo(3));
      expect(fake.peak, greaterThan(1));
    });
  });

  group('失败与熔断', () {
    test('请求失败时放行、不写缓存并计数', () async {
      final cache = JudgeCache(store: MemoryJudgeCacheStore());
      final fake = _FakeTransport(failures: 1);
      final service = _service(fake, cache: cache);
      final text = '请求失败的弹幕内容';
      final result = await service.judge(
        surface: FilterSurface.danmaku,
        items: _items(<String>[text]),
        categories: <FilterCategory>[_category('attack')],
      );
      final verdict = result.verdicts['t0']!;
      expect(verdict.blocked, isFalse);
      expect(verdict.source, JudgeSource.failed);
      expect(fake.calls.length, 1);
      expect(cache.dirty, isFalse);
      expect(
        cache.lookup(
          normalizeJudgeText(text),
          categories: <FilterCategory>[_category('attack')],
        ),
        isNull,
      );
      expect(result.stats.failedRequests, 1);
      expect(result.stats.requests, 1);
    });

    test('连续失败达到阈值后熔断，冷却结束恢复', () async {
      var now = DateTime(2026);
      final fake = _FakeTransport(
        gate: 0.9,
        defaultCategoryScore: 0.1,
        failures: 3,
      );
      final service = _service(
        fake,
        gateBatch: 1,
        categoryBatch: 1,
        maxConcurrency: 1,
        breakerFailures: 3,
        breakerCooldown: const Duration(seconds: 60),
        now: () => now,
      );
      final categories = <FilterCategory>[_category('attack')];
      final first = await service.judge(
        surface: FilterSurface.danmaku,
        items: _items(<String>['失败一', '失败二', '失败三', '失败四']),
        categories: categories,
      );
      expect(fake.calls.length, 3);
      expect(service.breakerOpen, isTrue);
      for (final id in <String>['t0', 't1', 't2']) {
        expect(first.verdicts[id]!.source, JudgeSource.failed);
      }
      expect(first.verdicts['t3']!.source, JudgeSource.skippedBreaker);

      now = now.add(const Duration(seconds: 61));
      fake.failures = 0;
      final second = await service.judge(
        surface: FilterSurface.danmaku,
        items: _items(<String>['恢复后的正常弹幕']),
        categories: categories,
      );
      expect(second.verdicts['t0']!.source, JudgeSource.ai);
      expect(service.breakerOpen, isFalse);
      expect(fake.calls.length, 5);
    });

    test('auth 错误立即熔断十分钟', () async {
      final start = DateTime(2026);
      var now = start;
      final fake = _FakeTransport(
        failures: 1,
        error: const JevException(JevErrorKind.auth, 'API Key 无效'),
      );
      final service = _service(
        fake,
        maxConcurrency: 1,
        now: () => now,
      );
      final categories = <FilterCategory>[_category('attack')];
      final first = await service.judge(
        surface: FilterSurface.danmaku,
        items: _items(<String>['触发鉴权失败的弹幕']),
        categories: categories,
      );
      expect(first.verdicts['t0']!.source, JudgeSource.failed);
      expect(service.breakerOpen, isTrue);

      now = start.add(const Duration(minutes: 5));
      final second = await service.judge(
        surface: FilterSurface.danmaku,
        items: _items(<String>['熔断期间的弹幕']),
        categories: categories,
      );
      expect(second.verdicts['t0']!.source, JudgeSource.skippedBreaker);
      expect(fake.calls.length, 1);

      now = start.add(const Duration(minutes: 11));
      fake.failures = 0;
      final third = await service.judge(
        surface: FilterSurface.danmaku,
        items: _items(<String>['冷却结束后的弹幕']),
        categories: categories,
      );
      expect(third.verdicts['t0']!.source, JudgeSource.ai);
      expect(service.breakerOpen, isFalse);
      expect(fake.calls.length, 3);
    });

    test('非 JevException 的异常也只放行不抛出', () async {
      final fake = _FakeTransport(failures: 1, error: StateError('boom'));
      final service = _service(fake);
      final result = await service.judge(
        surface: FilterSurface.danmaku,
        items: _items(<String>['异常弹幕内容']),
        categories: <FilterCategory>[_category('attack')],
      );
      expect(result.verdicts['t0']!.source, JudgeSource.failed);
      expect(result.verdicts['t0']!.blocked, isFalse);
    });
  });

  group('预算与禁用', () {
    test('预算不足时全部跳过且不发请求', () async {
      final budget = _TestBudget(allowed: false);
      final fake = _FakeTransport();
      final service = _service(fake, budget: budget);
      final result = await service.judge(
        surface: FilterSurface.danmaku,
        items: _items(<String>['预算不足的弹幕一', '预算不足的弹幕二']),
        categories: <FilterCategory>[_category('attack')],
      );
      for (final verdict in result.verdicts.values) {
        expect(verdict.source, JudgeSource.skippedBudget);
        expect(verdict.blocked, isFalse);
      }
      expect(fake.calls, isEmpty);
      expect(result.stats.requests, 0);
    });

    test('请求成功后记录 usage 到统计与预算', () async {
      final budget = _TestBudget();
      final fake = _FakeTransport(gate: 0.3);
      final service = _service(fake, budget: budget);
      final result = await service.judge(
        surface: FilterSurface.danmaku,
        items: _items(<String>['记录用量的弹幕内容']),
        categories: <FilterCategory>[_category('attack')],
      );
      expect(result.stats.inputTokens, 10);
      expect(result.stats.outputTokens, 5);
      expect(budget.records.length, 1);
      expect(budget.records.single, (10, 5));
    });

    test('没有启用类别时全部 disabled', () async {
      final fake = _FakeTransport();
      final service = _service(fake);
      final result = await service.judge(
        surface: FilterSurface.danmaku,
        items: _items(<String>['禁用类别的弹幕内容']),
        categories: <FilterCategory>[_category('attack', enabled: false)],
      );
      expect(result.verdicts['t0']!.source, JudgeSource.disabled);
      expect(result.verdicts['t0']!.blocked, isFalse);
      expect(fake.calls, isEmpty);
    });

    test('类别不适用于当前场景时按禁用处理', () async {
      final fake = _FakeTransport();
      final service = _service(fake);
      final result = await service.judge(
        surface: FilterSurface.danmaku,
        items: _items(<String>['场景不匹配的弹幕']),
        categories: <FilterCategory>[
          _category(
            'reply',
            surfaces: const <FilterSurface>{FilterSurface.reply},
          ),
        ],
      );
      expect(result.verdicts['t0']!.source, JudgeSource.disabled);
      expect(fake.calls, isEmpty);
    });
  });
}
