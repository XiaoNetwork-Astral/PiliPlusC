import 'dart:async';

import 'package:PiliPlus/models/cognitive_filter/filter_surface.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/ai_runtime.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/calibration/calibration_auto.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/calibration/calibration_bank.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/calibration/calibration_models.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/calibration/calibration_pool.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/calibration/calibration_round.dart'
    as round;
import 'package:PiliPlus/utils/cognitive_filter/ai/calibration/guard_rules_source.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/calibration/llm_client.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/calibration/llm_pricing.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/calibration/threshold_fit.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/calibration/upload_guard.dart';
import 'package:PiliPlus/utils/cognitive_filter/jev_proxy.dart';
import 'package:PiliPlus/utils/path_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

/// 一轮整理的结果
class RoundOutcome {
  const RoundOutcome({
    required this.questions,
    required this.abortedBy,
    this.abortMessage,
  });

  /// 这一轮整理出的题目
  final List<CalibrationQuestion> questions;

  /// 非空表示这一轮因密钥、网络、限流、服务端、超时或费用上限中止
  final LlmErrorKind? abortedBy;

  /// 中止时给用户看的说明，可能是异常原文，也可能是“未填写 API Key”这类合成文案
  final String? abortMessage;
}

/// 一轮整理的进度，界面据此显示进度条
class OrganizeStatus {
  const OrganizeStatus({this.running = false, this.done = 0, this.total = 0});

  /// 是否有整理在跑
  final bool running;

  /// 已完成的批数
  final int done;

  /// 总批数
  final int total;

  @override
  bool operator ==(Object other) =>
      other is OrganizeStatus &&
      other.running == running &&
      other.done == done &&
      other.total == total;

  @override
  int get hashCode => Object.hash(running, done, total);
}

/// 校准向导的运行时服务
///
/// 平时静默收集高分内容，后台把攒够的内容整理成题目存进题库，
/// 用户打开向导时直接从题库取题，答完后把回答折算成门槛调整量
class CalibrationService {
  CalibrationService._();

  static final CalibrationService instance = CalibrationService._();

  static const String _dirName = 'cognitive_filter';
  static const String _poolFileName = 'calibration_pool.json';
  static const String _bankFileName = 'calibration_bank.json';
  static const Duration _flushDelay = Duration(seconds: 5);

  /// 思考文字只保留末尾这么多字
  static const int _thinkingKeep = 400;

  CalibrationPool? _pool;
  CalibrationBank? _bank;
  Future<void>? _initFuture;
  Timer? _flushTimer;
  UploadGuard _guard = UploadGuard.empty();
  int _guardVersion = -1;

  /// 当前正在跑的一轮，用来互斥并让后来的调用等它结束
  Future<RoundOutcome>? _activeRound;

  /// 后台整理循环是否在跑，避免重复起循环
  bool _autoLoopRunning = false;

  /// 用户是否请求停止当前一轮，等这一批做完再生效
  bool _stopRequested = false;

  /// 上次没整理出至少 10 题或出错时的池条数，初始 0
  int _lastFailedPoolSize = 0;

  String _thinkingText = '';

  /// 题库或收集池变化时加一，界面据此刷新数量
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// 整理进度，后台整理时界面也看得到
  final ValueNotifier<OrganizeStatus> status = ValueNotifier<OrganizeStatus>(
    const OrganizeStatus(),
  );

  /// 整理时累计的思考文字，只保留末尾 [_thinkingKeep] 字
  final ValueNotifier<String> thinking = ValueNotifier<String>('');

  /// 初始化收集池与题库；可重复调用，失败时保持未激活
  Future<void> init() => _initFuture ??= _doInit();

  Future<void> _doInit() async {
    try {
      final directory = path.join(appSupportDirPath, _dirName);
      final pool = CalibrationPool(
        store: FileJudgeCacheStore(path.join(directory, _poolFileName)),
        isBlockedForUpload: _isBlockedForUpload,
      );
      final bank = CalibrationBank(
        store: FileJudgeCacheStore(path.join(directory, _bankFileName)),
      );
      await pool.load();
      await bank.load();
      _pool = pool;
      _bank = bank;
    } catch (_) {
      _pool = null;
      _bank = null;
    }
    _bumpRevision();
    unawaited(_maybeAutoOrganize());
  }

