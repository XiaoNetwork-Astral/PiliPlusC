import 'package:PiliPlus/models/cognitive_filter/category_resolver.dart';
import 'package:PiliPlus/models/cognitive_filter/filter_category.dart';
import 'package:PiliPlus/utils/storage_pref.dart';

/// 认知滤网的配置入口
abstract final class CognitiveFilterConfig {
  /// 当前实际生效的类别列表
  static List<FilterCategory> get effectiveCategories => resolveCategories(
    proMode: Pref.cfFilterProMode,
    tier: Pref.cfFilterTier,
    overrides: Pref.cfCategoryOverrides,
    custom: Pref.cfCustomCategories,
  );

  /// 开启专业模式
  ///
  /// 第一次开启时若还没有覆盖，先从当前档位复制一份，避免屏蔽行为突变
  static void enterProMode() {
    if (Pref.cfFilterProMode) return;
    if (Pref.cfCategoryOverrides.isEmpty) {
      Pref.cfCategoryOverrides = overridesFromTier(Pref.cfFilterTier);
    }
    Pref.cfFilterProMode = true;
  }

  /// 恢复某个内置类别的出厂默认，即删除该 id 的覆盖
  static void resetCategory(String id) {
    final overrides = Pref.cfCategoryOverrides;
    if (!overrides.containsKey(id)) return;
    Pref.cfCategoryOverrides = Map<String, dynamic>.from(overrides)
      ..remove(id);
  }
}
