import 'package:PiliPlus/utils/cognitive_filter/ai/calibration/calibration_models.dart';

/// 根据用户的分类回答拟合新的屏蔽门槛
///
/// 每项回答带上该题全部成员收集时的得分。对候选门槛 T：
/// * 回答"不该拦"的题里，成员得分 `>= T` 会被误拦，每个记 [falseBlockCost]；
/// * 回答"该拦"的题里，成员得分 `< T` 会被漏拦，每个记 1。
///
/// 候选 T 取所有成员得分去重后相邻两值的中点，外加 [lower]、[upper]，并
/// 全部限制在区间内。代价最小的候选胜出；并列时优先离 [current] 最近的，
/// 仍并列取较大者。最终只走一半距离，并再次限制在区间内。
///
/// 参与调参的题数不足 [minAnswers] 时返回 null，表示不调整。
double? fitThreshold({
  required double current,
  required List<({CalibrationAnswer answer, List<double> scores})> answers,
  double falseBlockCost = 2.0,
  double lower = 0.6,
  double upper = 0.97,
  int minAnswers = 8,
}) {
  final lo = lower <= upper ? lower : upper;
  final hi = lower <= upper ? upper : lower;

  final participating = <({CalibrationAnswer answer, List<double> scores})>[
    for (final entry in answers)
      if (entry.answer != CalibrationAnswer.skip) entry,
  ];
  if (participating.length < minAnswers) {
    return null;
  }

  final distinctScores = <double>{};
  for (final entry in participating) {
    for (final score in entry.scores) {
      if (score.isFinite) {
        distinctScores.add(score);
      }
    }
  }
  final sorted = distinctScores.toList()..sort();

  final candidates = <double>{lo, hi};
  for (var i = 1; i < sorted.length; i++) {
    final mid = (sorted[i - 1] + sorted[i]) / 2;
    candidates.add(mid.clamp(lo, hi).toDouble());
  }

  var best = lo;
  var bestCost = double.infinity;
  for (final candidate in candidates) {
    var cost = 0.0;
    for (final entry in participating) {
      if (entry.answer == CalibrationAnswer.keep) {
        for (final score in entry.scores) {
          if (score >= candidate) {
            cost += falseBlockCost;
          }
        }
      } else if (entry.answer == CalibrationAnswer.block) {
        for (final score in entry.scores) {
          if (score < candidate) {
            cost += 1;
          }
        }
      }
    }
    if (cost < bestCost ||
        (cost == bestCost && _prefer(candidate, best, current))) {
      best = candidate;
      bestCost = cost;
    }
  }

  // candidates 至少包含 lo 与 hi，best 一定是其中一个候选
  final fitted = current + (best - current) / 2;
  return fitted.clamp(lo, hi).toDouble();
}

/// 代价并列时：离 [current] 更近者优先，仍并列取较大者
bool _prefer(double candidate, double best, double current) {
  final candidateDistance = (candidate - current).abs();
  final bestDistance = (best - current).abs();
  if (candidateDistance != bestDistance) {
    return candidateDistance < bestDistance;
  }
  return candidate > best;
}