  /// 当前的不外传检查器，用户改规则后自动重建
  UploadGuard get guard {
    final version = GuardRulesSource.instance.version.value;
    if (_guardVersion != version) {
      try {
        _guard = GuardRulesSource.instance.buildGuard();
      } catch (_) {
        _guard = UploadGuard.empty();
      }
      _guardVersion = version;
    }
    return _guard;
  }

  /// 每次判定都取当前版本的检查器，规则改动后立即生效
  bool _isBlockedForUpload(String text) => guard.matches(text);

  /// 静默收集一条内容；没填整理接口的密钥时不收，不抛异常
  void collect({
    required FilterSurface surface,
    required String text,
    required double score,
    String category = '',
  }) {
    try {
      if (Pref.cfLlmApiKey.trim().isEmpty) {
        return;
      }
      final pool = _pool;
      if (pool == null) {
        // 调用方可能还没来得及 init，这里补一次，本条先跳过
        unawaited(init());
        return;
      }
      final added = pool.add(
        text: text,
        surface: surface.label,
        score: score,
        category: category,
      );
      if (added) {
        _bumpRevision();
        _scheduleFlush();
        unawaited(_maybeAutoOrganize());
      }
    } catch (_) {
      // 收集是旁路，失败不影响判定主流程
    }
  }

  /// 给向导准备本次要答的题：优先从题库取，题库不够就手动整理一轮
  ///
  /// ①若有一轮正在跑（后台或手动）先等它结束 ②题库已有至少
  /// [calibrationMinQuestions] 题就直接返回最早的至多
  /// [calibrationMaxQuestions] 题 ③否则整理一轮，够 10 题就返回至多 20 题，
  /// 不够就返回空题目；出错或取消时按 [RoundOutcome] 的语义返回 abortedBy
  Future<RoundOutcome> prepareSession() async {
    await init();
    final active = _activeRound;
    if (active != null) {
      try {
        await active;
      } catch (_) {
        // 已有那一轮失败不影响重新检查题库
      }
    }

    final bank = _bank;
    if (bank != null && bank.length >= calibrationMinQuestions) {
      return RoundOutcome(
        questions: bank.take(calibrationMaxQuestions),
        abortedBy: null,
      );
    }

    final outcome = await _organizeOnce();
    final after = _bank;
    final questions = after == null
        ? const <CalibrationQuestion>[]
        : after.take(calibrationMaxQuestions);
    if (questions.length >= calibrationMinQuestions) {
      return RoundOutcome(questions: questions, abortedBy: null);
    }
    return RoundOutcome(
      questions: const <CalibrationQuestion>[],
      abortedBy: outcome.abortedBy,
      abortMessage: outcome.abortMessage,
    );
  }

  /// 请求停止当前一轮，当前批结束后停，已整理出且够 10 题的结果照常入库
  void stop() {
    if (_activeRound == null) {
      return;
    }
    _stopRequested = true;
  }

  /// 把答过的题从题库删掉，然后看看要不要接着在后台整理
  void finishSession(Iterable<CalibrationQuestion> answered) {
    final targets = answered.toList(growable: false);
    final bank = _bank;
    if (bank == null) {
      // 还没初始化时补一次，题库就绪后再删
      unawaited(
        init().then((_) {
          final loaded = _bank;
          if (loaded == null) {
            return;
          }
          loaded.removeAnswered(targets);
          _bumpRevision();
          unawaited(_flushBank());
          unawaited(_maybeAutoOrganize());
        }),
      );
      return;
    }
    bank.removeAnswered(targets);
    _bumpRevision();
    unawaited(_flushBank());
    unawaited(_maybeAutoOrganize());
  }

