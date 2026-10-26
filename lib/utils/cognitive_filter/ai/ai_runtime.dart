import 'dart:async';
import 'dart:io';

import 'package:PiliPlus/models/cognitive_filter/config.dart';
import 'package:PiliPlus/models/cognitive_filter/filter_category.dart';
import 'package:PiliPlus/models/cognitive_filter/filter_surface.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/ai_whitelist.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/calibration/calibration_service.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/daily_budget.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/judge_cache.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/judge_history.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/judge_service.dart';
import 'package:PiliPlus/utils/cognitive_filter/block_stats.dart';
import 'package:PiliPlus/utils/cognitive_filter/jev_client.dart';
import 'package:PiliPlus/utils/cognitive_filter/jev_proxy.dart';
import 'package:PiliPlus/utils/path_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:path/path.dart' as path;

/// 简单文本文件读写，所有异常都吞掉
class FileTextStore {
  FileTextStore(this.path);

  final String path;

  /// 读文件；文件不存在或读取失败返回 null
  Future<String?> read() async {
    try {
      final file = File(path);
      if (!file.existsSync()) {
        return null;
      }
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }

  /// 先写临时文件再替换，避免写到一半损坏原文件
  Future<void> write(String text) async {
    try {
      final file = File(path);
      await file.parent.create(recursive: true);
      final tmp = File('$path.tmp');
      await tmp.writeAsString(text, flush: true);
      await tmp.rename(path);
    } catch (_) {
      // 落盘失败时保留原文件，下次再试
    }
  }
}

/// 用文件实现判定缓存存储
class FileJudgeCacheStore implements JudgeCacheStore {
  FileJudgeCacheStore(String path) : _file = FileTextStore(path);

  final FileTextStore _file;

  @override
  Future<String?> read() => _file.read();

  @override
  Future<void> write(String json) => _file.write(json);
}

/// 认知滤网 AI 屏蔽的运行时接线
class AiFilterRuntime {
  AiFilterRuntime._();

  static final AiFilterRuntime instance = AiFilterRuntime._();

  static const String _dirName = 'cognitive_filter';
  static const String _cacheFileName = 'judge_cache.json';
  static const String _historyFileName = 'judge_history.json';
  static const Duration _flushDelay = Duration(seconds: 5);
  static const int _ruleDedupWindow = 300;
  static const int _ruleRateLimit = 20;
  static const Duration _ruleRateWindow = Duration(seconds: 1);
  static const Duration _failureToastWindow = Duration(seconds: 20);

  /// 每种失败提示最近一次弹出的时间，用于 20 秒去重
  final Map<String, DateTime> _lastFailureToastAt = <String, DateTime>{};

  /// 命中白名单的条目不送 AI，直接视为不屏蔽
  static const JudgeVerdict _whitelistVerdict = JudgeVerdict(
    blocked: false,
    categoryId: null,
    score: 0,
    source: JudgeSource.disabled,
  );

  /// 正在等待 AI 判定的列表类请求数，界面据此显示"AI 判定中"
  final ValueNotifier<int> busy = ValueNotifier<int>(0);

  /// 全屏期间有评论/相关视频被暂缓送 AI；退出全屏后视频页据此补判一次
  bool deferredWhileFullscreen = false;

  JudgeService? _service;
  JudgeCache? _cache;
  JudgeHistory? _history;
  FileTextStore? _historyStore;
  DailyUsageBudget? _budget;
  Timer? _flushTimer;
  Future<void>? _initFuture;

  /// 各适用面最近一秒内的规则屏蔽时间，用于限速
  final Map<FilterSurface, List<DateTime>> _ruleBlockTimes = {};

  /// 初始化缓存、历史与判定服务；可重复调用，失败时保持未激活
  Future<void> init() => _initFuture ??= _doInit();

