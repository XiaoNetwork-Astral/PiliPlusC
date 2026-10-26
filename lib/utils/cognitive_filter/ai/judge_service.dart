import 'dart:async';

import 'package:PiliPlus/models/cognitive_filter/filter_category.dart';
import 'package:PiliPlus/models/cognitive_filter/filter_surface.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/jev_request.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/judge_cache.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/judge_text.dart';
import 'package:PiliPlus/utils/cognitive_filter/jev_client.dart';
import 'package:PiliPlus/utils/cognitive_filter/raw_error.dart';

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
  cache,
  ai,
  skippedShort,
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
    this.scores = const <String, double>{},
  });

  final bool blocked;
  final String? categoryId;
  final double score;
  final JudgeSource source;

  /// 八个固定选项的概率，键见 [JevRequest.optionNames]；跳过的条目为空
  final Map<String, double> scores;
}

/// 一次判定的统计
class JudgeStats {
  int requests = 0;
  int cacheHits = 0;
  int inputTokens = 0;
  int outputTokens = 0;
  int failedRequests = 0;

  /// 最近一次失败的原始说明，供界面提示
  String? lastError;
}

/// 待判定的文字
class JudgeItem {
  const JudgeItem({
    required this.id,
    required this.text,
    this.mid,
    this.midHash,
    this.meta,
    this.snapshotBuilder,
  });

  final String id;
  final String text;

  /// 作者 UID，能拿到时用于白名单的用户规则
  final int? mid;

  /// 弹幕发送者哈希，用于白名单里按 UID 派生的哈希匹配
  final String? midHash;

  /// 原始内容的简单快照，键与值都是简单类型
  final Map<String, dynamic>? meta;

