import 'dart:convert';

import 'package:PiliPlus/utils/cognitive_filter/ai/calibration/calibration_bank.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/calibration/calibration_models.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/judge_cache.dart';
import 'package:flutter_test/flutter_test.dart';

PoolItem _item(String id) => PoolItem(
  id: id,
  text: '内容$id',
  surface: '动态',
  score: 0.6,
  time: 0,
);

CalibrationQuestion _question(String name, List<String> ids) =>
    CalibrationQuestion(
      name: name,
      description: '$name的描述',
      members: <PoolItem>[for (final id in ids) _item(id)],
    );

/// 记录写盘次数，便于断言没有改动时不落盘
class _CountingStore implements JudgeCacheStore {
  _CountingStore([this.value]);

  String? value;
  int writes = 0;

  @override
  Future<String?> read() => Future<String?>.value(value);

  @override
  Future<void> write(String json) {
    writes++;
    value = json;
    return Future<void>.value();
  }
}

void main() {
  group('增删取', () {
    test('按加入先后取题且不删除', () {
      final bank = CalibrationBank(store: MemoryJudgeCacheStore());
      bank.add(<CalibrationQuestion>[
        _question('甲', <String>['1', '2', '3']),
        _question('乙', <String>['4', '5', '6']),
      ]);

      expect(bank.length, 2);
      expect(bank.take(1).single.name, '甲');
      expect(bank.length, 2);
      expect(
        bank.take(10).map((question) => question.name),
        <String>['甲', '乙'],
      );
      expect(bank.take(0), isEmpty);
      expect(bank.take(-1), isEmpty);
    });

    test('答过的新建对象也能按稳定编号精确删除', () {
      final bank = CalibrationBank(store: MemoryJudgeCacheStore());
      bank.add(<CalibrationQuestion>[
        _question('甲', <String>['1', '2', '3']),
        _question('乙', <String>['4', '5', '6']),
        _question('丙', <String>['7', '8', '9']),
      ]);

      // 成员顺序不同，编号仍相同
      final answered = _question('甲', <String>['3', '1', '2']);
      expect(answered.id, bank.questions.first.id);

      bank.removeAnswered(<CalibrationQuestion>[answered]);
      expect(bank.length, 2);
      expect(
        bank.take(10).map((question) => question.name),
        <String>['乙', '丙'],
      );

      // 删不存在的题不改动题库
      bank.removeAnswered(<CalibrationQuestion>[
        _question('丁', <String>['10', '11', '12']),
      ]);
      expect(bank.length, 2);

      bank.clear();
      expect(bank.length, 0);
      expect(bank.take(10), isEmpty);
    });

    test('空列表加入与空列表删除都不算改动', () async {
      final store = _CountingStore();
      final bank = CalibrationBank(store: store);
      bank.add(const <CalibrationQuestion>[]);
      bank.removeAnswered(const <CalibrationQuestion>[]);
      expect(bank.length, 0);
      await bank.flush();
      expect(store.writes, 0);
    });
  });

  group('持久化', () {
    test('往返后题目与成员顺序不变', () async {
      final store = MemoryJudgeCacheStore();
      final bank = CalibrationBank(store: store);
      bank.add(<CalibrationQuestion>[
        _question('甲', <String>['1', '2', '3']),
        _question('乙', <String>['4', '5', '6']),
      ]);
      await bank.flush();

      final raw = jsonDecode(store.value!) as Map<String, dynamic>;
      expect(raw['v'], 1);
      expect((raw['questions'] as List<dynamic>).length, 2);

      final restored = CalibrationBank(store: store);
      await restored.load();
      expect(restored.length, 2);
      expect(restored.questions.map((question) => question.name), <String>[
        '甲',
        '乙',
      ]);
      expect(restored.questions.first.description, '甲的描述');
      expect(
        restored.questions.first.members.map((member) => member.id),
        <String>['1', '2', '3'],
      );
      expect(
        restored.questions.first.id,
        _question('甲', <String>['1', '2', '3']).id,
      );
    });

    test('没有改动时 flush 不写盘', () async {
      final store = _CountingStore();
      final bank = CalibrationBank(store: store);

      await bank.load();
      await bank.flush();
      expect(store.writes, 0);

      bank.add(<CalibrationQuestion>[_question('甲', <String>['1', '2', '3'])]);
      await bank.flush();
      expect(store.writes, 1);

      await bank.flush();
      expect(store.writes, 1);
    });

    test('坏文件、空文件与未知版本按空题库处理', () async {
      final broken = CalibrationBank(store: MemoryJudgeCacheStore('{not json'));
      await broken.load();
      expect(broken.length, 0);

      final empty = CalibrationBank(store: MemoryJudgeCacheStore());
      await empty.load();
      expect(empty.length, 0);

      final unknown = CalibrationBank(
        store: MemoryJudgeCacheStore(
          jsonEncode(<String, dynamic>{'v': 2, 'questions': <dynamic>[]}),
        ),
      );
      await unknown.load();
      expect(unknown.length, 0);

      final wrongShape = CalibrationBank(
        store: MemoryJudgeCacheStore(
          jsonEncode(<String, dynamic>{'v': 1, 'questions': 'x'}),
        ),
      );
      await wrongShape.load();
      expect(wrongShape.length, 0);
    });

    test('跳过损坏题目，保留可用题目', () async {
      final good = _question('甲', <String>['1', '2', '3']).toJson();
      final store = MemoryJudgeCacheStore(
        jsonEncode(<String, dynamic>{
          'v': 1,
          'questions': <dynamic>[
            good,
            <String, dynamic>{'name': '缺成员'},
            'not a map',
          ],
        }),
      );
      final bank = CalibrationBank(store: store);
      await bank.load();
      expect(bank.length, 1);
      expect(bank.questions.single.name, '甲');
    });
  });
}
