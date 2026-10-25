import 'package:PiliPlus/models/cognitive_filter/builtin_categories.dart';
import 'package:PiliPlus/models/cognitive_filter/category_resolver.dart';
import 'package:PiliPlus/models/cognitive_filter/filter_category.dart';
import 'package:PiliPlus/models/cognitive_filter/filter_surface.dart';
import 'package:PiliPlus/models/cognitive_filter/filter_tier.dart';
import 'package:flutter_test/flutter_test.dart';

/// 内置类别的出厂阈值：仅占位，统一为 0.55
const _factoryThresholds = <String, double>{
  'attack': 0.55,
  'discrim': 0.55,
  'bait': 0.55,
  'mock': 0.55,
  'vulgar': 0.55,
  'promo': 0.55,
};

/// 规格要求的三档映射，逐项手写以便对照
///
/// 所有内置类别共用档位阈值；关闭的类别沿用同一阈值，便于开启时直接使用。
const _expectedTierSettings = <FilterTier, Map<String, (bool, double)>>{
  FilterTier.basic: {
    'attack': (true, 0.55),
    'discrim': (true, 0.55),
    'bait': (false, 0.55),
    'mock': (false, 0.55),
    'vulgar': (true, 0.55),
    'promo': (true, 0.55),
  },
  FilterTier.balanced: {
    'attack': (true, 0.55),
    'discrim': (true, 0.55),
    'bait': (true, 0.55),
    'mock': (false, 0.55),
    'vulgar': (true, 0.55),
    'promo': (true, 0.55),
  },
  FilterTier.strict: {
    'attack': (true, 0.75),
    'discrim': (true, 0.75),
    'bait': (true, 0.75),
    'mock': (true, 0.75),
    'vulgar': (true, 0.75),
    'promo': (true, 0.75),
  },
};

/// 各档位的全局阈值，与 _expectedTierSettings 保持一致
const _expectedTierThresholds = <FilterTier, double>{
  FilterTier.basic: 0.55,
  FilterTier.balanced: 0.55,
  FilterTier.strict: 0.75,
};

FilterCategory _category({
  String id = 'test',
  String question = '测试问句？',
  double threshold = FilterCategory.defaultThreshold,
  bool enabled = true,
  Set<FilterSurface> surfaces = const {FilterSurface.danmaku},
  bool builtin = false,
}) => FilterCategory(
  id: id,
  name: id,
  summary: '测试类别',
  question: question,
  trueCriteria: '算作是',
  falseCriteria: '算作否',
  threshold: threshold,
  enabled: enabled,
  surfaces: surfaces,
  builtin: builtin,
);

FilterCategory _builtin(String id) =>
    builtinCategories.firstWhere((category) => category.id == id);

FilterCategory _byId(List<FilterCategory> categories, String id) =>
    categories.firstWhere((category) => category.id == id);