  /// 被屏蔽并写入历史时才调用的重快照生成器
  final Map<String, dynamic> Function()? snapshotBuilder;
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

/// 认知滤网 AI 判定服务：短文本 → 去重缓存 → 单级选择题 → 阈值
///
/// 每条内容只发一道八选一选择题，屏蔽得分 S 是启用的内置类别对应选项概率
/// 之和，S 达到内置类别共用的阈值 T 即屏蔽；自定义类别是同一次请求里的
/// 额外 noul 题，按各自的阈值判断。
class JudgeService {
  JudgeService({
    required this.transport,
    required this.model,
    required this.cache,
    required this.budget,
    this.categoryBatch = 80,
    this.maxConcurrency = 3,
    this.breakerFailures = 3,
    this.breakerCooldown = const Duration(seconds: 60),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now,
       _semaphore = _Semaphore(maxConcurrency),
       assert(categoryBatch > 0),
       assert(maxConcurrency > 0),
       assert(breakerFailures > 0);

  static const Duration _authCooldown = Duration(minutes: 10);

  final JevTransport transport;
  final String model;
  final JudgeCache cache;
  final JudgeBudget budget;
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

    final builtins = <FilterCategory>[
      for (final category in enabled)
        if (category.builtin &&
            JevRequest.builtinOptionNames.containsKey(category.id))
          category,
    ];
    final customs = <FilterCategory>[
      for (final category in enabled)
        if (!category.builtin ||
            !JevRequest.builtinOptionNames.containsKey(category.id))
          category,
    ];

    final work = <String, _WorkItem>{};
    for (final item in items) {
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

    final pending = <_WorkItem>[];
    for (final item in work.values) {
      final hit = cache.lookup(
        item.key,
        customCategories: customs,
      );
      final options = hit?.options;
      final customScores = hit?.scores ?? const <String, double>{};
      if (options != null &&
          JevRequest.optionNames.every(options.containsKey) &&
          customs.every((category) => customScores.containsKey(category.id))) {
        _assign(
          verdicts,
          item.ids,
          _fromScores(
            options,
            customScores,
            builtins,
            customs,
            JudgeSource.cache,
          ),
        );
        stats.cacheHits++;
      } else {
        pending.add(item);
      }
    }

    await _runBatches(
      items: pending,
      builtins: builtins,
      customs: customs,
      surface: surface,
      title: title,
      context: context,
      contextKey: contextKey,
      stats: stats,
      verdicts: verdicts,
    );
  }

  Future<void> _runBatches({
    required List<_WorkItem> items,
    required List<FilterCategory> builtins,
    required List<FilterCategory> customs,
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
    final batches = _chunk(items, _batchSize(customs.length));
    final results = await Future.wait(
      <Future<_BatchResult<List<JevItemScores>>>>[
        for (final batch in batches)
          _attempt<List<JevItemScores>>(
            stats: stats,
            buildBody: () => JevRequest.buildRequest(
              model: model,
              surface: surface,
              texts: <String>[for (final item in batch) item.key],
              customCategories: customs,
              title: title,
              context: context,
              contextKey: contextKey,
            ),
            parse: (response) => JevRequest.parseResponse(
              response,
              batch.length,
              customCategories: customs,
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
        final score = scores[i];
        cache.putOptions(item.key, score.options);
        if (customs.isNotEmpty) {
          cache.putCustomScores(item.key, score.custom, customs);
        }
        _assign(
          verdicts,
          item.ids,
          _fromScores(
            score.options,
            score.custom,
            builtins,
            customs,
            JudgeSource.ai,
          ),
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
      } catch (error) {
        _onFailure(error, stats);
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

  void _onFailure(Object? error, JudgeStats stats) {
    stats.failedRequests++;
    final jev = error is JevException ? error : null;
    if (jev != null) {
      stats.lastError = jev.message;
    } else if (error == null) {
      stats.lastError = '未知错误';
    } else {
      stats.lastError = truncateError(redactSecrets(error.toString()));
    }
    _consecutiveFailures++;
    final auth = jev?.kind == JevErrorKind.auth;
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

  /// 选项概率与实际启用的内置/自定义类别合成判定
  JudgeVerdict _fromScores(
    Map<String, double> options,
    Map<String, double> customScores,
    List<FilterCategory> builtins,
    List<FilterCategory> customs,
    JudgeSource source,
  ) {
    var sum = 0.0;
    FilterCategory? topBuiltin;
    var topBuiltinProb = -1.0;
    var threshold = 0.0;
    for (var i = 0; i < builtins.length; i++) {
      final category = builtins[i];
      final probability =
          options[JevRequest.builtinOptionNames[category.id]] ?? 0.0;
      sum += probability;
      if (probability > topBuiltinProb) {
        topBuiltinProb = probability;
        topBuiltin = category;
      }
      final value = category.threshold;
      if (i == 0 || value > threshold) {
        threshold = value;
      }
    }
    final builtinBlocked = builtins.isNotEmpty && sum >= threshold;

    FilterCategory? topCustom;
    var topCustomProb = -1.0;
    FilterCategory? blockedCustom;
    var blockedCustomProb = -1.0;
    for (final category in customs) {
      final probability = customScores[category.id] ?? 0.0;
      if (probability > topCustomProb) {
        topCustomProb = probability;
        topCustom = category;
      }
      if (probability >= category.threshold &&
          probability > blockedCustomProb) {
        blockedCustomProb = probability;
        blockedCustom = category;
      }
    }

    final scores = Map<String, double>.from(options);
    if (builtinBlocked) {
      return JudgeVerdict(
        blocked: true,
        categoryId: topBuiltin?.id,
        score: sum,
        source: source,
        scores: scores,
      );
    }
    if (blockedCustom != null) {
      return JudgeVerdict(
        blocked: true,
        categoryId: blockedCustom.id,
        score: blockedCustomProb,
        source: source,
        scores: scores,
      );
    }
    if (builtins.isNotEmpty) {
      return JudgeVerdict(
        blocked: false,
        categoryId: topBuiltin?.id,
        score: sum,
        source: source,
        scores: scores,
      );
    }
    return JudgeVerdict(
      blocked: false,
      categoryId: topCustom?.id,
      score: topCustomProb < 0 ? 0.0 : topCustomProb,
      source: source,
      scores: scores,
    );
  }

  int _batchSize(int customCount) {
    final perText = 1 + customCount;
    final maxByQuestions = perText <= 0
        ? JevRequest.maxQuestions
        : JevRequest.maxQuestions ~/ perText;
    var size = categoryBatch;
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
