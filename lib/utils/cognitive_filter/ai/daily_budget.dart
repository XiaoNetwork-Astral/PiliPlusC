import 'package:PiliPlus/utils/cognitive_filter/ai/judge_service.dart';
import 'package:PiliPlus/utils/cognitive_filter/block_stats_core.dart';

/// 一天的本机用量
class DailyUsage {
  const DailyUsage({this.day = '', this.inputTokens = 0});

  /// 用量所属的本地日期，格式 yyyy-MM-dd
  final String day;

  final int inputTokens;

  DailyUsage copyWith({String? day, int? inputTokens}) {
    return DailyUsage(
      day: day ?? this.day,
      inputTokens: inputTokens ?? this.inputTokens,
    );
  }
}

/// 按本地日期与输入 token 费用限制每日用量
///
/// 只依赖注入的读写函数，便于脱离 Flutter/Hive 单独测试。
class DailyUsageBudget implements JudgeBudget {
  DailyUsageBudget({
    required this.capUsd,
    required this.now,
    required this.load,
    required this.save,
  });

  /// 每日上限（美元），每次读取以便设置变化立即生效；≤ 0 表示不限制
  final double Function() capUsd;

  /// 当前时间，用于判断是否跨天
  final DateTime Function() now;

  /// 读取本机存储的用量
  final DailyUsage Function() load;

  /// 保存本机用量
  final void Function(DailyUsage usage) save;

  @override
  bool canSpend() {
    final day = dayKeyOf(now());
    var usage = load();
    if (usage.day != day) {
      usage = DailyUsage(day: day);
      save(usage);
    }
    final cap = capUsd();
    if (!cap.isFinite || cap <= 0) {
      return true;
    }
    return _usdOf(usage.inputTokens) < cap;
  }

  @override
  void record({required int inputTokens, required int outputTokens}) {
    final day = dayKeyOf(now());
    final stored = load();
    final base = stored.day == day ? stored : DailyUsage(day: day);
    save(
      DailyUsage(
        day: day,
        inputTokens: base.inputTokens + _nonNegative(inputTokens),
      ),
    );
  }

  /// 今天的用量，跨天时返回清零后的值
  DailyUsage get today {
    final day = dayKeyOf(now());
    final usage = load();
    return usage.day == day ? usage : DailyUsage(day: day);
  }

  /// 今天已花的输入费用（美元），输出 token 免费
  double get usdToday => _usdOf(today.inputTokens);

  static double _usdOf(int inputTokens) =>
      inputTokens.toDouble() * 0.042 / 1e6;

  static int _nonNegative(int value) => value < 0 ? 0 : value;
}
