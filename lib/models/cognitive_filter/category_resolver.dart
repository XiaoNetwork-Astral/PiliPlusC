import 'package:PiliPlus/models/cognitive_filter/builtin_categories.dart';
import 'package:PiliPlus/models/cognitive_filter/filter_category.dart';
import 'package:PiliPlus/models/cognitive_filter/filter_surface.dart';

/// 解析出实际生效的类别列表
///
/// 以出厂值为底，叠加 [overrides] 里用户改过的字段。内置类别的阈值先取自己
/// 的覆盖值（校准向导和类别编辑页写入），没有就跟随总敏感度 [threshold]；
/// 再追加自定义类别（各自保留自己的阈值）。
List<FilterCategory> resolveCategories({
  required double threshold,
  required Map<String, dynamic> overrides,
  required List<FilterCategory> custom,
}) {
  return [
    for (final category in builtinCategories)
      _applyOverride(category.copyWith(threshold: threshold), overrides[category.id]),
    ...custom,
  ];
}

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

  final threshold = raw['threshold'];
  if (threshold is num && threshold.isFinite) {
    result = result.copyWith(
      threshold: threshold.toDouble().clamp(0.30, 0.99).toDouble(),
    );
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
