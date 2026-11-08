import 'dart:async';
import 'dart:math';

import 'package:PiliPlus/models/cognitive_filter/config.dart';
import 'package:PiliPlus/models/cognitive_filter/filter_category.dart';
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
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

/// 一轮整理的结果
class RoundOutcome {
  const RoundOutcome({
    required this.questions,
    required this.abortedBy,
    this.abortMessage,
    this.cancelled = false,
  });

  /// 这一轮整理出的题目
  final List<CalibrationQuestion> questions;

  /// 非空表示这一轮因密钥、网络、限流、服务端、超时或费用上限中止
  final LlmErrorKind? abortedBy;

  /// 中止时给用户看的说明，可能是异常原文，也可能是“未填写 API Key”这类合成文案
  final String? abortMessage;

  /// 用户停手或后台开关关掉导致整轮作废
  ///
  /// 此时 [questions] 为空，[abortedBy] 也为空：不是错误，也不用提示
  final bool cancelled;
}

/// 一个内置类别这次校准的调整结果
class CategoryFit {
  const CategoryFit({
    required this.id,
    required this.name,
    required this.before,
    required this.after,
  });

  final String id;
  final String name;
  final double before;
  final double after;
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

  /// 思考文字超过 [_thinkingLimit] 字才裁，裁到只剩末尾 [_thinkingKeep] 字
  ///
  /// 每来一段就裁头部会让界面里所有行不断重排，所以留足余量、很少裁
  static const int _thinkingKeep = 2000;
  static const int _thinkingLimit = 3000;

  CalibrationPool? _pool;
  CalibrationBank? _bank;
  Future<void>? _initFuture;
  Timer? _flushTimer;
  UploadGuard _guard = UploadGuard.empty();
  int _guardVersion = -1;

  /// 当前正在跑的一轮，用来互斥并让后来的调用等它结束
  Future<RoundOutcome>? _activeRound;

  /// 当前这一轮的取消令牌，用户停手时立即取消请求
  CancelToken? _cancelToken;

  /// 当前这一轮是不是后台整理发起的（手动整理为 false）
  bool _backgroundRound = false;

  /// 用户是否请求过停止，每停一次加一，用来判断 [prepareSession] 从开头
  /// 到起新一轮之间是否被打断
  int _stopCounter = 0;

  /// 进入设置页时的软暂停：只停后台轮，不动已归出的题
  bool _pauseRequested = false;

  /// 后台整理循环是否在跑，避免重复起循环
  bool _autoLoopRunning = false;

  /// 上次没整理出至少 10 题或出错时的池条数，初始 0
  int _lastFailedPoolSize = 0;

  String _thinkingText = '';

  /// 题库或收集池变化时加一，界面据此刷新数量
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// 整理进度，后台整理时界面也看得到
  final ValueNotifier<OrganizeStatus> status = ValueNotifier<OrganizeStatus>(
    const OrganizeStatus(),
  );

