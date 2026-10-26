import 'package:PiliPlus/models/cognitive_filter/builtin_categories.dart';
import 'package:PiliPlus/models/cognitive_filter/category_resolver.dart';
import 'package:PiliPlus/models/cognitive_filter/filter_category.dart';
import 'package:PiliPlus/models/cognitive_filter/filter_surface.dart';
import 'package:flutter_test/flutter_test.dart';

/// 内置类别常量里的阈值只是占位，统一为 0.55
const _factoryThresholds = <String, double>{
  'attack': 0.55,
  'discrim': 0.55,
  'bait': 0.55,
  'mock': 0.55,
  'vulgar': 0.55,
  'promo': 0.55,
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

List<FilterCategory> _resolve({
  double threshold = kDefaultBlockThreshold,
  Map<String, dynamic> overrides = const <String, dynamic>{},
  List<FilterCategory> custom = const <FilterCategory>[],
  double calibrationDelta = 0,
}) => resolveCategories(
  threshold: threshold,
  overrides: overrides,
  custom: custom,
  calibrationDelta: calibrationDelta,
);

void main() {
  group('出厂默认', () {
    test('空覆盖时只启用 attack、discrim 与 promo', () {
      final categories = _resolve();
      expect(
        categories.map((category) => category.id),
        builtinCategories.map((category) => category.id),
      );

      final enabled = {
        for (final category in categories) category.id: category.enabled,
      };
      expect(enabled, {
        'attack': true,
        'discrim': true,
        'bait': false,
        'mock': false,
        'vulgar': false,
        'promo': true,
      });

      for (final category in categories) {
        final factory = _builtin(category.id);
        expect(category.builtin, isTrue);
        expect(category.surfaces, FilterSurface.values.toSet());
        expect(category.name, factory.name);
        expect(category.summary, factory.summary);
        expect(category.question, factory.question);
        expect(category.trueCriteria, factory.trueCriteria);
        expect(category.falseCriteria, factory.falseCriteria);
      }
    });

    test('内置类别阈值统一等于传入的 threshold', () {
      for (final threshold in const [0.31, 0.55, 0.75, 0.95]) {
        final categories = _resolve(threshold: threshold);
        for (final category in categories) {
          expect(
            category.threshold,
            closeTo(threshold, 1e-9),
            reason: 'threshold=$threshold 时 ${category.id} 的阈值',
          );
        }
      }
    });
  });

  group('覆盖叠加', () {
    test('覆盖里的 enabled、适用面、名称、摘要、题面与标准都照常叠加', () {
      final categories = _resolve(
        threshold: 0.62,
        overrides: {
          'attack': {
            'threshold': 0.42,
            'enabled': false,
            'surfaces': ['reply', 'video'],
            'name': '覆盖后的名称',
            'summary': '覆盖后的摘要',
            'question': '覆盖后的问句？',
            'trueCriteria': '覆盖后的算作是',
            'falseCriteria': '覆盖后的算作否',
          },
        },
      );
      final attack = _byId(categories, 'attack');
      expect(attack.enabled, isFalse);
      expect(attack.surfaces, {FilterSurface.reply, FilterSurface.video});
      expect(attack.name, '覆盖后的名称');
      expect(attack.summary, '覆盖后的摘要');
      expect(attack.question, '覆盖后的问句？');
      expect(attack.trueCriteria, '覆盖后的算作是');
      expect(attack.falseCriteria, '覆盖后的算作否');
      // 覆盖里的 threshold 不生效，统一用传入的 threshold
      expect(attack.threshold, closeTo(0.62, 1e-9));
    });

    test('未覆盖的字段沿用出厂值', () {
      final categories = _resolve(
        threshold: 0.58,
        overrides: {
          'mock': {'enabled': true},
        },
      );
      final mock = _byId(categories, 'mock');
      expect(mock.enabled, isTrue);
      expect(mock.name, _builtin('mock').name);
      expect(mock.summary, _builtin('mock').summary);
      expect(mock.question, _builtin('mock').question);
      expect(mock.trueCriteria, _builtin('mock').trueCriteria);
      expect(mock.falseCriteria, _builtin('mock').falseCriteria);
      expect(mock.surfaces, _builtin('mock').surfaces);
      expect(mock.threshold, closeTo(0.58, 1e-9));

      // 未覆盖的 bait 沿用出厂的关闭状态
      expect(_byId(categories, 'bait').enabled, isFalse);
    });

    test('改变 threshold，所有内置类别阈值随之变化', () {
      for (final threshold in const [0.30, 0.55, 0.75, 0.95]) {
        final categories = _resolve(threshold: threshold);
        for (final category in categories) {
          expect(category.builtin, isTrue);
          expect(
            category.threshold,
            closeTo(threshold, 1e-9),
            reason: 'threshold=$threshold 时 ${category.id} 的阈值',
          );
        }
      }
    });

    test('覆盖里的 threshold 被忽略', () {
      final categories = _resolve(
        threshold: 0.66,
        overrides: {
          'attack': {'threshold': 0.1},
          'bait': {'threshold': 3},
        },
      );
      expect(_byId(categories, 'attack').threshold, closeTo(0.66, 1e-9));
      expect(_byId(categories, 'bait').threshold, closeTo(0.66, 1e-9));
    });

    test('自定义类别保留自己的阈值，不受 threshold 影响', () {
      final custom = _category(id: 'custom-1', threshold: 0.9);
      final categories = _resolve(threshold: 0.35, custom: [custom]);
      expect(_byId(categories, 'attack').threshold, closeTo(0.35, 1e-9));
      expect(categories.last.id, 'custom-1');
      expect(categories.last.threshold, closeTo(0.9, 1e-9));
    });

    test('覆盖只改指定字段，删除覆盖即恢复出厂值', () {
      final overrides = <String, dynamic>{
        'vulgar': {'question': '被覆盖的问句？'},
      };
      var categories = _resolve(threshold: 0.50, overrides: overrides);
      expect(_byId(categories, 'vulgar').question, '被覆盖的问句？');
      expect(_byId(categories, 'vulgar').threshold, closeTo(0.50, 1e-9));

      overrides.remove('vulgar');
      categories = _resolve(threshold: 0.50, overrides: overrides);
      expect(_byId(categories, 'vulgar').question, _builtin('vulgar').question);
      expect(_byId(categories, 'vulgar').threshold, closeTo(0.50, 1e-9));
    });

    test('覆盖里的非法字段与类型被忽略', () {
      final categories = _resolve(
        threshold: 0.58,
        overrides: {
          'attack': {
            'enabled': 'yes',
            'threshold': 'not-a-number',
            'surfaces': 'danmaku',
            'name': 42,
            'summary': null,
            'question': 42,
            'trueCriteria': false,
            'falseCriteria': <String>[],
            'unknown': 'ignored',
          },
        },
      );
      final attack = _byId(categories, 'attack');
      expect(attack.enabled, isTrue);
      expect(attack.threshold, closeTo(0.58, 1e-9));
      expect(attack.surfaces, FilterSurface.values.toSet());
      expect(attack.name, _builtin('attack').name);
      expect(attack.summary, _builtin('attack').summary);
      expect(attack.question, _builtin('attack').question);
      expect(attack.trueCriteria, _builtin('attack').trueCriteria);
      expect(attack.falseCriteria, _builtin('attack').falseCriteria);
    });

    test('覆盖里的 surfaces 只认已知的适用面名称', () {
      final categories = _resolve(
        overrides: {
          'attack': {
            'surfaces': ['danmaku', 'unknown', 1],
          },
        },
      );
      expect(_byId(categories, 'attack').surfaces, {FilterSurface.danmaku});
    });

    test('自定义类别追加在出厂类别之后且不叠加覆盖', () {
      final custom = _category(
        id: 'custom-1',
        threshold: 0.9,
        enabled: true,
        surfaces: const {FilterSurface.dynamic},
      );
      final categories = _resolve(
        threshold: 0.45,
        overrides: {
          'custom-1': {'threshold': 0.1, 'enabled': false},
        },
        custom: [custom],
      );
      expect(categories.length, builtinCategories.length + 1);
      final appended = categories.last;
      expect(appended.id, 'custom-1');
      expect(appended.threshold, 0.9);
      expect(appended.enabled, isTrue);
      expect(appended.surfaces, {FilterSurface.dynamic});
    });
  });

  group('calibrationDelta', () {
    test('正负偏移都会加在内置类别阈值上', () {
      final raised = _resolve(threshold: 0.62, calibrationDelta: 0.1);
      for (final category in raised) {
        expect(
          category.threshold,
          closeTo(0.72, 1e-9),
          reason: '${category.id} 的正向偏移',
        );
      }

      final lowered = _resolve(threshold: 0.62, calibrationDelta: -0.1);
      for (final category in lowered) {
        expect(
          category.threshold,
          closeTo(0.52, 1e-9),
          reason: '${category.id} 的负向偏移',
        );
      }

      // 不传时默认不偏移
      final unchanged = _resolve(threshold: 0.62);
      for (final category in unchanged) {
        expect(category.threshold, closeTo(0.62, 1e-9));
      }
    });

    test('低于 0.30 时钳位到 0.30', () {
      final negative = _resolve(threshold: 0.35, calibrationDelta: -0.2);
      for (final category in negative) {
        expect(category.threshold, closeTo(0.30, 1e-9));
      }

      final farBelow = _resolve(threshold: 0.90, calibrationDelta: -1.0);
      for (final category in farBelow) {
        expect(category.threshold, closeTo(0.30, 1e-9));
      }
    });

    test('高于 0.99 时钳位到 0.99', () {
      final positive = _resolve(threshold: 0.95, calibrationDelta: 0.2);
      for (final category in positive) {
        expect(category.threshold, closeTo(0.99, 1e-9));
      }

      final farAbove = _resolve(threshold: 0.90, calibrationDelta: 1.0);
      for (final category in farAbove) {
        expect(category.threshold, closeTo(0.99, 1e-9));
      }
    });

    test('自定义类别阈值不受校准调整量影响', () {
      final categories = _resolve(
        threshold: 0.62,
        calibrationDelta: 0.1,
        custom: [_category(id: 'custom-1', threshold: 0.40)],
      );
      expect(_byId(categories, 'attack').threshold, closeTo(0.72, 1e-9));
      expect(categories.last.id, 'custom-1');
      expect(categories.last.threshold, closeTo(0.40, 1e-9));
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

    test('出厂默认只筛出启用的 attack、discrim 与 promo', () {
      final categories = _resolve();
      expect(
        activeCategoriesFor(FilterSurface.danmaku, categories)
            .map((category) => category.id),
        ['attack', 'discrim', 'promo'],
      );
      expect(
        activeCategoriesFor(FilterSurface.live, categories)
            .map((category) => category.id),
        ['attack', 'discrim', 'promo'],
      );
    });

    test('覆盖开启并限定适用面后按新适用面筛选', () {
      final categories = _resolve(
        overrides: {
          'vulgar': {
            'enabled': true,
            'surfaces': ['video'],
          },
        },
      );
      expect(
        activeCategoriesFor(FilterSurface.danmaku, categories)
            .map((category) => category.id),
        ['attack', 'discrim', 'promo'],
      );
      expect(
        activeCategoriesFor(FilterSurface.video, categories)
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
      expect(kDefaultBlockThreshold, closeTo(0.90, 1e-9));
      for (final category in builtinCategories) {
        expect(category.builtin, isTrue);
        expect(category.surfaces, FilterSurface.values.toSet());
        expect(category.threshold, _factoryThresholds[category.id]);
        expect(category.question, isNotEmpty);
        expect(category.question.startsWith('只判断'), isFalse);
        expect(category.question.contains('是否'), isTrue);
        expect(category.question.endsWith('？'), isTrue);
        expect(category.trueCriteria, isNotEmpty);
        expect(category.falseCriteria, isNotEmpty);
        expect(category.summary.runes.length, lessThanOrEqualTo(20));
      }
      expect(_builtin('attack').enabled, isTrue);
      expect(_builtin('discrim').enabled, isTrue);
      expect(_builtin('bait').enabled, isFalse);
      expect(_builtin('mock').enabled, isFalse);
      expect(_builtin('vulgar').enabled, isFalse);
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