void main() {
  group('FilterTier', () {
    test('三档阈值分别为 0.55、0.55、0.75', () {
      for (final tier in FilterTier.values) {
        expect(
          tier.threshold,
          closeTo(_expectedTierThresholds[tier]!, 1e-9),
          reason: '${tier.name} 的阈值',
        );
      }
      expect(FilterTier.basic.threshold, closeTo(0.55, 1e-9));
      expect(FilterTier.balanced.threshold, closeTo(0.55, 1e-9));
      expect(FilterTier.strict.threshold, closeTo(0.75, 1e-9));
    });

    test('档位映射与规格逐项一致', () {
      for (final tier in FilterTier.values) {
        final settings = tier.builtinSettings;
        final expected = _expectedTierSettings[tier]!;
        expect(settings.keys.toSet(), expected.keys.toSet());
        for (final entry in expected.entries) {
          final actual = settings[entry.key]!;
          expect(
            actual.enabled,
            entry.value.$1,
            reason: '${tier.name}/${entry.key} 的开关',
          );
          expect(
            actual.threshold,
            closeTo(entry.value.$2, 1e-9),
            reason: '${tier.name}/${entry.key} 的阈值',
          );
          // 所有内置类别共用档位阈值
          expect(actual.threshold, closeTo(tier.threshold, 1e-9));
        }
      }
    });

    test('非专业模式按档位给出开关与阈值，题面与适用面用出厂值', () {
      for (final tier in FilterTier.values) {
        final categories = resolveCategories(
          proMode: false,
          tier: tier,
          proThreshold: 0.42,
          overrides: const <String, dynamic>{},
          custom: const [],
        );
        expect(
          categories.map((category) => category.id),
          builtinCategories.map((category) => category.id),
        );
        for (final category in categories) {
          final expected = _expectedTierSettings[tier]![category.id]!;
          expect(category.enabled, expected.$1);
          expect(category.threshold, closeTo(expected.$2, 1e-9));
          expect(category.surfaces, FilterSurface.values.toSet());
          expect(category.question, _builtin(category.id).question);
          expect(category.name, _builtin(category.id).name);
          expect(category.summary, _builtin(category.id).summary);
          expect(category.trueCriteria, _builtin(category.id).trueCriteria);
          expect(category.falseCriteria, _builtin(category.id).falseCriteria);
          expect(category.builtin, isTrue);
        }
      }
    });

    test('默认档位为平衡', () {
      expect(FilterTier.defaultTier, FilterTier.balanced);

      final categories = resolveCategories(
        proMode: false,
        tier: FilterTier.defaultTier,
        proThreshold: 0.42,
        overrides: const <String, dynamic>{},
        custom: const [],
      );
      expect(_byId(categories, 'attack').threshold, closeTo(0.55, 1e-9));
      expect(_byId(categories, 'bait').enabled, isTrue);
      expect(_byId(categories, 'mock').enabled, isFalse);
      expect(_byId(categories, 'mock').threshold, closeTo(0.55, 1e-9));
    });

    test('非专业模式忽略覆盖、proThreshold 和自定义类别', () {
      final categories = resolveCategories(
        proMode: false,
        tier: FilterTier.basic,
        proThreshold: 0.90,
        overrides: {
          'attack': {'threshold': 0.1, 'enabled': false},
        },
        custom: [_category(id: 'custom')],
      );
      expect(categories.length, builtinCategories.length);
      expect(_byId(categories, 'attack').threshold, closeTo(0.55, 1e-9));
      expect(_byId(categories, 'attack').enabled, isTrue);
      expect(categories.any((category) => category.id == 'custom'), isFalse);
    });
  });

  group('专业模式', () {
    test('内置类别统一用 proThreshold，覆盖里其它字段照常叠加', () {
      final categories = resolveCategories(
        // 专业模式不使用档位，传严格档验证这一点
        proMode: true,
        tier: FilterTier.strict,
        proThreshold: 0.62,
        overrides: {
          'attack': {'threshold': 0.42},
          'mock': {
            'enabled': true,
            'question': '自定义问句？',
            'surfaces': ['danmaku'],
          },
        },
        custom: const [],
      );
      expect(categories.length, builtinCategories.length);

      final attack = _byId(categories, 'attack');
      // 覆盖里的 threshold 不生效，统一用 proThreshold
      expect(attack.threshold, closeTo(0.62, 1e-9));
      // 覆盖里没有 enabled，沿用出厂值
      expect(attack.enabled, isTrue);
      expect(attack.question, _builtin('attack').question);

      final mock = _byId(categories, 'mock');
      expect(mock.enabled, isTrue);
      expect(mock.question, '自定义问句？');
      expect(mock.surfaces, {FilterSurface.danmaku});
      // 覆盖里没有 name，沿用出厂值
      expect(mock.name, _builtin('mock').name);
      expect(mock.threshold, closeTo(0.62, 1e-9));

      // 严格档下 bait 应开启，但专业模式只看出厂值
      expect(_byId(categories, 'bait').enabled, isFalse);
      expect(_byId(categories, 'bait').threshold, closeTo(0.62, 1e-9));
    });

    test('改变 proThreshold，所有内置类别阈值随之变化', () {
      for (final threshold in const [0.30, 0.55, 0.75, 0.95]) {
        final categories = resolveCategories(
          proMode: true,
          tier: FilterTier.balanced,
          proThreshold: threshold,
          overrides: const <String, dynamic>{},
          custom: const [],
        );
        for (final category in categories) {
          expect(category.builtin, isTrue);
          expect(
            category.threshold,
            closeTo(threshold, 1e-9),
            reason: 'proThreshold=$threshold 时 ${category.id} 的阈值',
          );
        }
      }
    });

    test('覆盖里的 threshold 被忽略', () {
      final categories = resolveCategories(
        proMode: true,
        tier: FilterTier.basic,
        proThreshold: 0.66,
        overrides: {
          'attack': {'threshold': 0.1},
          'bait': {'threshold': 3},
        },
        custom: const [],
      );
      expect(_byId(categories, 'attack').threshold, closeTo(0.66, 1e-9));
      expect(_byId(categories, 'bait').threshold, closeTo(0.66, 1e-9));
    });

    test('自定义类别保留自己的阈值，不受 proThreshold 影响', () {
      final custom = _category(id: 'custom-1', threshold: 0.9);
      final categories = resolveCategories(
        proMode: true,
        tier: FilterTier.basic,
        proThreshold: 0.35,
        overrides: const <String, dynamic>{},
        custom: [custom],
      );
      expect(_byId(categories, 'attack').threshold, closeTo(0.35, 1e-9));
      expect(categories.last.id, 'custom-1');
      expect(categories.last.threshold, closeTo(0.9, 1e-9));
    });

    test('覆盖只改指定字段，删除覆盖即恢复出厂值', () {
      final overrides = <String, dynamic>{
        'vulgar': {'question': '被覆盖的问句？'},
      };
      var categories = resolveCategories(
        proMode: true,
        tier: FilterTier.basic,
        proThreshold: 0.50,
        overrides: overrides,
        custom: const [],
      );
      expect(_byId(categories, 'vulgar').question, '被覆盖的问句？');
      expect(_byId(categories, 'vulgar').threshold, closeTo(0.50, 1e-9));

      overrides.remove('vulgar');
      categories = resolveCategories(
        proMode: true,
        tier: FilterTier.basic,
        proThreshold: 0.50,
        overrides: overrides,
        custom: const [],
      );
      expect(_byId(categories, 'vulgar').question, _builtin('vulgar').question);
      expect(_byId(categories, 'vulgar').threshold, closeTo(0.50, 1e-9));
    });

    test('覆盖里的非法字段与类型被忽略', () {
      final categories = resolveCategories(
        proMode: true,
        tier: FilterTier.basic,
        proThreshold: 0.58,
        overrides: {
          'attack': {
            'enabled': 'yes',
            'threshold': 'not-a-number',
            'surfaces': 'danmaku',
            'question': 42,
            'unknown': 'ignored',
          },
        },
        custom: const [],
      );
      final attack = _byId(categories, 'attack');
      expect(attack.enabled, isTrue);
      expect(attack.threshold, closeTo(0.58, 1e-9));
      expect(attack.surfaces, FilterSurface.values.toSet());
      expect(attack.question, _builtin('attack').question);
    });

    test('自定义类别追加在出厂类别之后且不叠加覆盖', () {
      final custom = _category(
        id: 'custom-1',
        threshold: 0.9,
        enabled: true,
        surfaces: const {FilterSurface.dynamic},
      );
      final categories = resolveCategories(
        proMode: true,
        tier: FilterTier.basic,
        proThreshold: 0.45,
        overrides: {
          'custom-1': {'threshold': 0.1},
        },
        custom: [custom],
      );
      expect(categories.length, builtinCategories.length + 1);
      final appended = categories.last;
      expect(appended.id, 'custom-1');
      expect(appended.threshold, 0.9);
      expect(appended.surfaces, {FilterSurface.dynamic});
    });
  });

  group('overridesFromTier', () {
    test('只产出 enabled 字段，值与档位一致', () {
      for (final tier in FilterTier.values) {
        final overrides = overridesFromTier(tier);
        final expected = _expectedTierSettings[tier]!;
        expect(overrides.keys.toSet(), expected.keys.toSet());
        for (final entry in overrides.entries) {
          final value = entry.value as Map;
          expect(value.keys.toSet(), {'enabled'});
          expect(value['enabled'], expected[entry.key]!.$1);
        }
      }
    });
  });

  group('activeCategoriesFor', () {
    test('只保留启用且适用面匹配的类别', () {
      final categories = [
        _category(
          id: 'a',
          surfaces: const {FilterSurface.danmaku, FilterSurface.reply},
        ),
        _category(
          id: 'b',
          enabled: false,
          surfaces: const {FilterSurface.danmaku},
        ),
        _category(
          id: 'c',
          surfaces: const {FilterSurface.reply},
        ),
      ];
      expect(
        activeCategoriesFor(FilterSurface.danmaku, categories)
            .map((category) => category.id),
        ['a'],
      );
      expect(
        activeCategoriesFor(FilterSurface.reply, categories)
            .map((category) => category.id),
        ['a', 'c'],
      );
      expect(activeCategoriesFor(FilterSurface.video, categories), isEmpty);
    });

    test('非专业模式的基础档只筛出启用的四个类别', () {
      final categories = resolveCategories(
        proMode: false,
        tier: FilterTier.basic,
        proThreshold: 0.42,
        overrides: const <String, dynamic>{},
        custom: const [],
      );
      expect(
        activeCategoriesFor(FilterSurface.danmaku, categories)
            .map((category) => category.id),
        ['attack', 'discrim', 'vulgar', 'promo'],
      );
    });
  });

  group('内置类别常量', () {
    test('id、出厂默认、题面与摘要符合规格', () {
      expect(
        builtinCategories.map((category) => category.id),
        ['attack', 'discrim', 'bait', 'mock', 'vulgar', 'promo'],
      );
      for (final category in builtinCategories) {
        expect(category.builtin, isTrue);
        expect(category.surfaces, FilterSurface.values.toSet());
        expect(category.threshold, _factoryThresholds[category.id]);
        expect(category.question, isNotEmpty);
        expect(category.question.startsWith('只判断'), isFalse);
        expect(category.trueCriteria, isNotEmpty);
        expect(category.falseCriteria, isNotEmpty);
        expect(category.summary.runes.length, lessThanOrEqualTo(20));
      }
      expect(_builtin('attack').enabled, isTrue);
      expect(_builtin('discrim').enabled, isTrue);
      expect(_builtin('bait').enabled, isFalse);
      expect(_builtin('mock').enabled, isFalse);
      expect(_builtin('vulgar').enabled, isTrue);
      expect(_builtin('promo').enabled, isTrue);
    });
  });

  group('FilterSurface', () {
    test('中文名与发请求的对象名', () {
      expect(
        FilterSurface.values.map((surface) => surface.label),
        ['弹幕', '评论', '动态', '视频', '直播'],
      );
      expect(
        FilterSurface.values.map((surface) => surface.objectName),
        ['弹幕', '评论', '动态', '视频', '直播间'],
      );
    });
  });

  group('FilterCategory.fromJson', () {
    test('缺字段时使用缺省值且不抛异常', () {
      final category = FilterCategory.fromJson(const <String, dynamic>{});
      expect(category.id, '');
      expect(category.name, '');
      expect(category.summary, '');
      expect(category.question, '');
      expect(category.trueCriteria, '');
      expect(category.falseCriteria, '');
      expect(category.threshold, FilterCategory.defaultThreshold);
      expect(category.enabled, isFalse);
      expect(category.surfaces, FilterSurface.values.toSet());
      expect(category.builtin, isFalse);
    });

    test('类型错误时逐字段容错且不抛异常', () {
      final category = FilterCategory.fromJson({
        'id': 123,
        'name': null,
        'summary': false,
        'question': ['x'],
        'trueCriteria': 1,
        'falseCriteria': {},
        'threshold': 'not-a-number',
        'enabled': 'true',
        'surfaces': 'danmaku',
        'builtin': 1,
        'unknown': 'ignored',
      });
      expect(category.id, '');
      expect(category.name, '');
      expect(category.summary, '');
      expect(category.question, '');
      expect(category.trueCriteria, '');
      expect(category.falseCriteria, '');
      expect(category.threshold, FilterCategory.defaultThreshold);
      expect(category.enabled, isFalse);
      expect(category.surfaces, FilterSurface.values.toSet());
      expect(category.builtin, isFalse);
    });

    test('阈值接受数字字符串并限制在 0 到 1', () {
      final text = FilterCategory.fromJson({'threshold': '0.35'});
      expect(text.threshold, closeTo(0.35, 1e-9));
      expect(FilterCategory.fromJson({'threshold': -1}).threshold, 0.0);
      expect(FilterCategory.fromJson({'threshold': 2}).threshold, 1.0);
    });

    test('适用面按名称解析，未知名称忽略，空列表保持为空', () {
      final category = FilterCategory.fromJson({
        'surfaces': ['danmaku', 'unknown', 'video', 1],
      });
      expect(category.surfaces, {
        FilterSurface.danmaku,
        FilterSurface.video,
      });

      final empty = FilterCategory.fromJson({'surfaces': <String>[]});
      expect(empty.surfaces, isEmpty);
    });

    test('toJson 可以往返', () {
      final original = _category(
        id: 'custom',
        question: '自定义问句？',
        threshold: 0.35,
        enabled: false,
        surfaces: const {FilterSurface.reply, FilterSurface.video},
      );
      final restored = FilterCategory.fromJson(original.toJson());
      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.summary, original.summary);
      expect(restored.question, original.question);
      expect(restored.trueCriteria, original.trueCriteria);
      expect(restored.falseCriteria, original.falseCriteria);
      expect(restored.threshold, closeTo(original.threshold, 1e-9));
      expect(restored.enabled, original.enabled);
      expect(restored.surfaces, original.surfaces);
      expect(restored.builtin, original.builtin);
    });

    test('listFromJson 跳过无法识别的项', () {
      final categories = FilterCategory.listFromJson([
        {'id': 'a'},
        'not a map',
        {'id': 1},
        {'id': 'b', 'enabled': true},
      ]);
      expect(categories.map((category) => category.id), ['a', 'b']);
      expect(categories.last.enabled, isTrue);
    });

    test('listFromJson 对非列表返回空列表', () {
      expect(FilterCategory.listFromJson(null), isEmpty);
      expect(FilterCategory.listFromJson('not a list'), isEmpty);
      expect(FilterCategory.listFromJson(const {}), isEmpty);
    });
  });
}
