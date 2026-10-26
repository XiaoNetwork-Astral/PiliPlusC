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

  test('题库到上限后暂停，未到上限继续', () {
    expect(_should(bankSize: 60, bankCap: 60), isFalse);
    expect(_should(bankSize: 61, bankCap: 60), isFalse);
    expect(_should(bankSize: 59, bankCap: 60), isTrue);
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
}
