import 'dart:async';

import 'package:PiliPlus/models/cognitive_filter/filter_surface.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/ai_runtime.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/calibration/calibration_models.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/calibration/calibration_pool.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/calibration/calibration_round.dart'
    as round;
import 'package:PiliPlus/utils/cognitive_filter/ai/calibration/guard_rules_source.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/calibration/llm_client.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/calibration/threshold_fit.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/calibration/upload_guard.dart';
import 'package:PiliPlus/utils/cognitive_filter/jev_proxy.dart';
import 'package:PiliPlus/utils/cognitive_filter/raw_error.dart';
import 'package:PiliPlus/utils/path_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:path/path.dart' as path;

/// 一轮整理的结果
class RoundOutcome {
  const RoundOutcome({
    required this.questions,
    required this.abortedBy,
    this.abortMessage,
    required this.refusedChunks,
  });

  /// 这一轮整理出的题目
  final List<CalibrationQuestion> questions;

  /// 非空表示这一轮因密钥、网络、限流、服务端、超时或用量上限中止
  final LlmErrorKind? abortedBy;

  /// 中止时最后那个异常的原始说明，供界面直接显示
  final String? abortMessage;

  /// 服务商拒绝或返回无法解析而丢弃的批数
  final int refusedChunks;
}

/// 校准向导的运行时服务
///
/// 平时静默收集高分内容，用户点开始整理后调用整理接口归类并生成题目，
/// 答完后把用户的回答折算成门槛调整量。
class CalibrationService {
  CalibrationService._();

  static final CalibrationService instance = CalibrationService._();

  static const String _dirName = 'cognitive_filter';
  static const String _poolFileName = 'calibration_pool.json';
  static const Duration _flushDelay = Duration(seconds: 5);

  CalibrationPool? _pool;
  Future<void>? _initFuture;
  Timer? _flushTimer;
  UploadGuard _guard = UploadGuard.empty();
  int _guardVersion = -1;

  /// 初始化收集池；可重复调用，失败时保持未激活
  Future<void> init() => _initFuture ??= _doInit();

  Future<void> _doInit() async {
    try {
      final directory = path.join(appSupportDirPath, _dirName);
      final pool = CalibrationPool(
        store: FileJudgeCacheStore(path.join(directory, _poolFileName)),
        isBlockedForUpload: _isBlockedForUpload,
      );
      await pool.load();
      _pool = pool;
    } catch (_) {
      _pool = null;
    }
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
        _scheduleFlush();
      }
    } catch (_) {
      // 收集是旁路，失败不影响判定主流程
    }
  }

  /// 跑一轮整理，结束后删掉已成为题目与确定处理不了的池条目
  Future<RoundOutcome> runRound({
    void Function(int done, int total)? onProgress,
  }) async {
    final apiKey = Pref.cfLlmApiKey.trim();
    if (apiKey.isEmpty) {
      return const RoundOutcome(
        questions: <CalibrationQuestion>[],
        abortedBy: LlmErrorKind.auth,
        abortMessage: '未填写 API Key',
        refusedChunks: 0,
      );
    }

    // 今日整理接口的 token 额度用完了，这一轮直接不发请求
    if (llmBudgetReached) {
      return const RoundOutcome(
        questions: <CalibrationQuestion>[],
        abortedBy: LlmErrorKind.budget,
        abortMessage: '已达今日用量上限',
        refusedChunks: 0,
      );
    }

    await init();
    final pool = _pool;
    if (pool == null) {
      return const RoundOutcome(
        questions: <CalibrationQuestion>[],
        abortedBy: LlmErrorKind.network,
        refusedChunks: 0,
      );
    }

    try {
      final client = LlmClient(
        baseUrl: Pref.cfLlmBaseUrl,
        apiKey: apiKey,
        model: Pref.cfLlmModel,
        // 开着最高强度思考，一批可能要想一两分钟
        timeout: const Duration(seconds: 240),
        proxy: _currentProxy(),
        onUsage: _recordLlmUsage,
      );
      final result = await round.runRound(
        pool: pool.items,
        chat: client.chat,
        isBlockedForUpload: _isBlockedForUpload,
        onProgress: onProgress,
        shouldStop: () => llmBudgetReached,
      );
      pool.removeIds(<String>{...result.usedIds, ...result.droppedIds});
      await pool.flush();
      return RoundOutcome(
        questions: result.questions,
        abortedBy: result.abortedBy,
        abortMessage: result.abortMessage,
        refusedChunks: result.refusedChunks,
      );
    } catch (error) {
      return RoundOutcome(
        questions: const <CalibrationQuestion>[],
        abortedBy: LlmErrorKind.network,
        abortMessage: error is LlmException
            ? error.message
            : truncateError(redactSecrets(error.toString())),
        refusedChunks: 0,
      );
    }
  }

  /// 整理接口今天的 token 用量；跨天时把存储的日期改成今天并清零
  int get llmTokensToday {
    final day = _dayKey(DateTime.now());
    if (Pref.cfLlmUsageDay != day) {
      Pref.cfLlmUsageDay = day;
      Pref.cfLlmUsageTokens = 0;
      return 0;
    }
    return Pref.cfLlmUsageTokens;
  }

  /// 整理接口今天的用量是否已到上限；上限为 0 表示不限制
  bool get llmBudgetReached {
    final cap = Pref.cfLlmDailyCapTokens;
    return cap > 0 && llmTokensToday >= cap;
  }

  /// 累加整理接口的 token 用量，跨天时从 0 开始记
  void _recordLlmUsage(int totalTokens) {
    final day = _dayKey(DateTime.now());
    final base = Pref.cfLlmUsageDay == day ? Pref.cfLlmUsageTokens : 0;
    Pref.cfLlmUsageDay = day;
    Pref.cfLlmUsageTokens = base + (totalTokens < 0 ? 0 : totalTokens);
  }

  /// 本地日期，格式 yyyy-MM-dd，与用量存储保持一致
  static String _dayKey(DateTime time) {
    final month = time.month.toString().padLeft(2, '0');
    final day = time.day.toString().padLeft(2, '0');
    return '${time.year}-$month-$day';
  }

  /// 把回答折算成门槛调整量并写入设置
  ///
  /// 回答太少时不做改动，[after] 为 null
  ({double before, double? after}) apply(
    List<({CalibrationAnswer answer, CalibrationQuestion question})> answers,
  ) {
    final base = Pref.cfProThreshold;
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

  /// 清空收集池并复位门槛调整量
  Future<void> reset() async {
    _flushTimer?.cancel();
    _flushTimer = null;
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
    Pref.cfAiThresholdDelta = 0.0;
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
