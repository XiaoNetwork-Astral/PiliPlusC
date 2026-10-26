import 'dart:async';

import 'package:PiliPlus/utils/cognitive_filter/block_stats_core.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/foundation.dart';

/// 屏蔽统计的读写入口
///
/// 累计条数与起始日期存在 [Pref] 里，读到的 [total] 包含尚未落盘的改动；
/// 落盘失败只吞掉异常，不影响调用方。
class BlockStats {
  BlockStats._();

  static final BlockStats instance = BlockStats._();

  /// 落盘或清零后自增，供界面刷新
  final ValueNotifier<int> version = ValueNotifier<int>(0);

  late final BlockStatsCore _core = BlockStatsCore(
    loadCount: () {
      try {
        return Pref.cfStatsBlocked;
      } catch (_) {
        return 0;
      }
    },
    loadSince: () {
      try {
        return Pref.cfStatsSince;
      } catch (_) {
        return '';
      }
    },
    save: (count, since) {
      try {
        Pref.cfStatsBlocked = count;
        Pref.cfStatsSince = since;
      } catch (_) {
        // 落盘失败不影响调用方
      }
    },
  );

  Timer? _flushTimer;

  /// 累计屏蔽条数，包含尚未落盘的改动
  int get total {
    try {
      return _core.total;
    } catch (_) {
      return 0;
    }
  }

  /// 从第一次统计起的天数（同一天为 1）；还没开始统计为 0
  int get days {
    try {
      return _core.days;
    } catch (_) {
      return 0;
    }
  }

  /// 累计屏蔽 [n] 条，3 秒内的多次调用合并成一次落盘
  void add([int n = 1]) {
    if (n <= 0) {
      return;
    }
    try {
      _core.add(n);
      _flushTimer ??= Timer(const Duration(seconds: 3), _flush);
    } catch (_) {
      // 统计失败不影响屏蔽流程
    }
  }

  /// 清零并立即落盘，同时刷新界面
  void reset() {
    try {
      _core.reset();
    } catch (_) {
      // 清零落盘失败也要刷新界面
    }
    _flushTimer?.cancel();
    _flushTimer = null;
    _bump();
  }

  /// 立即落盘，供退出或进入后台时调用
  void flush() {
    _flushTimer?.cancel();
    _flush();
  }

  void _flush() {
    _flushTimer = null;
    try {
      _core.flushIfDirty();
    } catch (_) {
      // 落盘失败，等下次 add 再试
    }
    _bump();
  }

  void _bump() {
    try {
      version.value = version.value + 1;
    } catch (_) {
      // 界面已销毁时忽略
    }
  }
}
