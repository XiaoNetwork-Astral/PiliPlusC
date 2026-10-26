import 'package:PiliPlus/models/cognitive_filter/category_resolver.dart';
import 'package:PiliPlus/models/cognitive_filter/filter_category.dart';
import 'package:PiliPlus/utils/storage_pref.dart';

/// 认知滤网的配置入口
abstract final class CognitiveFilterConfig {
  /// 当前实际生效的类别列表
  static List<FilterCategory> get effectiveCategories => resolveCategories(
    threshold: Pref.cfProThreshold,
    overrides: Pref.cfCategoryOverrides,
    custom: Pref.cfCustomCategories,
    calibrationDelta: Pref.cfAiThresholdDelta,
  );

  /// 恢复某个内置类别的出厂默认，即删除该 id 的覆盖
  static void resetCategory(String id) {
    final overrides = Pref.cfCategoryOverrides;
    if (!overrides.containsKey(id)) return;
    Pref.cfCategoryOverrides = Map<String, dynamic>.from(overrides)
      ..remove(id);
  }
}