  Future<void> _doInit() async {
    try {
      final dir = path.join(appSupportDirPath, _dirName);
      final directory = Directory(dir);
      if (!directory.existsSync()) {
        await directory.create(recursive: true);
      }

      final cache = JudgeCache(
        store: FileJudgeCacheStore(path.join(dir, _cacheFileName)),
      );
      await cache.load();

      final historyStore = FileTextStore(path.join(dir, _historyFileName));
      final history = JudgeHistory();
      history.loadJson(await historyStore.read() ?? '');

      final budget = DailyUsageBudget(
        capUsd: () => Pref.cfAiDailyCapUsd,
        now: DateTime.now,
        load: _loadUsage,
        save: _saveUsage,
      );
      final service = JudgeService(
        transport: _transport,
        model: Pref.cfApiModel,
        cache: cache,
        budget: budget,
      );

      _cache = cache;
      _history = history;
      _historyStore = historyStore;
      _budget = budget;
      _service = service;
      unawaited(CalibrationService.instance.init());
    } catch (_) {
      _service = null;
      _cache = null;
      _history = null;
      _historyStore = null;
      _budget = null;
    }
  }

  /// 每次请求都重新读取接口设置，用户改完立即生效
  Future<Map<String, dynamic>> _transport(Map<String, dynamic> body) {
    final transport = JevClient.makeTransport(
      endpoint: Pref.cfApiBaseUrl,
      apiKey: Pref.cfApiKey,
      model: Pref.cfApiModel,
      timeout: Duration(seconds: Pref.cfApiTimeout),
      proxy: _currentProxy(),
    );
    return transport(body);
  }

  /// 当前设置对应的代理，未启用或地址非法时返回 null（直连）
  JevProxy? _currentProxy() {
    final type = switch (Pref.cfApiProxyType) {
      1 => JevProxyType.http,
      2 => JevProxyType.socks5,
      _ => JevProxyType.none,
    };
    return JevProxy.parse(type, Pref.cfApiProxyAddress);
  }

  /// 开关、Key 与至少一个启用类别都满足时才算激活
  bool get active {
    if (_service == null) {
      return false;
    }
    if (!Pref.cfAiFilterEnabled) {
      return false;
    }
    if (Pref.cfApiKey.trim().isEmpty) {
      return false;
    }
    return _enabledCategories().isNotEmpty;
  }

  /// 该适用面是否处于激活状态
  bool isActiveFor(FilterSurface surface) {
    if (!active) {
      return false;
    }
    if (!Pref.cfAiSurfaces.contains(surface)) {
      return false;
    }
    return _enabledCategories().any(
      (category) => category.surfaces.contains(surface),
    );
  }

  /// 判定一批内容；未激活时返回 null，内部异常同样返回 null
  Future<JudgeResult?> judge({
    required FilterSurface surface,
    required List<JudgeItem> items,
    String title = '',
    String context = '',
  }) {
    return _judge(
      surface: surface,
      items: items,
      title: title,
      context: context,
      recordHistory: true,
      applyWhitelist: true,
      trial: false,
    );
  }