  /// 设置变化后由页面调用，重新判断要不要在后台整理
  void onSettingsChanged() {
    unawaited(_maybeAutoOrganize());
  }

  /// 题库里现在有多少道题，还没初始化时为 0
  int get bankSize => _bank?.length ?? 0;

  /// 题库里最早的至多 [limit] 道题，还没初始化时为空
  List<CalibrationQuestion> bankQuestions([
    int limit = calibrationMaxQuestions,
  ]) {
    final bank = _bank;
    if (bank == null) {
      return const <CalibrationQuestion>[];
    }
    return bank.take(limit);
  }

  /// 内部整理一轮，同时只允许一轮在跑
  Future<RoundOutcome> _organizeOnce({
    void Function(int done, int total)? onProgress,
    void Function(String delta)? onThinking,
    bool Function()? shouldCancel,
  }) {
    final active = _activeRound;
    if (active != null) {
      return active;
    }
    late final Future<RoundOutcome> future;
    future = _organizeLocked(
      onProgress: onProgress,
      onThinking: onThinking,
      shouldCancel: shouldCancel,
    ).whenComplete(() {
      if (identical(_activeRound, future)) {
        _activeRound = null;
      }
    });
    _activeRound = future;
    return future;
  }

  Future<RoundOutcome> _organizeLocked({
    void Function(int done, int total)? onProgress,
    void Function(String delta)? onThinking,
    bool Function()? shouldCancel,
  }) async {
    _stopRequested = false;
    _clearThinking();
    status.value = const OrganizeStatus(running: true);
    try {
      return await _runRoundBody(
          onProgress: onProgress,
        onThinking: onThinking,
        shouldCancel: shouldCancel,
      );
    } finally {
      final current = status.value;
      status.value = OrganizeStatus(
        running: false,
        done: current.done,
        total: current.total,
      );
    }
  }

  Future<RoundOutcome> _runRoundBody({
    void Function(int done, int total)? onProgress,
    void Function(String delta)? onThinking,
    bool Function()? shouldCancel,
  }) async {
    final apiKey = Pref.cfLlmApiKey.trim();
    if (apiKey.isEmpty) {
      return const RoundOutcome(
        questions: <CalibrationQuestion>[],
        abortedBy: LlmErrorKind.auth,
        abortMessage: '未填写 API Key',
      );
    }

    // 今日整理接口的每日费用额度用完了，这一轮直接不发请求
    if (llmBudgetReached) {
      return const RoundOutcome(
        questions: <CalibrationQuestion>[],
        abortedBy: LlmErrorKind.budget,
        abortMessage: '已达今日费用上限',
      );
    }

    await init();
    final pool = _pool;
    if (pool == null) {
      return const RoundOutcome(
        questions: <CalibrationQuestion>[],
        abortedBy: LlmErrorKind.network,
      );
    }

    try {
      final client = LlmClient(
        baseUrl: Pref.cfLlmBaseUrl,
        apiKey: apiKey,
        model: Pref.cfLlmModel,
        // 开着最高强度思考，一批可能要想一两分钟；超时由用户设置
        timeout: Duration(seconds: Pref.cfLlmTimeout),
        proxy: _currentProxy(),
        onUsage: _recordLlmUsage,
        onReasoning: (delta) {
          _appendThinking(delta);
          onThinking?.call(delta);
        },
      );
      final result = await round.runRound(
        pool: pool.items,
        chat: client.chat,
        isBlockedForUpload: _isBlockedForUpload,
        onProgress: (done, total) {
          // 新的一批开始，思考文字从头来
          _clearThinking();
          status.value = OrganizeStatus(
            running: true,
            done: done,
            total: total,
          );
          onProgress?.call(done, total);
        },
        shouldStop: () =>
            _stopRequested ||
            llmBudgetReached ||
            (shouldCancel?.call() ?? false),
        outputRetries: Pref.cfLlmOutputRetries,
        otherRetries: Pref.cfLlmOtherRetries,
      );
      // 题数不够 10 道时不出题，已用掉的内容留在池里等下一轮；
      // 够了就照常使用，即便中途是被用户停止或出错中断的
      final usable = result.questions.length >= calibrationMinQuestions;
      final removedIds = <String>{
        if (usable) ...result.usedIds,
        ...result.droppedIds,
      };
      pool.removeIds(removedIds);
      await pool.flush();
      if (removedIds.isNotEmpty) {
        _bumpRevision();
      }

      if (usable) {
        final bank = _bank;
        if (bank != null) {
          bank.add(result.questions);
          await bank.flush();
          _bumpRevision();
        }
      } else {
        _lastFailedPoolSize = pool.length;
      }
      // 中途出错或用户停止过，也算这次没跑顺，记下池条数免得马上重试
      if (usable && result.abortedBy != null) {
        _lastFailedPoolSize = pool.length;
      }

      return RoundOutcome(
        questions: usable ? result.questions : const <CalibrationQuestion>[],
        abortedBy: usable ? null : result.abortedBy,
        abortMessage: usable ? null : result.abortMessage,
      );
    } catch (error) {
      _lastFailedPoolSize = pool.length;
      return RoundOutcome(
        questions: const <CalibrationQuestion>[],
        abortedBy: LlmErrorKind.network,
        abortMessage: round.llmErrorMessage(error),
      );
    }
  }

