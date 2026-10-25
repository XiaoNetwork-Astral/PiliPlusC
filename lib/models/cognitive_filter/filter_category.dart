import 'package:PiliPlus/models/cognitive_filter/filter_surface.dart';

/// AI 屏蔽的一个类别
///
/// 内置类别对应选择题里的一个选项，启用类别的概率之和达到共用的总阈值时屏蔽；
/// 自定义类别对应一道是非题，「是」的概率达到自己的 [threshold] 时屏蔽。
/// [question] 不含「只判断【弹幕】这一条：」前缀，该前缀在发请求时按适用面拼接。
class FilterCategory {
  const FilterCategory({
    required this.id,
    required this.name,
    required this.summary,
    required this.question,
    required this.trueCriteria,
    required this.falseCriteria,
    required this.threshold,
    required this.enabled,
    required this.surfaces,
    required this.builtin,
  });

  /// 自定义类别的缺省阈值
  static const double defaultThreshold = 0.70;

  /// 固定不变的标识，存储里的 id 永不改动
  final String id;

  final String name;

  /// 列表里显示的一句话说明
  final String summary;

  /// 去掉适用面前缀后的是非题
  final String question;

  /// 「算作是」的标准
  final String trueCriteria;

  /// 「算作否」的标准
  final String falseCriteria;

  /// 「是」的概率达到该值即屏蔽
  final double threshold;

  final bool enabled;

  /// 该类别生效的适用面
  final Set<FilterSurface> surfaces;

  /// 是否为内置类别
  final bool builtin;

  FilterCategory copyWith({
    String? id,
    String? name,
    String? summary,
    String? question,
    String? trueCriteria,
    String? falseCriteria,
    double? threshold,
    bool? enabled,
    Set<FilterSurface>? surfaces,
    bool? builtin,
  }) {
    return FilterCategory(
      id: id ?? this.id,
      name: name ?? this.name,
      summary: summary ?? this.summary,
      question: question ?? this.question,
      trueCriteria: trueCriteria ?? this.trueCriteria,
      falseCriteria: falseCriteria ?? this.falseCriteria,
      threshold: threshold ?? this.threshold,
      enabled: enabled ?? this.enabled,
      surfaces: surfaces ?? this.surfaces,
      builtin: builtin ?? this.builtin,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'summary': summary,
    'question': question,
    'trueCriteria': trueCriteria,
    'falseCriteria': falseCriteria,
    'threshold': threshold,
    'enabled': enabled,
    'surfaces': [
      for (final surface in FilterSurface.values)
        if (surfaces.contains(surface)) surface.name,
    ],
    'builtin': builtin,
  };

  /// 缺字段、类型错误或多余的字段都不抛异常，按缺省值处理
  factory FilterCategory.fromJson(Map<String, dynamic> json) {
    return FilterCategory(
      id: _stringOf(json['id']),
      name: _stringOf(json['name']),
      summary: _stringOf(json['summary']),
      question: _stringOf(json['question']),
      trueCriteria: _stringOf(json['trueCriteria']),
      falseCriteria: _stringOf(json['falseCriteria']),
      threshold: _thresholdOf(json['threshold']),
      enabled: _boolOf(json['enabled']),
      surfaces: _surfacesOf(json['surfaces']),
      builtin: _boolOf(json['builtin']),
    );
  }

  /// 解析自定义类别列表，无法识别的项直接跳过
  static List<FilterCategory> listFromJson(Object? value) {
    if (value is! List) return const <FilterCategory>[];
    final result = <FilterCategory>[];
    for (final item in value) {
      if (item is! Map) continue;
      final json = <String, dynamic>{};
      item.forEach((key, val) {
        if (key is String) json[key] = val;
      });
      final category = FilterCategory.fromJson(json);
      if (category.id.isNotEmpty) result.add(category);
    }
    return result;
  }

  static String _stringOf(Object? value) => value is String ? value : '';

  static bool _boolOf(Object? value) => value is bool ? value : false;

  static double _thresholdOf(Object? value) {
    final threshold = switch (value) {
      num number => number.toDouble(),
      String text => double.tryParse(text),
      _ => null,
    };
    if (threshold == null || !threshold.isFinite) {
      return defaultThreshold;
    }
    return threshold.clamp(0.0, 1.0).toDouble();
  }

  static Set<FilterSurface> _surfacesOf(Object? value) {
    if (value is! List) return FilterSurface.values.toSet();
    final result = <FilterSurface>{};
    for (final name in value) {
      if (name is String) {
        final surface = FilterSurface.values.asNameMap()[name];
        if (surface != null) result.add(surface);
      }
    }
    return result;
  }
}
