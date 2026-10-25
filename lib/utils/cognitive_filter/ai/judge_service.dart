import 'dart:async';

import 'package:PiliPlus/models/cognitive_filter/filter_category.dart';
import 'package:PiliPlus/models/cognitive_filter/filter_surface.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/jev_request.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/judge_cache.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/judge_text.dart';
import 'package:PiliPlus/utils/cognitive_filter/jev_client.dart';
import 'package:PiliPlus/utils/cognitive_filter/local_rules.dart';

/// 发一次请求并返回解码后的响应 Map，失败抛 [JevException]
typedef JevTransport =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> body);

/// 请求预算接口
abstract class JudgeBudget {
  bool canSpend();

  void record({required int inputTokens, required int outputTokens});
}

/// 不限预算，适合未配置预算的场景
class UnlimitedJudgeBudget implements JudgeBudget {
  const UnlimitedJudgeBudget();

  @override
  bool canSpend() => true;

  @override
  void record({required int inputTokens, required int outputTokens}) {}
}

/// 判定结果的来源
enum JudgeSource {
  rule,
  cache,
  ai,
  skippedShort,
  skippedGate,
  failed,
  skippedBreaker,
  skippedBudget,
  disabled,
}

/// 单条文字的判定结果
class JudgeVerdict {
  const JudgeVerdict({
    required this.blocked,
    required this.score,
    required this.source,
    this.categoryId,
  });

  final bool blocked;
  final String? categoryId;
  final double score;
  final JudgeSource source;
}

/// 一次判定的统计
class JudgeStats {
  int requests = 0;
  int cacheHits = 0;
  int ruleHits = 0;
  int gateSkipped = 0;
  int inputTokens = 0;
  int outputTokens = 0;
  int failedRequests = 0;
}

/// 待判定的文字
class JudgeItem {
  const JudgeItem({required this.id, required this.text});

  final String id;
  final String text;
}

/// 一次判定的完整结果
class JudgeResult {
  const JudgeResult({required this.verdicts, required this.stats});

  final Map<String, JudgeVerdict> verdicts;
  final JudgeStats stats;
}

class _WorkItem {
  _WorkItem({required this.key, required this.ids});

  final String key;
  final List<String> ids;
}

class _BatchResult<T> {
  const _BatchResult.value(this.value) : source = null, failed = false;

  const _BatchResult.skip(JudgeSource this.source) : value = null, failed = false;

  const _BatchResult.failed() : value = null, source = null, failed = true;

  final T? value;
  final JudgeSource? source;
  final bool failed;
}

