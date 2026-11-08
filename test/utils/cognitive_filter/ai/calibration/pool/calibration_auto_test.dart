import 'package:PiliPlus/utils/cognitive_filter/ai/calibration/calibration_auto.dart';
import 'package:flutter_test/flutter_test.dart';

/// 所有条件都满足时的基线，单项测试只改关心的参数
bool _should({
  bool autoEnabled = true,
  bool hasKey = true,
  bool running = false,
  bool budgetReached = false,
  int bankSize = 10,
  int bankCap = 60,
  int poolSize = 30,
  int lastFailedPoolSize = 0,
}) => shouldAutoOrganize(
  autoEnabled: autoEnabled,
  hasKey: hasKey,
  running: running,
  budgetReached: budgetReached,
  bankSize: bankSize,
  bankCap: bankCap,
  poolSize: poolSize,
  lastFailedPoolSize: lastFailedPoolSize,
);

void main() {
  test('全部条件满足才整理', () {
    expect(_should(), isTrue);
  });

  test('自动整理关闭、没有密钥、正在跑、到费用上限时不整理', () {
    expect(_should(autoEnabled: false), isFalse);
    expect(_should(hasKey: false), isFalse);
    expect(_should(running: true), isFalse);
    expect(_should(budgetReached: true), isFalse);
  });

  test('剩余空间至少 10 题才整理，正好 10 题可以', () {
    expect(_should(bankSize: 50, bankCap: 60), isTrue); // 剩 10
    expect(_should(bankSize: 51, bankCap: 60), isFalse); // 剩 9
  });

  test('题库到上限或已超过上限后暂停', () {
    expect(_should(bankSize: 60, bankCap: 60), isFalse); // 剩 0
    expect(_should(bankSize: 61, bankCap: 60), isFalse); // 剩负数按 0
  });

  test('池不足 30 条不整理，刚好 30 条整理', () {
    expect(_should(poolSize: 29), isFalse);
    expect(_should(poolSize: 30), isTrue);
  });

  test('池比上次失败时多不足 10 条不整理', () {
    expect(_should(poolSize: 30, lastFailedPoolSize: 21), isFalse);
    expect(_should(poolSize: 30, lastFailedPoolSize: 20), isTrue);
    expect(_should(poolSize: 40, lastFailedPoolSize: 30), isTrue);
    expect(_should(poolSize: 39, lastFailedPoolSize: 30), isFalse);
  });

  test('上次失败时池为空，攒到 30 条就整理', () {
    expect(_should(poolSize: 30, lastFailedPoolSize: 0), isTrue);
  });

  test('任一条件不满足就为假', () {
    expect(
      _should(
        autoEnabled: true,
        hasKey: true,
        running: false,
        budgetReached: false,
        bankSize: 0,
        bankCap: 60,
        poolSize: 100,
        lastFailedPoolSize: 0,
      ),
      isTrue,
    );
    expect(_should(autoEnabled: false, bankSize: 0, poolSize: 100), isFalse);
    expect(_should(running: true, bankSize: 0, poolSize: 100), isFalse);
    expect(_should(bankSize: 60, bankCap: 60, poolSize: 100), isFalse);
    expect(_should(poolSize: 100, lastFailedPoolSize: 95), isFalse);
  });

  group('题库剩余空间', () {
    test('空间按上限减题库算，负数与 0 都归零', () {
      expect(calibrationBankRoom(bankCap: 60, bankSize: 50), 10);
      expect(calibrationBankRoom(bankCap: 60, bankSize: 59), 1);
      expect(calibrationBankRoom(bankCap: 60, bankSize: 60), 0);
      expect(calibrationBankRoom(bankCap: 60, bankSize: 70), 0);
      expect(calibrationBankRoom(bankCap: 10, bankSize: 0), 10);
    });

    test('一轮可用题数取 10 与剩余空间的较小值', () {
      expect(calibrationNeededQuestions(0), 0);
      expect(calibrationNeededQuestions(1), 1);
      expect(calibrationNeededQuestions(3), 3);
      expect(calibrationNeededQuestions(9), 9);
      expect(calibrationNeededQuestions(10), 10);
      expect(calibrationNeededQuestions(20), 10);
      expect(calibrationNeededQuestions(-1), 0);
    });

    test('小上限时按剩下的几道题算，门槛仍然只有 10', () {
      final room = calibrationBankRoom(bankCap: 10, bankSize: 7);
      expect(room, 3);
      expect(calibrationNeededQuestions(room), 3);
      // 上限只有 10 题时，空题库刚好够一轮
      expect(_should(bankCap: 10, bankSize: 0), isTrue);
      expect(_should(bankCap: 10, bankSize: 1), isFalse);
    });

    test('上限压到题库之下时没有空间，也不会生成新题', () {
      final room = calibrationBankRoom(bankCap: 30, bankSize: 45);
      expect(room, 0);
      expect(calibrationNeededQuestions(room), 0);
    });
  });

  group('后台开关硬停', () {
    test('开关关掉时只硬停正在跑的后台轮', () {
      expect(
        shouldHardStopBackgroundRound(
          autoEnabled: false,
          backgroundRound: true,
          running: true,
        ),
        isTrue,
      );
      // 手动轮不受开关影响
      expect(
        shouldHardStopBackgroundRound(
          autoEnabled: false,
          backgroundRound: false,
          running: true,
        ),
        isFalse,
      );
      // 开关还开着，或没有在跑，就不需要停
      expect(
        shouldHardStopBackgroundRound(
          autoEnabled: true,
          backgroundRound: true,
          running: true,
        ),
        isFalse,
      );
      expect(
        shouldHardStopBackgroundRound(
          autoEnabled: false,
          backgroundRound: true,
          running: false,
        ),
        isFalse,
      );
    });
  });
}