  /// 整理时累计的思考文字，超长时才裁掉开头
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
    String categoryId = '',
    String source = '',
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
        categoryId: categoryId,
        source: source,
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
  /// 不够就返回空题目；出错、被费用上限中止或用户取消时按 [RoundOutcome]
  /// 的语义返回 abortedBy 或 cancelled
  Future<RoundOutcome> prepareSession() async {
    // 一开头就记下停止次数：init() 或等上一轮期间用户点了停止，
    // 起来后看到次数变了就不再起新一轮
    final stopCounter = _stopCounter;
    await init();
    // 题库够答时不等后台那一轮，直接用现成的题
    final ready = _bank;
    if (ready != null && ready.length >= calibrationMinQuestions) {
      return RoundOutcome(
        questions: ready.take(calibrationMaxQuestions),
        abortedBy: null,
      );
    }
    final active = _activeRound;
    if (active != null) {
      try {
        await active;
      } catch (_) {
        // 已有那一轮失败不影响重新检查题库
      }
      if (_stopCounter != stopCounter) {
        return const RoundOutcome(
          questions: <CalibrationQuestion>[],
          abortedBy: null,
          cancelled: true,
        );
      }
    }

    final bank = _bank;
    if (bank != null && bank.length >= calibrationMinQuestions) {
      return RoundOutcome(
        questions: bank.take(calibrationMaxQuestions),
        abortedBy: null,
      );
    }

    // 起新一轮前再看一次停止次数：停止可能落在 init() 或等上一轮的时候，
    // 这时直接按用户取消返回，不建令牌也不花接口的钱
    if (_stopCounter != stopCounter) {
      return const RoundOutcome(
        questions: <CalibrationQuestion>[],
        abortedBy: null,
        cancelled: true,
      );
    }

    final outcome = await _organizeOnce();
    // 这一轮被用户停手作废时题目全部丢弃，题库里之前攒的也不拿来答
    if (outcome.cancelled) {
      return const RoundOutcome(
        questions: <CalibrationQuestion>[],
        abortedBy: null,
        cancelled: true,
      );
    }
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

  /// 请求立刻停止当前一轮：取消进行中的请求，这一轮已整理出的题全部丢弃
  ///
  /// 不管此刻有没有登记中的一轮都记一次停止：手动整理可能还在 init() 或
  /// 等上一轮的半路上，[prepareSession] 起来后看到次数变了就不再起新一轮，
  /// 也不会在用户点过停止后再花接口的钱
  void stop() {
    _stopCounter++;
    _cancelToken?.cancel('用户停止');
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

  /// 认知滤网设置页打开的数量，大于 0 时不在后台整理
  int _settingsOpen = 0;

  /// 用户进入认知滤网设置页：后台整理软暂停
  ///
  /// 进入设置页不代表用户不要已经付过钱的整理，所以只让后台轮在下一批
  /// 之前停下，已归出的题照常入库，也不记失败；手动整理不受影响
  void enterSettings() {
    _settingsOpen++;
    _requestSoftPause();
  }

  /// 请求后台轮在下一批之前软暂停，和 [stop] 的硬停是两条路
  void _requestSoftPause() {
    _pauseRequested = true;
  }

  /// 用户离开认知滤网设置页，全部离开后恢复后台整理
  void leaveSettings() {
    if (_settingsOpen > 0) _settingsOpen--;
    if (_settingsOpen == 0) {
      _pauseRequested = false;
      unawaited(_maybeAutoOrganize());
    }
  }

  /// 设置变化后由页面调用，重新判断要不要在后台整理
  ///
  /// 后台开关刚被关掉时，正在跑的后台轮立即硬停，进行中的请求会被取消；
  /// 手动整理不受这个开关影响
  void onSettingsChanged() {
    if (shouldHardStopBackgroundRound(
      autoEnabled: Pref.cfCalibAuto,
      backgroundRound: _backgroundRound,
      running: _activeRound != null,
    )) {
      stop();
    }
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
  ///
  /// [background] 为真表示这是后台循环发起的一轮，受后台开关与设置页
  /// 软暂停影响；手动整理两者都不管
  Future<RoundOutcome> _organizeOnce({
    void Function(int done, int total)? onProgress,
    void Function(String delta)? onThinking,
    bool Function()? shouldCancel,
    bool background = false,
  }) {
    final active = _activeRound;
    if (active != null) {
      return active;
    }
    final cancelToken = CancelToken();
    _cancelToken = cancelToken;
    _backgroundRound = background;
    late final Future<RoundOutcome> future;
    future = _organizeLocked(
      cancelToken: cancelToken,
      background: background,
      onProgress: onProgress,
      onThinking: onThinking,
      shouldCancel: shouldCancel,
    ).whenComplete(() {
      if (identical(_activeRound, future)) {
        _activeRound = null;
        _backgroundRound = false;
        _cancelToken = null;
      }
    });
    _activeRound = future;
    return future;
  }

  Future<RoundOutcome> _organizeLocked({
    required CancelToken cancelToken,
    required bool background,
    void Function(int done, int total)? onProgress,
    void Function(String delta)? onThinking,
    bool Function()? shouldCancel,
  }) async {
    _clearThinking();
    status.value = const OrganizeStatus(running: true);
    try {
      return await _runRoundBody(
        cancelToken: cancelToken,
        background: background,
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
    required CancelToken cancelToken,
    required bool background,
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

    // 题库剩余空间决定这一轮最多出多少题、出多少道才算能用
    final room = calibrationBankRoom(
      bankCap: Pref.cfCalibBankCap,
      bankSize: _bank?.length ?? 0,
    );
    if (room == 0) {
      // 题库已经放不下新题，一条请求也不发
      return const RoundOutcome(
        questions: <CalibrationQuestion>[],
        abortedBy: null,
      );
    }
    final needed = calibrationNeededQuestions(room);
    final maxQuestions = min(calibrationMaxQuestions, room);

    try {
      final client = LlmClient(
        baseUrl: Pref.cfLlmBaseUrl,
        apiKey: apiKey,
        model: Pref.cfLlmModel,
        format: Pref.cfLlmApiFormat,
        // 开着高强度思考（high），一批可能要想一两分钟；超时由用户设置
        timeout: Duration(seconds: Pref.cfLlmTimeout),
        proxy: _currentProxy(),
        cancelToken: cancelToken,
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
        maxQuestions: maxQuestions,
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
        // 费用上限只负责停下并保留已得的题；用户停手与后台开关关掉
        // 都走取消，整轮作废
        shouldStop: () => llmBudgetReached,
        isCancelled: () =>
            cancelToken.isCancelled ||
            (background && !Pref.cfCalibAuto) ||
            (shouldCancel?.call() ?? false),
        shouldPause: background ? () => _pauseRequested : null,
        outputRetries: Pref.cfLlmOutputRetries,
        otherRetries: Pref.cfLlmOtherRetries,
      );
      // 题数不够这一轮需要的数量时不出题，已用掉的内容留在池里等下一轮；
      // 用户停手或后台开关关掉时整轮作废，之前归出的题也不再使用
      final cancelled = result.cancelled;
      final usable = !cancelled && result.questions.length >= needed;
      final removedIds = <String>{
        if (usable) ...result.usedIds,
        ...result.droppedIds,
      };
      pool.removeIds(removedIds);
      await pool.flush();
      if (removedIds.isNotEmpty) {
        _bumpRevision();
      }

      if (cancelled) {
        // 只删掉不外传规则拦下的条目，别的都留在池里；记下池条数，
        // 免得后台循环马上又起一轮
        _lastFailedPoolSize = pool.length;
        return const RoundOutcome(
          questions: <CalibrationQuestion>[],
          abortedBy: null,
          cancelled: true,
        );
      }

      if (usable) {
        final bank = _bank;
        if (bank != null) {
          bank.add(result.questions);
          await bank.flush();
          _bumpRevision();
        }
      } else if (!result.paused) {
        // 软暂停不记失败，离开设置页后才能接着整理
        _lastFailedPoolSize = pool.length;
      }
      // 中途出错也算这次没跑顺，记下池条数免得马上重试
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
    if (_autoLoopRunning || _settingsOpen > 0) {
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
        if (_settingsOpen > 0) {
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
        final outcome = await _organizeOnce(background: true);
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
    _thinkingText = text.length > _thinkingLimit
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

  /// 把回答折算成各内置类别自己的门槛并写入设置
  ///
  /// 每道题归到成员里出现最多的内置类别，每个类别单独拟合；某个类别回答太少
  /// 就不动它。一个类别都没调整时返回空列表
  List<CategoryFit> apply(
    List<({CalibrationAnswer answer, CalibrationQuestion question})> answers,
  ) {
    final categories = <FilterCategory>[
      for (final category in CognitiveFilterConfig.effectiveCategories)
        if (category.builtin && category.enabled) category,
    ];
    final groups =
        <String, List<({CalibrationAnswer answer, List<double> scores})>>{};
    // 没有类别记录的旧题（更新前收集的）无法归类，计入所有已启用的类别
    final unattributed =
        <({CalibrationAnswer answer, List<double> scores})>[];
    for (final entry in answers) {
      final item = (
        answer: entry.answer,
        scores: <double>[
          for (final member in entry.question.members) member.score,
        ],
      );
      final id = _questionCategory(entry.question, categories);
      if (id == null) {
        unattributed.add(item);
      } else {
        groups.putIfAbsent(id, () => []).add(item);
      }
    }

    final fits = <CategoryFit>[];
    for (final category in categories) {
      final group = <({CalibrationAnswer answer, List<double> scores})>[
        ...?groups[category.id],
        ...unattributed,
      ];
      if (group.isEmpty) continue;
      final after = fitThreshold(current: category.threshold, answers: group);
      if (after == null) continue;
      CognitiveFilterConfig.setCategoryThreshold(category.id, after);
      fits.add(
        CategoryFit(
          id: category.id,
          name: category.name,
          before: category.threshold,
          after: after,
        ),
      );
    }
    return fits;
  }

  /// 一道题所属的内置类别：成员里出现最多的那个，按类别 id 认，
  /// 旧数据没有 id 时按类别名认；都认不出来返回 null
  static String? _questionCategory(
    CalibrationQuestion question,
    List<FilterCategory> categories,
  ) {
    final counts = <String, int>{};
    for (final member in question.members) {
      String? id;
      for (final category in categories) {
        if (category.id == member.categoryId ||
            (member.categoryId.isEmpty &&
                member.category.isNotEmpty &&
                category.name == member.category)) {
          id = category.id;
          break;
        }
      }
      if (id != null) counts[id] = (counts[id] ?? 0) + 1;
    }
    String? best;
    var bestCount = 0;
    for (final entry in counts.entries) {
      if (entry.value > bestCount) {
        best = entry.key;
        bestCount = entry.value;
      }
    }
    return best;
  }

  /// 清空收集池与题库，并让各内置类别回到跟随总敏感度
  Future<void> reset() async {
    _flushTimer?.cancel();
    _flushTimer = null;
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
    CognitiveFilterConfig.clearCategoryThresholds();
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
