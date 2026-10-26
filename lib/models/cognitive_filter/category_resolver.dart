import 'package:PiliPlus/models/cognitive_filter/builtin_categories.dart';
import 'package:PiliPlus/models/cognitive_filter/filter_category.dart';
import 'package:PiliPlus/models/cognitive_filter/filter_surface.dart';

/// 解析出实际生效的类别列表
///
/// 以出厂值为底，叠加 [overrides] 里用户改过的字段，内置类别统一用
/// [threshold]（总敏感度），再追加自定义类别（各自保留自己的阈值）。
/// 校准向导的累计调整量 [calibrationDelta] 只加在内置类别的阈值上。
List<FilterCategory> resolveCategories({
  required double threshold,
  required Map<String, dynamic> overrides,
  required List<FilterCategory> custom,
  double calibrationDelta = 0,
}) {
  return [
    for (final category in builtinCategories)
      _applyOverride(
        category,
        overrides[category.id],
      ).copyWith(threshold: _shifted(threshold, calibrationDelta)),
    ...custom,
  ];
}

/// 门槛加上校准调整量，限制在 0.30 到 0.99
double _shifted(double threshold, double delta) =>
    (threshold + delta).clamp(0.30, 0.99).toDouble();

/// 在某个适用面下实际生效的类别
List<FilterCategory> activeCategoriesFor(
  FilterSurface surface,
  List<FilterCategory> all,
) => all
    .where((category) => category.enabled && category.surfaces.contains(surface))
    .toList();

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