  /// 条件满足就在后台整理；不阻塞调用方，也不抛异常
  Future<void> _maybeAutoOrganize() async {
    if (_autoLoopRunning) {
      return;
    }
    _autoLoopRunning = true;
    try {
      while (true) {
        await init();
        final pool = _pool;
        final bank = _bank;
        if (pool == null || bank == null) {
          return;
        }
        final shouldRun = shouldAutoOrganize(
          autoEnabled: Pref.cfCalibAuto,
          hasKey: Pref.cfLlmApiKey.trim().isNotEmpty,
          running: _activeRound != null,
          budgetReached: llmBudgetReached,
          bankSize: bank.length,
          bankCap: Pref.cfCalibBankCap,
          poolSize: pool.length,
          lastFailedPoolSize: _lastFailedPoolSize,
        );
        if (!shouldRun) {
          return;
        }
        final outcome = await _organizeOnce();
        if (outcome.abortedBy != null ||
            outcome.questions.length < calibrationMinQuestions) {
          return;
        }
        // 一轮成功后再看一次条件，题库没满且池还够就接着整理
      }
    } catch (_) {
      // 后台整理不弹提示也不抛异常
    } finally {
      _autoLoopRunning = false;
    }
  }

  void _appendThinking(String delta) {
    if (delta.isEmpty) {
      return;
    }
    final text = _thinkingText + delta;
    _thinkingText = text.length > _thinkingKeep
        ? text.substring(text.length - _thinkingKeep)
        : text;
    thinking.value = _thinkingText;
  }

  void _clearThinking() {
    _thinkingText = '';
    thinking.value = '';
  }

  void _bumpRevision() {
    revision.value++;
  }

  /// 整理接口今天的花费（人民币元）；跨天时把存储的日期改成今天并清零
  ///
  /// 价格见 `llm_pricing.dart`，按 DeepSeek 官方高峰时段价保守估算
  double get llmCostCnyToday {
    final usage = _usageToday;
    return llmCostCny(usage.input, usage.output);
  }

  /// 整理接口今天的费用是否已到上限；上限为 0 表示不限制
  bool get llmBudgetReached {
    final cap = Pref.cfLlmDailyCapCny;
    return cap > 0 && llmCostCnyToday >= cap;
  }

  /// 今日累计的输入/输出 token；跨天时把存储日期改成今天并清零
  ({int input, int output}) get _usageToday {
    final day = _dayKey(DateTime.now());
    if (Pref.cfLlmUsageDay != day) {
      Pref.cfLlmUsageDay = day;
      Pref.cfLlmUsageInputTokens = 0;
      Pref.cfLlmUsageOutputTokens = 0;
      return (input: 0, output: 0);
    }
    return (
      input: Pref.cfLlmUsageInputTokens,
      output: Pref.cfLlmUsageOutputTokens,
    );
  }

