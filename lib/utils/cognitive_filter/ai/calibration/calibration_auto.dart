import 'package:PiliPlus/utils/cognitive_filter/ai/calibration/calibration_models.dart';

/// 池里至少这么多条才值得自动整理
///
/// 一轮至少 10 题、每题至少 3 条，30 是算术下限，不直接展示给用户
const int calibrationAutoMinPool = 30;

/// 上次失败后池里要再多出这么多条才重试，避免对同一堆内容反复花钱
const int calibrationAutoRetryGrowth = 10;

/// 题库还能再放多少题；已经达到或超过上限时按 0 算
///
/// 用户把上限调到当前题库之下时也返回 0，已有的题不受影响
int calibrationBankRoom({required int bankCap, required int bankSize}) {
  final room = bankCap - bankSize;
  return room > 0 ? room : 0;
}

/// 一轮至少要出这么多题才算能用
///
/// 题库快满时按剩余空间算，剩下的几道题也能照常入库；
/// [room] 为 0 时返回 0，调用方据此不发起整理
int calibrationNeededQuestions(int room) {
  final safeRoom = room > 0 ? room : 0;
  return safeRoom < calibrationMinQuestions
      ? safeRoom
      : calibrationMinQuestions;
}

/// 后台开关关掉时，是否要把正在跑的后台一轮硬停
///
/// 只停后台轮；用户自己点“开始校准”发起的一轮不受开关影响
bool shouldHardStopBackgroundRound({
  required bool autoEnabled,
  required bool backgroundRound,
  required bool running,
}) => !autoEnabled && backgroundRound && running;

/// 后台是否该再整理一轮，全部条件满足才为真
///
/// [lastFailedPoolSize] 是上次没整理出至少 10 题或出错时的池条数，初始为 0
bool shouldAutoOrganize({
  required bool autoEnabled,
  required bool hasKey,
  required bool running,
  required bool budgetReached,
  required int bankSize,
  required int bankCap,
  required int poolSize,
  required int lastFailedPoolSize,
}) {
  if (!autoEnabled || !hasKey || running || budgetReached) {
    return false;
  }
  // 剩余空间不足一轮可用的题数就先暂停，等用户答掉一些题再继续
  final room = calibrationBankRoom(bankCap: bankCap, bankSize: bankSize);
  if (room < calibrationMinQuestions) {
    return false;
  }
  if (poolSize < calibrationAutoMinPool) {
    return false;
  }
  // 池里内容没比上次失败时多出足够多，先不花这份钱
  if (poolSize - lastFailedPoolSize < calibrationAutoRetryGrowth) {
    return false;
  }
  return true;
}
