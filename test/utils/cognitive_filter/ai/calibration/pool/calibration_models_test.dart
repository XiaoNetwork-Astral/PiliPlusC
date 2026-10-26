import 'package:PiliPlus/utils/cognitive_filter/ai/calibration/calibration_models.dart';
import 'package:flutter_test/flutter_test.dart';

PoolItem _item(String id, {double score = 0.6, String category = ''}) =>
    PoolItem(
      id: id,
      text: '内容$id',
      surface: '评论',
      score: score,
      time: 1700000000000,
      category: category,
    );

void main() {
  test('CalibrationQuestion 序列化往返', () {
    final question = CalibrationQuestion(
      name: '同一类',
      description: '共同特点',
      members: <PoolItem>[
        _item('1', score: 0.5, category: '广告'),
        _item('2', score: 0.7),
        _item('3', score: 0.9),
      ],
    );

    final json = question.toJson();
    expect(json['name'], '同一类');
    expect(json['description'], '共同特点');
    expect((json['members'] as List<dynamic>).length, 3);

    final restored = CalibrationQuestion.fromJson(json);
    expect(restored.name, question.name);
    expect(restored.description, question.description);
    expect(restored.members.map((member) => member.id), <String>['1', '2', '3']);
    expect(restored.members.first.text, '内容1');
    expect(restored.members.first.score, 0.5);
    expect(restored.members.first.category, '广告');
    expect(restored.members[1].category, '');
  });

  test('题目编号由成员编号排序后拼接，与成员顺序无关', () {
    final a = CalibrationQuestion(
      name: '甲',
      description: '说明',
      members: <PoolItem>[_item('3'), _item('1'), _item('2')],
    );
    final b = CalibrationQuestion(
      name: '乙',
      description: '说明',
      members: <PoolItem>[_item('2'), _item('3'), _item('1')],
    );

    expect(a.id, '1_2_3');
    expect(b.id, a.id);
  });
}
