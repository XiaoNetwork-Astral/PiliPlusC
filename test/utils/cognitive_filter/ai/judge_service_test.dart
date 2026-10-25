import 'dart:convert';

import 'package:PiliPlus/models/cognitive_filter/builtin_categories.dart';
import 'package:PiliPlus/models/cognitive_filter/filter_category.dart';
import 'package:PiliPlus/models/cognitive_filter/filter_surface.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/jev_request.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/judge_cache.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/judge_service.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/judge_text.dart';
import 'package:PiliPlus/utils/cognitive_filter/jev_client.dart';
import 'package:flutter_test/flutter_test.dart';

FilterCategory _builtin(
  String id, {
  double threshold = 0.55,
  bool enabled = true,
  Set<FilterSurface>? surfaces,
}) {
  final base = builtinCategories.firstWhere((category) => category.id == id);
  return base.copyWith(
    threshold: threshold,
    enabled: enabled,
    surfaces: surfaces ?? base.surfaces,
  );
}

FilterCategory _custom(
  String id, {
  String name = '自定义类别',
  String question = '它是否属于自定义类别？',
  double threshold = 0.7,
  bool enabled = true,
  Set<FilterSurface>? surfaces,
}) {
  return FilterCategory(
    id: id,
    name: name,
    summary: '合成类别',
    question: question,
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
  int categoryBatch = 80,
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

class _FakeTransport {
  _FakeTransport({
    this.optionsByText = const <String, Map<String, double>>{},
    this.defaultOptions = const <String, double>{},
    this.customByText = const <String, Map<String, double>>{},
    this.defaultCustom = const <String, double>{},
    this.delay,
    this.failures = 0,
    this.error = const JevException(JevErrorKind.network, '模拟失败'),
    this.badResponse = false,
  });

  final Map<String, Map<String, double>> optionsByText;
  final Map<String, double> defaultOptions;
  final Map<String, Map<String, double>> customByText;
  final Map<String, double> defaultCustom;
  Duration? delay;
  int failures;
  Object error;
  bool badResponse;

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
      if (badResponse) {
        return <String, dynamic>{'answers': <String, dynamic>{}};
      }
      final state = _stateOf(body);
      final listKey = state.keys.firstWhere((key) => key.endsWith('列表'));
      final list = state[listKey] as List<dynamic>;
      final questions = body['questions'] as Map<String, dynamic>;
      final answers = <String, dynamic>{};
      for (var i = 0; i < list.length; i++) {
        final entry = list[i] as Map<String, dynamic>;
        final text = entry.entries
            .firstWhere((item) => item.key != '编号')
            .value as String;
        final no = i + 1;
        final options = optionsByText[text] ?? defaultOptions;
        answers['i$no'] = <String, dynamic>{
          'probabilities': <String, dynamic>{
            for (final name in JevRequest.optionNames)
              name: options[name] ?? 0.0,
          },
        };
        final customs = customByText[text] ?? defaultCustom;
        for (final key in questions.keys) {
          if (!key.startsWith('i${no}_')) {
            continue;
          }
          final id = key.substring(key.indexOf('_') + 1);
          answers[key] = <String, dynamic>{'noul': customs[id] ?? 0.0};
        }
      }
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
  group('短文本与去重', () {
    test('规范化后不超过 2 个字符直接放行', () async {
      final fake = _FakeTransport();
      final service = _service(fake);
      final result = await service.judge(
        surface: FilterSurface.danmaku,
        items: _items(<String>['前排', '。。。', '好好好']),
        categories: <FilterCategory>[_builtin('attack')],
      );
      for (final verdict in result.verdicts.values) {
        expect(verdict.blocked, isFalse);
        expect(verdict.source, JudgeSource.skippedShort);
        expect(verdict.scores, isEmpty);
      }
      expect(fake.calls, isEmpty);
    });

    test('请求带上标题与附加背景', () async {
      final fake = _FakeTransport(defaultOptions: <String, double>{'正常': 1.0});
      final service = _service(fake);
      await service.judge(
        surface: FilterSurface.danmaku,
        items: _items(<String>['带背景的弹幕内容']),
        categories: <FilterCategory>[_builtin('attack')],
        title: '视频标题文字',
        context: '背景文字',
        contextKey: '字幕',
      );
      final state = _stateOf(fake.calls.single);
      expect(state['视频标题'], '视频标题文字');
      expect(state['字幕'], '背景文字');
    });

    test('不再接入本地规则，规则关键词也交给 AI', () async {
      final fake = _FakeTransport(defaultOptions: <String, double>{'正常': 1.0});
      final service = _service(fake);
      final result = await service.judge(
        surface: FilterSurface.danmaku,
        items: _items(<String>['加vx领红包']),
        categories: <FilterCategory>[_builtin('attack')],
      );
      expect(fake.calls.length, 1);
      expect(result.verdicts['t0']!.source, JudgeSource.ai);
      expect(result.verdicts['t0']!.blocked, isFalse);
    });

    test('同文本只请求一次并把结果回填给所有 id', () async {
      final fake = _FakeTransport(defaultOptions: <String, double>{'正常': 1.0});
      final service = _service(fake);
      final result = await service.judge(
        surface: FilterSurface.danmaku,
        items: _items(<String>[
          '重复的弹幕内容',
          '  重复的弹幕内容  ',
          '重复的弹幕内容',
        ]),
        categories: <FilterCategory>[_builtin('attack')],
      );
      expect(fake.calls.length, 1);
      final body = fake.calls.single;
      expect((body['questions'] as Map).length, 1);
      final list = _stateOf(body)['弹幕列表'] as List<dynamic>;
      expect(list.length, 1);
      expect((list.single as Map<String, dynamic>)['弹幕'], '重复的弹幕内容');
      for (final id in <String>['t0', 't1', 't2']) {
        expect(result.verdicts[id]!.source, JudgeSource.ai);
        expect(result.verdicts[id]!.blocked, isFalse);
      }
      expect(result.stats.requests, 1);
    });
  });

  group('内置类别求和与阈值', () {
    test('启用类别概率之和达到阈值即屏蔽，理由取概率最大的内置类别', () async {
      final fake = _FakeTransport(
        defaultOptions: <String, double>{
          '正常': 0.45,
          '攻击': 0.3,
          '嘲讽': 0.25,
        },
      );
      final service = _service(fake);
      final result = await service.judge(
        surface: FilterSurface.danmaku,
        items: _items(<String>['达到阈值的弹幕内容']),
        categories: <FilterCategory>[
          _builtin('attack', threshold: 0.5),
          _builtin('mock', threshold: 0.5),
        ],
      );
      final verdict = result.verdicts['t0']!;
      expect(verdict.blocked, isTrue);
      expect(verdict.categoryId, 'attack');
      expect(verdict.score, closeTo(0.55, 1e-9));
      expect(verdict.source, JudgeSource.ai);
      expect(verdict.scores['攻击'], 0.3);
      expect(verdict.scores['嘲讽'], 0.25);
      expect(fake.calls.length, 1);
    });

    test('低于阈值不屏蔽但仍给出可能属于的内置类别', () async {
      final fake = _FakeTransport(
        defaultOptions: <String, double>{
          '正常': 0.6,
          '攻击': 0.25,
          '嘲讽': 0.15,
        },
      );
      final service = _service(fake);
      final result = await service.judge(
        surface: FilterSurface.danmaku,
        items: _items(<String>['未达到阈值的弹幕']),
        categories: <FilterCategory>[
          _builtin('attack', threshold: 0.5),
          _builtin('mock', threshold: 0.5),
        ],
      );
      final verdict = result.verdicts['t0']!;
      expect(verdict.blocked, isFalse);
      expect(verdict.categoryId, 'attack');
      expect(verdict.score, closeTo(0.4, 1e-9));
      expect(verdict.source, JudgeSource.ai);
    });

    test('阈值取启用内置类别里的最大值', () async {
      final fake = _FakeTransport(
        defaultOptions: <String, double>{
          '正常': 0.45,
          '攻击': 0.25,
          '嘲讽': 0.3,
        },
      );
      final service = _service(fake);
      final result = await service.judge(
        surface: FilterSurface.danmaku,
        items: _items(<String>['阈值取最大值的弹幕']),
        categories: <FilterCategory>[
          _builtin('attack', threshold: 0.4),
          _builtin('mock', threshold: 0.6),
        ],
      );
      final verdict = result.verdicts['t0']!;
      expect(verdict.blocked, isFalse);
      expect(verdict.score, closeTo(0.55, 1e-9));
      expect(verdict.categoryId, 'mock');
    });

    test('乱码选项不计入屏蔽得分', () async {
      final fake = _FakeTransport(
        defaultOptions: <String, double>{'攻击': 0.2, '乱码': 0.8},
      );
      final service = _service(fake);
      final result = await service.judge(
        surface: FilterSurface.danmaku,
        items: _items(<String>['乱码占多数的弹幕']),
        categories: <FilterCategory>[_builtin('attack', threshold: 0.5)],
      );
      final verdict = result.verdicts['t0']!;
      expect(verdict.blocked, isFalse);
      expect(verdict.score, closeTo(0.2, 1e-9));
      expect(verdict.categoryId, 'attack');
    });

    test('关闭某类别后同一缓存文本的得分随之变化', () async {
      final cache = JudgeCache(store: MemoryJudgeCacheStore());
      final fake = _FakeTransport(
        defaultOptions: <String, double>{
          '正常': 0.4,
          '攻击': 0.2,
          '嘲讽': 0.4,
        },
      );
      final service = _service(fake, cache: cache);
      final text = '关闭类别后得分变化的弹幕';

      final both = await service.judge(
        surface: FilterSurface.danmaku,
        items: _items(<String>[text]),
        categories: <FilterCategory>[
          _builtin('attack', threshold: 0.5),
          _builtin('mock', threshold: 0.5),
        ],
      );
      expect(both.verdicts['t0']!.blocked, isTrue);
      expect(both.verdicts['t0']!.score, closeTo(0.6, 1e-9));
      expect(both.verdicts['t0']!.categoryId, 'mock');

      final onlyAttack = await service.judge(
        surface: FilterSurface.danmaku,
        items: _items(<String>[text]),
        categories: <FilterCategory>[_builtin('attack', threshold: 0.5)],
      );
      final verdict = onlyAttack.verdicts['t0']!;
      expect(verdict.source, JudgeSource.cache);
      expect(verdict.blocked, isFalse);
      expect(verdict.score, closeTo(0.2, 1e-9));
      expect(verdict.categoryId, 'attack');
      expect(fake.calls.length, 1);
    });
  });

  group('自定义类别', () {
    test('只有自定义类别时按自己的阈值判定', () async {
      final fake = _FakeTransport(
        defaultOptions: <String, double>{'正常': 1.0},
        defaultCustom: <String, double>{'c1': 0.7},
      );
      final service = _service(fake);
      final result = await service.judge(
        surface: FilterSurface.danmaku,
        items: _items(<String>['命中自定义类别的弹幕']),
        categories: <FilterCategory>[_custom('c1', threshold: 0.7)],
      );
      final verdict = result.verdicts['t0']!;
      expect(verdict.blocked, isTrue);
      expect(verdict.categoryId, 'c1');
      expect(verdict.score, closeTo(0.7, 1e-9));
      expect(verdict.source, JudgeSource.ai);
      expect(verdict.scores['正常'], 1.0);
    });

    test('自定义类别低于阈值时不屏蔽', () async {
      final fake = _FakeTransport(
        defaultOptions: <String, double>{'正常': 1.0},
        defaultCustom: <String, double>{'c1': 0.6},
      );
      final service = _service(fake);
      final result = await service.judge(
        surface: FilterSurface.danmaku,
        items: _items(<String>['未命中自定义类别的弹幕']),
        categories: <FilterCategory>[_custom('c1', threshold: 0.7)],
      );
      final verdict = result.verdicts['t0']!;
      expect(verdict.blocked, isFalse);
      expect(verdict.categoryId, 'c1');
      expect(verdict.score, closeTo(0.6, 1e-9));
    });

    test('选择题与自定义 noul 题在同一次请求里', () async {
      final fake = _FakeTransport(
        defaultOptions: <String, double>{'正常': 0.9, '攻击': 0.1},
        defaultCustom: <String, double>{'c1': 0.9},
      );
      final service = _service(fake);
      final result = await service.judge(
        surface: FilterSurface.danmaku,
        items: _items(<String>['同时带自定义类别的弹幕']),
        categories: <FilterCategory>[
          _builtin('attack', threshold: 0.5),
          _custom('c1', threshold: 0.7),
        ],
      );
      expect(fake.calls.length, 1);
      final questions = fake.calls.single['questions'] as Map<String, dynamic>;
      expect(questions.keys.toList(), <String>['i1', 'i1_c1']);
      expect((questions['i1'] as Map<String, dynamic>)['type'], 'choice');
      expect((questions['i1_c1'] as Map<String, dynamic>)['type'], 'noul');
      final state = _stateOf(fake.calls.single);
      expect(
        (state['类别说明'] as List<dynamic>).length,
        JevRequest.optionNames.length + 1,
      );
      final verdict = result.verdicts['t0']!;
      expect(verdict.blocked, isTrue);
      expect(verdict.categoryId, 'c1');
    });

    test('内置类别达到阈值时理由优先取内置类别', () async {
      final fake = _FakeTransport(
        defaultOptions: <String, double>{'正常': 0.4, '攻击': 0.6},
        defaultCustom: <String, double>{'c1': 0.95},
      );
      final service = _service(fake);
      final result = await service.judge(
        surface: FilterSurface.danmaku,
        items: _items(<String>['内置与自定义同时命中的弹幕']),
        categories: <FilterCategory>[
          _builtin('attack', threshold: 0.5),
          _custom('c1', threshold: 0.7),
        ],
      );
      final verdict = result.verdicts['t0']!;
      expect(verdict.blocked, isTrue);
      expect(verdict.categoryId, 'attack');
      expect(verdict.score, closeTo(0.6, 1e-9));
    });
  });

  group('缓存', () {
    test('选项概率命中缓存后不再请求', () async {
      final cache = JudgeCache(store: MemoryJudgeCacheStore());
      final fake = _FakeTransport(
        defaultOptions: <String, double>{'正常': 0.5, '攻击': 0.5},
      );
      final service = _service(fake, cache: cache);
      final text = '缓存命中的弹幕内容';
      final first = await service.judge(
        surface: FilterSurface.danmaku,
        items: _items(<String>[text]),
        categories: <FilterCategory>[_builtin('attack', threshold: 0.5)],
      );
      expect(first.verdicts['t0']!.source, JudgeSource.ai);

      final second = await service.judge(
        surface: FilterSurface.danmaku,
        items: _items(<String>[text]),
        categories: <FilterCategory>[_builtin('attack', threshold: 0.5)],
      );
      final verdict = second.verdicts['t0']!;
      expect(verdict.source, JudgeSource.cache);
      expect(verdict.blocked, isTrue);
      expect(verdict.categoryId, 'attack');
      expect(verdict.scores['攻击'], 0.5);
      expect(fake.calls.length, 1);
      expect(second.stats.cacheHits, 1);
    });

    test('自定义类别答案按指纹缓存，题面变化后重新请求', () async {
      final cache = JudgeCache(store: MemoryJudgeCacheStore());
      final fake = _FakeTransport(
        defaultOptions: <String, double>{'正常': 1.0},
        defaultCustom: <String, double>{'c1': 0.9},
      );
      final service = _service(fake, cache: cache);
      final text = '自定义类别缓存弹幕';
      final first = await service.judge(
        surface: FilterSurface.danmaku,
        items: _items(<String>[text]),
        categories: <FilterCategory>[_custom('c1')],
      );
      expect(first.verdicts['t0']!.source, JudgeSource.ai);

      final second = await service.judge(
        surface: FilterSurface.danmaku,
        items: _items(<String>[text]),
        categories: <FilterCategory>[_custom('c1')],
      );
      expect(second.verdicts['t0']!.source, JudgeSource.cache);
      expect(fake.calls.length, 1);

      final third = await service.judge(
        surface: FilterSurface.danmaku,
        items: _items(<String>[text]),
        categories: <FilterCategory>[
          _custom('c1', question: '换了题面的自定义类别？'),
        ],
      );
      expect(third.verdicts['t0']!.source, JudgeSource.ai);
      expect(fake.calls.length, 2);
    });
  });

  group('分批与并发', () {
    test('无自定义类别时按 80 条分批', () async {
      final fake = _FakeTransport(defaultOptions: <String, double>{'正常': 1.0});
      final service = _service(fake);
      final texts = <String>[
        for (var i = 0; i < 81; i++) '普通弹幕内容$i号',
      ];
      final result = await service.judge(
        surface: FilterSurface.danmaku,
        items: _items(texts),
        categories: <FilterCategory>[_builtin('attack')],
      );
      expect(result.stats.requests, 2);
      final counts = _questionCounts(fake.calls);
      counts.sort();
      expect(counts, <int>[1, 80]);
    });

    test('带自定义类别时按题目上限自动拆批', () async {
      final fake = _FakeTransport(defaultOptions: <String, double>{'正常': 1.0});
      final service = _service(fake);
      final texts = <String>[
        for (var i = 0; i < 81; i++) '带自定义类别弹幕$i号',
      ];
      final result = await service.judge(
        surface: FilterSurface.danmaku,
        items: _items(texts),
        categories: <FilterCategory>[
          _builtin('attack'),
          _custom('c1'),
        ],
      );
      expect(result.stats.requests, 2);
      final counts = _questionCounts(fake.calls);
      counts.sort();
      expect(counts, <int>[2, 160]);
    });

    test('并发请求数不超过 maxConcurrency', () async {
      final fake = _FakeTransport(
        defaultOptions: <String, double>{'正常': 1.0},
        delay: const Duration(milliseconds: 5),
      );
      final service = _service(
        fake,
        categoryBatch: 1,
        maxConcurrency: 3,
      );
      final texts = <String>[
        for (var i = 0; i < 7; i++) '并发测试弹幕$i号',
      ];
      await service.judge(
        surface: FilterSurface.danmaku,
        items: _items(texts),
        categories: <FilterCategory>[_builtin('attack')],
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
        categories: <FilterCategory>[_builtin('attack')],
      );
      final verdict = result.verdicts['t0']!;
      expect(verdict.blocked, isFalse);
      expect(verdict.source, JudgeSource.failed);
      expect(verdict.scores, isEmpty);
      expect(fake.calls.length, 1);
      expect(cache.dirty, isFalse);
      expect(
        cache.lookup(
          normalizeJudgeText(text),
          customCategories: const <FilterCategory>[],
        ),
        isNull,
      );
      expect(result.stats.failedRequests, 1);
      expect(result.stats.requests, 1);
    });

    test('响应结构不对时也只放行', () async {
      final fake = _FakeTransport(badResponse: true);
      final service = _service(fake);
      final result = await service.judge(
        surface: FilterSurface.danmaku,
        items: _items(<String>['响应结构错误的弹幕']),
        categories: <FilterCategory>[_builtin('attack')],
      );
      final verdict = result.verdicts['t0']!;
      expect(verdict.blocked, isFalse);
      expect(verdict.source, JudgeSource.failed);
      expect(result.stats.failedRequests, 1);
    });

    test('连续失败达到阈值后熔断，冷却结束恢复', () async {
      var now = DateTime(2026);
      final fake = _FakeTransport(
        defaultOptions: <String, double>{'正常': 1.0},
        failures: 3,
      );
      final service = _service(
        fake,
        categoryBatch: 1,
        maxConcurrency: 1,
        breakerFailures: 3,
        breakerCooldown: const Duration(seconds: 60),
        now: () => now,
      );
      final categories = <FilterCategory>[_builtin('attack')];
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
      expect(fake.calls.length, 4);
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
      final categories = <FilterCategory>[_builtin('attack')];
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
      expect(fake.calls.length, 2);
    });

    test('非 JevException 的异常也只放行不抛出', () async {
      final fake = _FakeTransport(failures: 1, error: StateError('boom'));
      final service = _service(fake);
      final result = await service.judge(
        surface: FilterSurface.danmaku,
        items: _items(<String>['异常弹幕内容']),
        categories: <FilterCategory>[_builtin('attack')],
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
        categories: <FilterCategory>[_builtin('attack')],
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
      final fake = _FakeTransport(defaultOptions: <String, double>{'正常': 1.0});
      final service = _service(fake, budget: budget);
      final result = await service.judge(
        surface: FilterSurface.danmaku,
        items: _items(<String>['记录用量的弹幕内容']),
        categories: <FilterCategory>[_builtin('attack')],
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
        categories: <FilterCategory>[_builtin('attack', enabled: false)],
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
          _custom(
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