  /// [trial] 为 true 时失败提示不受 20 秒去重限制
  Future<JudgeResult?> _judge({
    required FilterSurface surface,
    required List<JudgeItem> items,
    required String title,
    required String context,
    required bool recordHistory,
    required bool applyWhitelist,
    required bool trial,
  }) async {
    try {
      if (!isActiveFor(surface)) {
        return null;
      }
      final service = _service;
      if (service == null) {
        return null;
      }
      final whitelist = AiWhitelist.instance;
      final pending = <JudgeItem>[];
      final whitelisted = <String>{};
      if (applyWhitelist) {
        for (final item in items) {
          if (whitelist.matches(
            surface: surface,
            text: item.text,
            mid: item.mid,
            midHash: item.midHash,
          )) {
            whitelisted.add(item.id);
          } else {
            pending.add(item);
          }
        }
      } else {
        pending.addAll(items);
      }
      if (whitelisted.isNotEmpty && pending.isEmpty) {
        return JudgeResult(
          verdicts: <String, JudgeVerdict>{
            for (final item in items) item.id: _whitelistVerdict,
          },
          stats: JudgeStats(),
        );
      }
      // 弹幕有自己的提示，这里只统计列表类适用面
      final countBusy = surface != FilterSurface.danmaku;
      if (countBusy) busy.value++;
      final JudgeResult result;
      try {
        result = await service.judge(
          surface: surface,
          items: whitelisted.isEmpty ? items : pending,
          categories: _enabledCategories(),
          // 说明取全部内置类别的有效定义（含用户改动），不只是启用的
          builtinDefinitions: CognitiveFilterConfig.effectiveCategories
              .where((category) => category.builtin)
              .toList(),
          title: title,
          context: context,
        );
      } finally {
        if (countBusy) busy.value--;
      }
      if (result.stats.failedRequests > 0) {
        _notifyFailure(result.stats.lastError, trial: trial);
      }
      for (final id in whitelisted) {
        result.verdicts[id] = _whitelistVerdict;
      }

      if (recordHistory) {
        var blocked = 0;
        for (final verdict in result.verdicts.values) {
          if (verdict.blocked) blocked++;
        }
        BlockStats.instance.add(blocked);
      }

      final history = recordHistory ? _history : null;
      if (history != null) {
        final texts = <String, String>{
          for (final item in items) item.id: item.text,
        };
        final itemsById = <String, JudgeItem>{
          for (final item in items) item.id: item,
        };
        final time = DateTime.now();
        result.verdicts.forEach((id, verdict) {
          if (!verdict.blocked) {
            return;
          }
          // 同一内容反复出现（比如每次刷新首页）不重复记录
          final text = texts[id] ?? '';
          if (_recentAiEntry(history, surface, text)) {
            return;
          }
          final item = itemsById[id];
          Map<String, dynamic>? snapshot;
          final builder = item?.snapshotBuilder;
          if (builder != null) {
            try {
              snapshot = builder();
              if (snapshot.isEmpty) {
                snapshot = null;
              }
            } catch (_) {
              // 快照失败不影响判定与屏蔽
              snapshot = null;
            }
          }
          history.add(
            JudgeHistoryEntry(
              time: time,
              surface: surface.label,
              text: text,
              categoryId: verdict.categoryId,
              score: verdict.score,
              label: _categoryName(verdict.categoryId),
              scores: verdict.scores.isEmpty ? null : verdict.scores,
              meta: item?.meta,
              snapshot: snapshot,
            ),
          );
        });
      }

      // 得分偏高的内容静默存进校准向导的收集池，只存本机
      if (recordHistory && !trial) {
        final calibration = CalibrationService.instance;
        for (final item in items) {
          final verdict = result.verdicts[item.id];
          if (verdict == null ||
              (verdict.source != JudgeSource.ai &&
                  verdict.source != JudgeSource.cache)) {
            continue;
          }
          calibration.collect(
            surface: surface,
            text: item.text,
            score: verdict.score,
            category: _categoryName(verdict.categoryId),
          );
        }
      }

      _scheduleFlush();
      return result;
    } catch (_) {
      return null;
    }
  }

  /// 最近的历史里是否已有同一适用面的同一条 AI 屏蔽记录
  bool _recentAiEntry(
    JudgeHistory history,
    FilterSurface surface,
    String text,
  ) {
    final entryText = JudgeHistoryEntry.truncateText(text);
    var checked = 0;
    for (final entry in history.entries) {
      if (checked++ >= _ruleDedupWindow) {
        break;
      }
      if (!entry.isRule &&
          entry.surface == surface.label &&
          entry.text == entryText) {
        return true;
      }
    }
    return false;
  }

  /// 试判定一段文字，不写入屏蔽历史；未启用或请求失败返回 null
  Future<JudgeVerdict?> trial({
    required FilterSurface surface,
    required String text,
    String context = '',
  }) async {
    const id = 'trial';
    final result = await _judge(
      surface: surface,
      items: [JudgeItem(id: id, text: text)],
      title: '',
      context: context,
      recordHistory: false,
      applyWhitelist: false,
      trial: true,
    );
    return result?.verdicts[id];
  }

  /// 判定失败时提示用户；非试判定时同一文本 20 秒内只提示一次
  void _notifyFailure(String? error, {required bool trial}) {
    final text = error == null || error.isEmpty ? '未知错误' : error;
    if (!trial) {
      final now = DateTime.now();
      final last = _lastFailureToastAt[text];
      if (last != null && now.difference(last) < _failureToastWindow) {
        return;
      }
      _lastFailureToastAt[text] = now;
    }
    try {
      SmartDialog.showToast('AI 屏蔽失败：$text');
    } catch (_) {
      // 界面未就绪时不打断判定流程
    }
  }

