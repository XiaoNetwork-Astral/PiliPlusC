/// 池里至少这么多条才值得自动整理
///
/// 一轮至少 10 题、每题至少 3 条，30 是算术下限，不直接展示给用户
const int calibrationAutoMinPool = 30;

/// 上次失败后池里要再多出这么多条才重试，避免对同一堆内容反复花钱
const int calibrationAutoRetryGrowth = 10;

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
  // 题库到上限后暂停，等用户答掉一些题再继续
  if (bankSize >= bankCap) {
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
