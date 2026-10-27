import 'package:PiliPlus/models/cognitive_filter/category_resolver.dart';
import 'package:PiliPlus/models/cognitive_filter/filter_category.dart';
import 'package:PiliPlus/utils/storage_pref.dart';

/// 认知滤网的配置入口
abstract final class CognitiveFilterConfig {
  /// 当前实际生效的类别列表
  static List<FilterCategory> get effectiveCategories => resolveCategories(
    threshold: Pref.cfBlockThreshold,
    overrides: Pref.cfCategoryOverrides,
    custom: Pref.cfCustomCategories,
  );

  /// 写入某个内置类别自己的阈值，其余覆盖字段不动
  static void setCategoryThreshold(String id, double threshold) {
    final overrides = Map<String, dynamic>.from(Pref.cfCategoryOverrides);
    final raw = overrides[id];
    final current = raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};
    current['threshold'] = threshold.clamp(0.30, 0.99).toDouble();
    overrides[id] = current;
    Pref.cfCategoryOverrides = overrides;
  }

  /// 清掉所有内置类别单独的阈值，让它们都回到跟随总敏感度
  static void clearCategoryThresholds() {
    final overrides = Map<String, dynamic>.from(Pref.cfCategoryOverrides);
    var changed = false;
    for (final id in overrides.keys.toList()) {
      final raw = overrides[id];
      if (raw is! Map || !raw.containsKey('threshold')) continue;
      final next = Map<String, dynamic>.from(raw)..remove('threshold');
      if (next.isEmpty) {
        overrides.remove(id);
      } else {
        overrides[id] = next;
      }
      changed = true;
    }
    if (changed) Pref.cfCategoryOverrides = overrides;
  }

  /// 恢复某个内置类别的出厂默认，即删除该 id 的覆盖
  static void resetCategory(String id) {
    final overrides = Pref.cfCategoryOverrides;
    if (!overrides.containsKey(id)) return;
    Pref.cfCategoryOverrides = Map<String, dynamic>.from(overrides)
      ..remove(id);
  }
}