  /// 记一条规则屏蔽；[ruleType] 是规则类型名，[content] 是命中的规则内容
  ///
  /// 最近 300 条里同一（适用面、文字、规则 id）只记一次；同一适用面
  /// 每秒最多记 20 条，避免弹幕批量拉取时刷屏。
  void recordRuleBlock({
    required FilterSurface surface,
    required String text,
    required String ruleType,
    required String content,
    String? ruleId,
  }) {
    // 统计按命中次数算，不受历史去重和限速影响
    BlockStats.instance.add();
    final history = _history;
    if (history == null) {
      return;
    }
    final now = DateTime.now();
    final times = _ruleBlockTimes[surface] ??= <DateTime>[];
    times.removeWhere((time) => now.difference(time) >= _ruleRateWindow);
    if (times.length >= _ruleRateLimit) {
      return;
    }
    final entryText = JudgeHistoryEntry.truncateText(text);
    var checked = 0;
    for (final entry in history.entries) {
      if (checked++ >= _ruleDedupWindow) {
        break;
      }
      if (entry.isRule &&
          entry.surface == surface.label &&
          entry.text == entryText &&
          entry.ruleId == ruleId) {
        return;
      }
    }
    times.add(now);
    history.add(
      JudgeHistoryEntry(
        time: now,
        surface: surface.label,
        text: text,
        score: 1,
        kind: JudgeHistoryEntry.rule,
        label: content,
        ruleType: ruleType,
        ruleId: ruleId,
      ),
    );
    _scheduleFlush();
  }

  String _categoryName(String? id) {
    if (id == null) {
      return '';
    }
    for (final category in CognitiveFilterConfig.effectiveCategories) {
      if (category.id == id) {
        return category.name;
      }
    }
    return '';
  }

  /// 最近的历史记录，最新在前
  List<JudgeHistoryEntry> get history =>
      _history?.entries ?? const <JudgeHistoryEntry>[];

  void clearHistory() {
    _history?.clear();
    _scheduleFlush();
  }

  double get usdToday => _budget?.usdToday ?? 0;

  void resetBreaker() {
    _service?.resetBreaker();
  }

  /// 清除 AI 判定缓存并复位熔断器
  Future<void> clearCache() async {
    final cache = _cache;
    if (cache != null) {
      try {
        await cache.clear();
      } catch (_) {
        // 落盘失败时内存已经清空，下次仍会覆盖
      }
    }
    resetBreaker();
  }

  /// 立即把缓存与历史写到磁盘，供退出或暂停时调用
  Future<void> flush() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    try {
      final cache = _cache;
      if (cache != null && cache.dirty) {
        await cache.flush();
      }
    } catch (_) {
      // 缓存落盘失败下次再试
    }
    try {
      final history = _history;
      final store = _historyStore;
      if (history != null && store != null && history.dirty) {
        await store.write(history.toJson());
        history.markClean();
      }
    } catch (_) {
      // 历史落盘失败下次再试
    }
  }

  void _scheduleFlush() {
    if (_flushTimer?.isActive ?? false) {
      return;
    }
    final dirty = (_cache?.dirty ?? false) || (_history?.dirty ?? false);
    if (!dirty) {
      return;
    }
    _flushTimer = Timer(_flushDelay, () {
      _flushTimer = null;
      unawaited(flush());
    });
  }

  List<FilterCategory> _enabledCategories() {
    try {
      return <FilterCategory>[
        for (final category in CognitiveFilterConfig.effectiveCategories)
          if (category.enabled) category,
      ];
    } catch (_) {
      return const <FilterCategory>[];
    }
  }

  DailyUsage _loadUsage() {
    return DailyUsage(
      day: Pref.cfAiUsageDay,
      inputTokens: Pref.cfAiUsageInputTokens,
    );
  }

  void _saveUsage(DailyUsage usage) {
    Pref.cfAiUsageDay = usage.day;
    Pref.cfAiUsageInputTokens = usage.inputTokens;
  }
}
