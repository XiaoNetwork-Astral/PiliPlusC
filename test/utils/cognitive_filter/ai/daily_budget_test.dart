import 'package:PiliPlus/utils/cognitive_filter/ai/daily_budget.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DailyUsageBudget', () {
    late DateTime now;
    late DailyUsage stored;
    late int saves;

    DailyUsageBudget build(double cap) {
      return DailyUsageBudget(
        capUsd: () => cap,
        now: () => now,
        load: () => stored,
        save: (usage) {
          stored = usage;
          saves++;
        },
      );
    }

    setUp(() {
      now = DateTime(2024, 5, 6, 12);
      stored = const DailyUsage(day: '2024-05-06');
      saves = 0;
    });

    test('跨天时先清零再判断', () {
      stored = const DailyUsage(day: '2024-05-05', inputTokens: 2000000);
      final budget = build(1);

      expect(budget.canSpend(), isTrue);
      expect(saves, 1);
      expect(stored.day, '2024-05-06');
      expect(stored.inputTokens, 0);
      expect(budget.today.inputTokens, 0);
    });

    test('输入费用达到上限后不能再花费', () {
      const input = 1000000;
      stored = const DailyUsage(day: '2024-05-06', inputTokens: input);
      var cap = 1.0;
      final budget = DailyUsageBudget(
        capUsd: () => cap,
        now: () => now,
        load: () => stored,
        save: (usage) => stored = usage,
      );
      // 上限与当前费用完全相等，验证「大于等于」才算超限
      cap = budget.usdToday;

      expect(budget.canSpend(), isFalse);
    });

    test('输入费用未达上限仍可花费', () {
      stored = const DailyUsage(day: '2024-05-06', inputTokens: 999999);
      final budget = build(1);

      expect(budget.canSpend(), isTrue);
    });

    test('上限为 0 表示不限制', () {
      stored = const DailyUsage(day: '2024-05-06', inputTokens: 1000000000);
      final budget = build(0);

      expect(budget.canSpend(), isTrue);
    });

    test('负数上限按 0 处理，不限制', () {
      stored = const DailyUsage(day: '2024-05-06', inputTokens: 1000000000);
      final budget = build(-5);

      expect(budget.canSpend(), isTrue);
    });

    test('上限变化立即生效', () {
      stored = const DailyUsage(day: '2024-05-06', inputTokens: 1000000);
      var cap = 1.0;
      final budget = DailyUsageBudget(
        capUsd: () => cap,
        now: () => now,
        load: () => stored,
        save: (usage) => stored = usage,
      );

      expect(budget.canSpend(), isTrue);
      cap = budget.usdToday;
      expect(budget.canSpend(), isFalse);
    });

    test('record 累加 token，每次调用保存一次', () {
      final budget = build(1);

      budget.record(inputTokens: 100, outputTokens: 10);
      budget.record(inputTokens: 200, outputTokens: 20);

      expect(stored.day, '2024-05-06');
      expect(stored.inputTokens, 300);
      expect(saves, 2);
      expect(budget.usdToday, closeTo(300 * 0.042 / 1e6, 1e-15));
    });

    test('record 跨天先清零再累加', () {
      stored = const DailyUsage(day: '2024-05-05', inputTokens: 500);
      final budget = build(1);

      budget.record(inputTokens: 10, outputTokens: 2);

      expect(stored.day, '2024-05-06');
      expect(stored.inputTokens, 10);
      expect(saves, 1);
    });
  });
}
