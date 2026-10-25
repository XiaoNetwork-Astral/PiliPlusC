import 'package:PiliPlus/models/cognitive_filter/builtin_categories.dart';
import 'package:PiliPlus/models/cognitive_filter/filter_category.dart';
import 'package:PiliPlus/models/cognitive_filter/filter_surface.dart';
import 'package:PiliPlus/models/cognitive_filter/filter_tier.dart';

/// 按当前模式解析出实际生效的类别列表
///
/// 非专业模式只用档位决定内置类别的开关与阈值，题面与适用面用出厂值；
/// 专业模式以出厂值为底，叠加 [overrides] 里用户改过的字段，内置类别统一用
/// [proThreshold]（总敏感度），再追加自定义类别（各自保留自己的阈值）。
List<FilterCategory> resolveCategories({
  required bool proMode,
  required FilterTier tier,
  required double proThreshold,
  required Map<String, dynamic> overrides,
  required List<FilterCategory> custom,
}) {
  if (!proMode) {
    final settings = tier.builtinSettings;
    return [
      for (final category in builtinCategories)
        category.copyWith(
          enabled: settings[category.id]?.enabled ?? category.enabled,
          threshold: settings[category.id]?.threshold ?? category.threshold,
        ),
    ];
  }

  return [
    for (final category in builtinCategories)
      _applyOverride(
        category,
        overrides[category.id],
      ).copyWith(threshold: proThreshold),
    ...custom,
  ];
}

/// 在某个适用面下实际生效的类别
List<FilterCategory> activeCategoriesFor(
  FilterSurface surface,
  List<FilterCategory> all,
) => all
    .where((category) => category.enabled && category.surfaces.contains(surface))
    .toList();

/// 从档位复制出覆盖，只包含 enabled 字段（阈值是全局的，不放进覆盖）
///
/// 供第一次开启专业模式时使用，避免切换瞬间屏蔽行为突变
Map<String, dynamic> overridesFromTier(FilterTier tier) => {
  for (final entry in tier.builtinSettings.entries)
    entry.key: <String, dynamic>{
      'enabled': entry.value.enabled,
    },
};

FilterCategory _applyOverride(FilterCategory category, Object? raw) {
  if (raw is! Map) return category;
  var result = category;

  final enabled = raw['enabled'];
  if (enabled is bool) {
    result = result.copyWith(enabled: enabled);
  }

  final surfaces = raw['surfaces'];
  if (surfaces is List) {
    final parsed = <FilterSurface>{};
    for (final name in surfaces) {
      if (name is String) {
        final surface = FilterSurface.values.asNameMap()[name];
        if (surface != null) parsed.add(surface);
      }
    }
    result = result.copyWith(surfaces: parsed);
  }

  final name = raw['name'];
  if (name is String) result = result.copyWith(name: name);
  final summary = raw['summary'];
  if (summary is String) result = result.copyWith(summary: summary);
  final question = raw['question'];
  if (question is String) result = result.copyWith(question: question);
  final trueCriteria = raw['trueCriteria'];
  if (trueCriteria is String) {
    result = result.copyWith(trueCriteria: trueCriteria);
  }
  final falseCriteria = raw['falseCriteria'];
  if (falseCriteria is String) {
    result = result.copyWith(falseCriteria: falseCriteria);
  }

  return result;
}