  /// 累加整理接口的输入/输出 token，跨天时从 0 开始记
  void _recordLlmUsage(int inputTokens, int outputTokens) {
    final day = _dayKey(DateTime.now());
    final sameDay = Pref.cfLlmUsageDay == day;
    final input = sameDay ? Pref.cfLlmUsageInputTokens : 0;
    final output = sameDay ? Pref.cfLlmUsageOutputTokens : 0;
    Pref.cfLlmUsageDay = day;
    Pref.cfLlmUsageInputTokens = input + (inputTokens < 0 ? 0 : inputTokens);
    Pref.cfLlmUsageOutputTokens =
        output + (outputTokens < 0 ? 0 : outputTokens);
  }

  /// 本地日期，格式 yyyy-MM-dd，与用量存储保持一致
  static String _dayKey(DateTime time) {
    final month = time.month.toString().padLeft(2, '0');
    final day = time.day.toString().padLeft(2, '0');
    return '${time.year}-$month-$day';
  }

  /// 收集池里现在有多少条可整理的内容，还没初始化时为 0
  int get poolSize => _pool?.length ?? 0;

  /// 把回答折算成门槛调整量并写入设置
  ///
  /// 回答太少时不做改动，[after] 为 null
  ({double before, double? after}) apply(
    List<({CalibrationAnswer answer, CalibrationQuestion question})> answers,
  ) {
    final base = Pref.cfBlockThreshold;
    final current = base + Pref.cfAiThresholdDelta;
    final after = fitThreshold(
      current: current,
      answers: <({CalibrationAnswer answer, List<double> scores})>[
        for (final entry in answers)
          (
            answer: entry.answer,
            scores: <double>[
              for (final member in entry.question.members) member.score,
            ],
          ),
      ],
    );
    if (after == null) {
      return (before: current, after: null);
    }
    Pref.cfAiThresholdDelta = after - base;
    return (before: current, after: after);
  }

  /// 清空收集池与题库并复位门槛调整量
  Future<void> reset() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    _stopRequested = false;
    _lastFailedPoolSize = 0;
    await init();
    try {
      final pool = _pool;
      if (pool != null) {
        pool.clear();
        await pool.flush();
      }
    } catch (_) {
      // 落盘失败时内存已经清空，下次仍会覆盖
    }
    try {
      final bank = _bank;
      if (bank != null) {
        bank.clear();
        await bank.flush();
      }
    } catch (_) {
      // 落盘失败时内存已经清空，下次仍会覆盖
    }
    Pref.cfAiThresholdDelta = 0.0;
    _bumpRevision();
  }

  void _scheduleFlush() {
    if (_flushTimer?.isActive ?? false) {
      return;
    }
    _flushTimer = Timer(_flushDelay, () {
      _flushTimer = null;
      unawaited(_flushPool());
    });
  }

  /// 立即落盘，供退出或进入后台时调用
  Future<void> flush() async {
    await _flushPool();
    await _flushBank();
  }

  Future<void> _flushPool() async {
    try {
      final pool = _pool;
      if (pool != null) {
        await pool.flush();
      }
    } catch (_) {
      // 收集池落盘失败下次再试
    }
  }

  Future<void> _flushBank() async {
    try {
      final bank = _bank;
      if (bank != null) {
        await bank.flush();
      }
    } catch (_) {
      // 题库落盘失败下次再试
    }
  }

  /// 整理接口当前的代理设置，未启用或地址非法时返回 null（直连）
  JevProxy? _currentProxy() {
    final type = switch (Pref.cfLlmProxyType) {
      1 => JevProxyType.http,
      2 => JevProxyType.socks5,
      _ => JevProxyType.none,
    };
    return JevProxy.parse(type, Pref.cfLlmProxyAddress);
  }
}
