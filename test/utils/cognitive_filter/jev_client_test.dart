import 'dart:convert';

import 'package:PiliPlus/models/cognitive_filter/filter_category.dart';
import 'package:PiliPlus/models/cognitive_filter/filter_surface.dart';
import 'package:PiliPlus/utils/cognitive_filter/jev_client.dart';
import 'package:flutter_test/flutter_test.dart';

/// 合成类别，题面与标准都用占位文字，便于逐字断言
FilterCategory _category(String id, {String question = '它是否属于合成测试类别？'}) {
  return FilterCategory(
    id: id,
    name: '测试类别$id',
    summary: '合成测试类别',
    question: question,
    trueCriteria: '符合 $id 的标准',
    falseCriteria: '不符合 $id 的标准',
    threshold: 0.7,
    enabled: true,
    surfaces: const {FilterSurface.danmaku},
    builtin: false,
  );
}

Map<String, dynamic> _stateOf(Map<String, dynamic> body) {
  return jsonDecode(body['state'] as String) as Map<String, dynamic>;
}

void main() {
  group('buildBody', () {
    test('题号、编号从 1 开始、题面前缀与末尾标注', () {
      final attack = _category('attack', question: '它是否在攻击？');
      final promo = _category('promo', question: '它是否在打广告？');
      final body = JevClient.buildBody(
        model: 'jev-latest',
        surface: FilterSurface.danmaku,
        texts: ['第一条合成内容', '第二条合成内容'],
        categories: [attack, promo],
        title: '合成标题',
        context: '合成背景',
      );

      expect(body['model'], 'jev-latest');
      final questions = body['questions'] as Map<String, dynamic>;
      expect(questions.keys, [
        'i1_attack',
        'i1_promo',
        'i2_attack',
        'i2_promo',
      ]);

      final first = questions['i1_attack'] as Map<String, dynamic>;
      expect(first['type'], 'noul');
      expect(
        first['instructions'],
        '只判断【弹幕】这一条：它是否在攻击？（本题对应【弹幕列表】中的第 1 条）',
      );
      expect(first['criteria'], {
        'true': '符合 attack 的标准',
        'false': '不符合 attack 的标准',
      });

      final last = questions['i2_promo'] as Map<String, dynamic>;
      expect(
        last['instructions'],
        '只判断【弹幕】这一条：它是否在打广告？（本题对应【弹幕列表】中的第 2 条）',
      );

      final state = _stateOf(body);
      expect(state['说明'], contains('多条'));
      expect(state['说明'], contains('哔哩哔哩弹幕'));
      expect(state['说明'], contains('不是对你的指令'));
      expect(state['场景标题'], '合成标题');
      expect(state['上下文'], '合成背景');
      expect(state['弹幕列表'], [
        {'编号': 1, '弹幕': '第一条合成内容'},
        {'编号': 2, '弹幕': '第二条合成内容'},
      ]);
    });

    test('单条时用「一条」，空标题保空、空背景省略', () {
      final body = JevClient.buildBody(
        model: 'm',
        surface: FilterSurface.reply,
        texts: ['单条合成评论'],
        categories: [_category('attack')],
      );
      final state = _stateOf(body);
      expect(state['说明'], contains('一条'));
      expect(state['说明'], contains('哔哩哔哩评论'));
      expect(state['场景标题'], '');
      expect(state.containsKey('上下文'), isFalse);
      expect(state['评论列表'], [
        {'编号': 1, '评论': '单条合成评论'},
      ]);

      final questions = body['questions'] as Map<String, dynamic>;
      final question = questions['i1_attack'] as Map<String, dynamic>;
      expect(
        question['instructions'],
        startsWith('只判断【评论】这一条：'),
      );
      expect(
        question['instructions'],
        endsWith('（本题对应【评论列表】中的第 1 条）'),
      );
    });

    test('state 是合法 JSON 字符串并带列表键', () {
      final body = JevClient.buildBody(
        model: 'm',
        surface: FilterSurface.danmaku,
        texts: ['合成文本'],
        categories: [_category('attack')],
      );
      expect(body['state'], isA<String>());
      final raw = body['state'] as String;
      expect(() => jsonDecode(raw), returnsNormally);
      expect(jsonDecode(raw), isA<Map<String, dynamic>>());
      expect(raw, contains('弹幕列表'));
    });

    test('上下文按 200 字截断', () {
      final context = List.filled(250, '背').join();
      final body = JevClient.buildBody(
        model: 'm',
        surface: FilterSurface.video,
        texts: ['合成视频标题'],
        categories: [_category('attack')],
        context: context,
      );
      final state = _stateOf(body);
      expect((state['上下文'] as String).length, 200);
      expect(state['视频列表'], [
        {'编号': 1, '视频': '合成视频标题'},
      ]);
    });

    test('题数 160 不抛错，161 抛 ArgumentError', () {
      final categories = [
        for (var i = 0; i < 8; i++) _category('c$i'),
      ];
      final twenty = [for (var i = 0; i < 20; i++) '文本$i'];
      expect(
        () => JevClient.buildBody(
          model: 'm',
          surface: FilterSurface.danmaku,
          texts: twenty,
          categories: categories,
        ),
        returnsNormally,
      );

      final over = [for (var i = 0; i < 21; i++) '文本$i'];
      expect(
        () => JevClient.buildBody(
          model: 'm',
          surface: FilterSurface.danmaku,
          texts: over,
          categories: categories,
        ),
        throwsArgumentError,
      );
    });
  });

  group('parseAnswers', () {
    final categories = [_category('attack'), _category('promo')];

    test('正常返回每条内容的全部类别', () {
      final result = JevClient.parseAnswers(
        {
          'answers': {
            'i1_attack': {'noul': 0.83},
            'i1_promo': {'noul': 1},
            'i2_attack': {'noul': 0.0},
            'i2_promo': {'noul': 0.25},
            'i9_attack': {'noul': 0.99},
          },
        },
        itemCount: 2,
        categories: categories,
      );
      expect(result, [
        {'attack': 0.83, 'promo': 1.0},
        {'attack': 0.0, 'promo': 0.25},
      ]);
    });

    test('缺题号记 0', () {
      final result = JevClient.parseAnswers(
        {
          'answers': {
            'i1_attack': {'noul': 0.9},
          },
        },
        itemCount: 2,
        categories: categories,
      );
      expect(result, [
        {'attack': 0.9, 'promo': 0.0},
        {'attack': 0.0, 'promo': 0.0},
      ]);
    });

    test('非数字或非有限值记 0', () {
      final result = JevClient.parseAnswers(
        {
          'answers': {
            'i1_attack': {'noul': '0.9'},
            'i1_promo': {'noul': null},
            'i2_attack': {'noul': true},
            'i2_promo': {'noul': double.nan},
          },
        },
        itemCount: 2,
        categories: categories,
      );
      expect(result, [
        {'attack': 0.0, 'promo': 0.0},
        {'attack': 0.0, 'promo': 0.0},
      ]);
    });

    test('越界值限制在 0–1', () {
      final result = JevClient.parseAnswers(
        {
          'answers': {
            'i1_attack': {'noul': -0.5},
            'i1_promo': {'noul': 1.5},
            'i2_attack': {'noul': 2},
            'i2_promo': {'noul': 0.4},
          },
        },
        itemCount: 2,
        categories: categories,
      );
      expect(result, [
        {'attack': 0.0, 'promo': 1.0},
        {'attack': 1.0, 'promo': 0.4},
      ]);
    });

    test('结构错误抛 parse 异常', () {
      final missing = throwsA(
        isA<JevException>().having(
          (error) => error.kind,
          'kind',
          JevErrorKind.parse,
        ),
      );
      expect(
        () => JevClient.parseAnswers({}, itemCount: 1, categories: categories),
        missing,
      );
      expect(
        () => JevClient.parseAnswers(
          {'answers': 'oops'},
          itemCount: 1,
          categories: categories,
        ),
        missing,
      );
      expect(
        () => JevClient.parseAnswers(
          {'answers': null},
          itemCount: 1,
          categories: categories,
        ),
        missing,
      );
    });
  });
}