/// 认知滤网 AI 判定服务：规则 → 短文本 → 去重缓存 → 门控 → 逐类别 → 阈值
class JudgeService {
  JudgeService({
    required this.transport,
    required this.model,
    required this.cache,
    required this.budget,
    this.gateThreshold = 0.5,
    this.gateBatch = 80,
    this.categoryBatch = 20,
    this.maxConcurrency = 3,
    this.breakerFailures = 3,
    this.breakerCooldown = const Duration(seconds: 60),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now,
       _semaphore = _Semaphore(maxConcurrency),
       assert(gateThreshold >= 0 && gateThreshold <= 1),
       assert(gateBatch > 0),
       assert(categoryBatch > 0),
       assert(maxConcurrency > 0),
       assert(breakerFailures > 0);

  static const Duration _authCooldown = Duration(minutes: 10);
  static const int _gateLimit = 80;
  static const int _categoryTextLimit = 20;

  final JevTransport transport;
  final String model;
  final JudgeCache cache;
  final JudgeBudget budget;
  final double gateThreshold;
  final int gateBatch;
  final int categoryBatch;
  final int maxConcurrency;
  final int breakerFailures;
  final Duration breakerCooldown;
  final DateTime Function() _now;
  final _Semaphore _semaphore;
  int _consecutiveFailures = 0;
  DateTime? _breakerUntil;

  /// 熔断器是否处于打开状态；冷却结束后自动复位
  bool get breakerOpen {
    final until = _breakerUntil;
    if (until == null) {
      return false;
    }
    if (_now().isBefore(until)) {
      return true;
    }
    _breakerUntil = null;
    _consecutiveFailures = 0;
    return false;
  }

  /// 手动复位熔断器
  void resetBreaker() {
    _breakerUntil = null;
    _consecutiveFailures = 0;
  }

  /// 判定一批文字，任何情况下都不向调用方抛异常
  Future<JudgeResult> judge({
    required FilterSurface surface,
    required List<JudgeItem> items,
    required List<FilterCategory> categories,
    String title = '',
    String context = '',
    String? contextKey,
  }) async {
    final stats = JudgeStats();
    final verdicts = <String, JudgeVerdict>{};
    try {
      await _run(
        surface: surface,
        items: items,
        categories: categories,
        title: title,
        context: context,
        contextKey: contextKey,
        stats: stats,
        verdicts: verdicts,
      );
    } catch (_) {
      // 兜底放行，保证调用方拿到的永远是结果
    }
    for (final item in items) {
      verdicts.putIfAbsent(
        item.id,
        () => const JudgeVerdict(
          blocked: false,
          score: 0,
          source: JudgeSource.failed,
        ),
      );
    }
    return JudgeResult(verdicts: verdicts, stats: stats);
  }

  Future<void> _run({
    required FilterSurface surface,
    required List<JudgeItem> items,
    required List<FilterCategory> categories,
    required String title,
    required String context,
    required String? contextKey,
    required JudgeStats stats,
    required Map<String, JudgeVerdict> verdicts,
  }) async {
    final enabled = <FilterCategory>[
      for (final category in categories)
        if (category.enabled && category.surfaces.contains(surface)) category,
    ];
    if (enabled.isEmpty) {
      for (final item in items) {
        verdicts[item.id] = const JudgeVerdict(
          blocked: false,
          score: 0,
          source: JudgeSource.disabled,
        );
      }
      return;
    }

    final work = <String, _WorkItem>{};
    for (final item in items) {
      if (LocalRules.verdict(item.text).blocked) {
        verdicts[item.id] = const JudgeVerdict(
          blocked: true,
          score: 1,
          source: JudgeSource.rule,
        );
        stats.ruleHits++;
        continue;
      }
      if (isTooShortToJudge(item.text)) {
        verdicts[item.id] = const JudgeVerdict(
          blocked: false,
          score: 0,
          source: JudgeSource.skippedShort,
        );
        continue;
      }
      final key = normalizeJudgeText(item.text);
      final existing = work[key];
      if (existing != null) {
        existing.ids.add(item.id);
      } else {
        work[key] = _WorkItem(key: key, ids: <String>[item.id]);
      }
    }

    final gateStage = <_WorkItem>[];
    final categoryStage = <_WorkItem>[];
    for (final item in work.values) {
      final hit = cache.lookup(item.key, categories: enabled);
      if (hit != null) {
        final gate = hit.gate;
        if (gate != null && gate < gateThreshold) {
          _assign(
            verdicts,
            item.ids,
            JudgeVerdict(
              blocked: false,
              score: gate,
              source: JudgeSource.cache,
            ),
          );
          stats.cacheHits++;
          continue;
        }
        final complete =
            gate != null &&
            gate >= gateThreshold &&
            enabled.every((category) => hit.scores.containsKey(category.id));
        if (complete) {
          _assign(
            verdicts,
            item.ids,
            _fromScores(hit.scores, enabled, JudgeSource.cache),
          );
          stats.cacheHits++;
          continue;
        }
        if (gate != null && gate >= gateThreshold) {
          categoryStage.add(item);
          continue;
        }
      }
      gateStage.add(item);
    }

    await _runGateBatches(
      items: gateStage,
      enabled: enabled,
      surface: surface,
      title: title,
      context: context,
      contextKey: contextKey,
      stats: stats,
      verdicts: verdicts,
      categoryStage: categoryStage,
    );

    await _runCategoryBatches(
      items: categoryStage,
      enabled: enabled,
      surface: surface,
      title: title,
      context: context,
      contextKey: contextKey,
      stats: stats,
      verdicts: verdicts,
    );
  }

  Future<void> _runGateBatches({
    required List<_WorkItem> items,
    required List<FilterCategory> enabled,
    required FilterSurface surface,
    required String title,
    required String context,
    required String? contextKey,
    required JudgeStats stats,
    required Map<String, JudgeVerdict> verdicts,
    required List<_WorkItem> categoryStage,
  }) async {
    final size = gateBatch > _gateLimit ? _gateLimit : gateBatch;
    final batches = _chunk(items, size < 1 ? 1 : size);
    final results = await Future.wait(<Future<_BatchResult<List<double>>>>[
      for (final batch in batches)
        _attempt<List<double>>(
          stats: stats,
          buildBody: () => JevRequest.buildGateRequest(
            model: model,
            surface: surface,
            texts: <String>[for (final item in batch) item.key],
            categories: enabled,
            title: title,
            context: context,
            contextKey: contextKey,
          ),
          parse: (response) =>
              JevRequest.parseGateScores(response, batch.length),
        ),
    ]);

    for (var index = 0; index < batches.length; index++) {
      final batch = batches[index];
      final result = results[index];
      if (result.failed) {
        _assignAll(
          verdicts,
          batch,
          const JudgeVerdict(
            blocked: false,
            score: 0,
            source: JudgeSource.failed,
          ),
        );
        continue;
      }
      final skip = result.source;
      if (skip != null) {
        _assignAll(
          verdicts,
          batch,
          JudgeVerdict(blocked: false, score: 0, source: skip),
        );
        continue;
      }
      final scores = result.value!;
      for (var i = 0; i < batch.length; i++) {
        final item = batch[i];
        final score = scores[i];
        cache.putGate(item.key, score, enabled);
        if (score < gateThreshold) {
          stats.gateSkipped++;
          _assign(
            verdicts,
            item.ids,
            JudgeVerdict(
              blocked: false,
              score: score,
              source: JudgeSource.skippedGate,
            ),
          );
        } else {
          categoryStage.add(item);
        }
      }
    }
  }

  Future<void> _runCategoryBatches({
    required List<_WorkItem> items,
    required List<FilterCategory> enabled,
    required FilterSurface surface,
    required String title,
    required String context,
    required String? contextKey,
    required JudgeStats stats,
    required Map<String, JudgeVerdict> verdicts,
  }) async {
    if (items.isEmpty) {
      return;
    }
    final size = _categoryBatchSize(enabled.length);
    final batches = _chunk(items, size);
    final results = await Future.wait(
      <Future<_BatchResult<List<Map<String, double>>>>>[
        for (final batch in batches)
          _attempt<List<Map<String, double>>>(
            stats: stats,
            buildBody: () => JevRequest.buildCategoryRequest(
              model: model,
              surface: surface,
              texts: <String>[for (final item in batch) item.key],
              categories: enabled,
              title: title,
              context: context,
              contextKey: contextKey,
            ),
            parse: (response) => JevRequest.parseCategoryScores(
              response,
              batch.length,
              enabled,
            ),
          ),
      ],
    );

    for (var index = 0; index < batches.length; index++) {
      final batch = batches[index];
      final result = results[index];
      if (result.failed) {
        _assignAll(
          verdicts,
          batch,
          const JudgeVerdict(
            blocked: false,
            score: 0,
            source: JudgeSource.failed,
          ),
        );
        continue;
      }
      final skip = result.source;
      if (skip != null) {
        _assignAll(
          verdicts,
          batch,
          JudgeVerdict(blocked: false, score: 0, source: skip),
        );
        continue;
      }
      final scores = result.value!;
      for (var i = 0; i < batch.length; i++) {
        final item = batch[i];
        cache.putScores(item.key, scores[i], enabled);
        _assign(
          verdicts,
          item.ids,
          _fromScores(scores[i], enabled, JudgeSource.ai),
        );
      }
    }
  }

  Future<_BatchResult<T>> _attempt<T>({
    required JudgeStats stats,
    required Map<String, dynamic> Function() buildBody,
    required T Function(Map<String, dynamic> response) parse,
  }) {
    return _semaphore.run<_BatchResult<T>>(() async {
      final skip = _skipSource();
      if (skip != null) {
        return _BatchResult<T>.skip(skip);
      }
      stats.requests++;
      try {
        final response = await transport(buildBody());
        final value = parse(response);
        _consecutiveFailures = 0;
        try {
          _recordUsage(response, stats);
        } catch (_) {
          // 预算实现异常不影响判定结果
        }
        return _BatchResult<T>.value(value);
      } on JevException catch (error) {
        _onFailure(error, stats);
        return _BatchResult<T>.failed();
      } catch (_) {
        _onFailure(null, stats);
        return _BatchResult<T>.failed();
      }
    });
  }

  JudgeSource? _skipSource() {
    if (breakerOpen) {
      return JudgeSource.skippedBreaker;
    }
    if (!budget.canSpend()) {
      return JudgeSource.skippedBudget;
    }
    return null;
  }

  void _onFailure(JevException? error, JudgeStats stats) {
    stats.failedRequests++;
    _consecutiveFailures++;
    final auth = error?.kind == JevErrorKind.auth;
    if (auth || _consecutiveFailures >= breakerFailures) {
      _breakerUntil = _now().add(auth ? _authCooldown : breakerCooldown);
    }
  }

  void _recordUsage(Map<String, dynamic> response, JudgeStats stats) {
    final usage = response['usage'];
    var input = 0;
    var output = 0;
    if (usage is Map) {
      input = _tokenOf(usage['input_tokens']);
      output = _tokenOf(usage['output_tokens']);
    }
    stats.inputTokens += input;
    stats.outputTokens += output;
    budget.record(inputTokens: input, outputTokens: output);
  }

  int _tokenOf(Object? value) {
    if (value is! num) {
      return 0;
    }
    final number = value.toDouble();
    if (!number.isFinite || number <= 0) {
      return 0;
    }
    return number.toInt();
  }

  JudgeVerdict _fromScores(
    Map<String, double> scores,
    List<FilterCategory> enabled,
    JudgeSource source,
  ) {
    FilterCategory? best;
    var bestRatio = -1.0;
    var bestScore = 0.0;
    var maxScore = 0.0;
    for (final category in enabled) {
      final score = scores[category.id] ?? 0;
      if (score > maxScore) {
        maxScore = score;
      }
      if (score < category.threshold) {
        continue;
      }
      final ratio = category.threshold <= 0
          ? double.infinity
          : score / category.threshold;
      if (best == null || ratio > bestRatio) {
        best = category;
        bestRatio = ratio;
        bestScore = score;
      }
    }
    if (best != null) {
      return JudgeVerdict(
        blocked: true,
        categoryId: best.id,
        score: bestScore,
        source: source,
      );
    }
    return JudgeVerdict(blocked: false, score: maxScore, source: source);
  }

  int _categoryBatchSize(int categoryCount) {
    var size = categoryBatch > _categoryTextLimit
        ? _categoryTextLimit
        : categoryBatch;
    final maxByQuestions = categoryCount > 0
        ? JevRequest.maxQuestions ~/ categoryCount
        : size;
    if (size > maxByQuestions) {
      size = maxByQuestions;
    }
    return size < 1 ? 1 : size;
  }

  void _assignAll(
    Map<String, JudgeVerdict> verdicts,
    List<_WorkItem> items,
    JudgeVerdict verdict,
  ) {
    for (final item in items) {
      _assign(verdicts, item.ids, verdict);
    }
  }

  void _assign(
    Map<String, JudgeVerdict> verdicts,
    List<String> ids,
    JudgeVerdict verdict,
  ) {
    for (final id in ids) {
      verdicts[id] = verdict;
    }
  }

  List<List<T>> _chunk<T>(List<T> items, int size) {
    final step = size < 1 ? 1 : size;
    final result = <List<T>>[];
    for (var i = 0; i < items.length; i += step) {
      final end = i + step > items.length ? items.length : i + step;
      result.add(items.sublist(i, end));
    }
    return result;
  }
}

class _Semaphore {
  _Semaphore(this.max);

  final int max;
  int _active = 0;
  final List<Completer<void>> _waiters = <Completer<void>>[];

  Future<T> run<T>(Future<T> Function() action) async {
    if (_active >= max) {
      final waiter = Completer<void>();
      _waiters.add(waiter);
      await waiter.future;
    }
    _active++;
    try {
      return await action();
    } finally {
      _active--;
      if (_waiters.isNotEmpty) {
        _waiters.removeAt(0).complete();
      }
    }
  }
}
