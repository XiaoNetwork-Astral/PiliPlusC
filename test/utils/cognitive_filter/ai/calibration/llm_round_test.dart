import 'dart:convert';
import 'dart:math';

import 'package:PiliPlus/utils/cognitive_filter/ai/calibration/calibration_models.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/calibration/calibration_round.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/calibration/llm_client.dart';
import 'package:flutter_test/flutter_test.dart';

PoolItem _item(String id, String text) => PoolItem(
  id: id,
  text: text,
  surface: '弹幕',
  score: 0.5,
  time: 0,
);

List<PoolItem> _pool(int count) => <PoolItem>[
  for (var index = 1; index <= count; index++) _item('p$index', '内容$index'),
];

Map<String, Object?> _cluster(
  List<int> members, {
  String name = '同一类',
  String description = '共同特点',
}) => <String, Object?>{
  '名称': name,
  '描述': description,
  '成员编号': members,
};

String _reply(List<Object?> clusters) => jsonEncode(clusters);

/// 假的聊天函数，记录每次收到的消息
class _FakeChat {
  _FakeChat(this._handler);

  final Future<String> Function(int call, List<LlmMessage> messages) _handler;
  final List<List<LlmMessage>> calls = <List<LlmMessage>>[];

  Future<String> call(List<LlmMessage> messages) {
    calls.add(messages);
    return _handler(calls.length, messages);
  }
}

void main() {
  test('正常归类并记录 usedIds 与进度', () async {
    final fake = _FakeChat(
      (_, __) async => _reply(<Object?>[
        _cluster(<int>[1, 2, 3], name: '辱骂'),
        _cluster(<int>[4, 5, 6], name: '广告'),
      ]),
    );
    final progress = <List<int>>[];

    final result = await runRound(
      pool: _pool(6),
      chat: fake.call,
      isBlockedForUpload: (_) => false,
      random: Random(7),
      chunkSize: 6,
      onProgress: (done, total) => progress.add(<int>[done, total]),
    );

    expect(result.questions, hasLength(2));
    expect(result.usedIds, hasLength(6));
    expect(result.droppedIds, isEmpty);
    expect(result.refusedChunks, 0);
    expect(result.abortedBy, isNull);
    expect(result.abortMessage, isNull);
    expect(result.processedChunks, 1);
    expect(progress, <List<int>>[
      <int>[1, 1],
    ]);
    expect(result.questions.first.name, '辱骂');
    expect(fake.calls, hasLength(1));
  });

  test('容忍 ```json 围栏、对象包裹与英文键名', () async {
    final fake = _FakeChat(
      (_, __) async =>
          '```json\n{"clusters":[{"name":"玩梗","description":"都在复读同一句话",'
          '"members":[1,2,3]}]}\n```',
    );

    final result = await runRound(
      pool: _pool(3),
      chat: fake.call,
      isBlockedForUpload: (_) => false,
      random: Random(1),
      chunkSize: 3,
    );

    expect(result.questions, hasLength(1));
    final question = result.questions.single;
    expect(question.name, '玩梗');
    expect(question.description, '都在复读同一句话');
    expect(question.members, hasLength(3));
  });

  test('越界与重复编号被忽略，只保留有效成员', () async {
    final fake = _FakeChat(
      (_, __) async => _reply(<Object?>[
        _cluster(<int>[1, 1, 2, 3, 99, 0]),
      ]),
    );

    final result = await runRound(
      pool: _pool(4),
      chat: fake.call,
      isBlockedForUpload: (_) => false,
      random: Random(2),
      chunkSize: 4,
    );

    expect(result.questions, hasLength(1));
    final members = result.questions.single.members;
    expect(members, hasLength(3));
    expect(members.map((item) => item.id).toSet(), hasLength(3));
    expect(result.usedIds, hasLength(3));
  });

  test('成员不足的类丢弃，但成员留给后面的类', () async {
    final fake = _FakeChat(
      (_, __) async => _reply(<Object?>[
        _cluster(<int>[1, 2], name: '小类'),
        _cluster(<int>[1, 2, 3], name: '大类'),
      ]),
    );

    final result = await runRound(
      pool: _pool(3),
      chat: fake.call,
      isBlockedForUpload: (_) => false,
      random: Random(3),
      chunkSize: 3,
    );

    expect(result.questions, hasLength(1));
    expect(result.questions.single.name, '大类');
    expect(result.questions.single.members, hasLength(3));
  });

  test('同一编号先到先得，后面的类只拿到剩余成员', () async {
    final fake = _FakeChat(
      (_, __) async => _reply(<Object?>[
        _cluster(<int>[1, 2, 3], name: '先到'),
        _cluster(<int>[1, 4, 5], name: '后到'),
      ]),
    );

    final result = await runRound(
      pool: _pool(5),
      chat: fake.call,
      isBlockedForUpload: (_) => false,
      random: Random(4),
      chunkSize: 5,
    );

    expect(result.questions, hasLength(1));
    expect(result.questions.single.name, '先到');
    expect(result.usedIds, hasLength(3));
  });

  test('题数达到上限就不再调用后面的批', () async {
    final fake = _FakeChat(
      (_, __) async => _reply(<Object?>[
        _cluster(<int>[1, 2, 3]),
      ]),
    );
    final progress = <List<int>>[];

    final result = await runRound(
      pool: _pool(12),
      chat: fake.call,
      isBlockedForUpload: (_) => false,
      random: Random(5),
      chunkSize: 4,
      maxQuestions: 1,
      onProgress: (done, total) => progress.add(<int>[done, total]),
    );

    expect(result.questions, hasLength(1));
    expect(result.processedChunks, 1);
    expect(fake.calls, hasLength(1));
    expect(progress, <List<int>>[
      <int>[1, 3],
    ]);
  });

  test('refused 后重试一次成功', () async {
    final fake = _FakeChat((call, _) async {
      if (call == 1) {
        throw const LlmException(LlmErrorKind.refused, '拒绝了');
      }
      return _reply(<Object?>[
        _cluster(<int>[1, 2, 3]),
      ]);
    });

    final result = await runRound(
      pool: _pool(3),
      chat: fake.call,
      isBlockedForUpload: (_) => false,
      random: Random(6),
      chunkSize: 3,
    );

    expect(fake.calls, hasLength(2));
    expect(result.questions, hasLength(1));
    expect(result.refusedChunks, 0);
    expect(result.droppedIds, isEmpty);
    expect(result.abortedBy, isNull);
  });

  test('网络类问题最多试三次，第三次成功就不丢批', () async {
    final fake = _FakeChat((call, _) async {
      if (call <= 2) {
        throw const LlmException(LlmErrorKind.network, '断了');
      }
      return _reply(<Object?>[
        _cluster(<int>[1, 2, 3]),
      ]);
    });

    final result = await runRound(
      pool: _pool(3),
      chat: fake.call,
      isBlockedForUpload: (_) => false,
      random: Random(10),
      chunkSize: 3,
      retryDelay: Duration.zero,
    );

    expect(fake.calls, hasLength(3));
    expect(result.questions, hasLength(1));
    expect(result.droppedIds, isEmpty);
    expect(result.abortedBy, isNull);
  });

  test('网络类问题连续三次失败则中止整轮且条目不动', () async {
    final fake = _FakeChat(
      (_, __) async => throw const LlmException(LlmErrorKind.server, '挂了'),
    );

    final result = await runRound(
      pool: _pool(3),
      chat: fake.call,
      isBlockedForUpload: (_) => false,
      random: Random(11),
      chunkSize: 3,
      retryDelay: Duration.zero,
    );

    expect(fake.calls, hasLength(3));
    expect(result.abortedBy, LlmErrorKind.server);
    expect(result.abortMessage, '挂了');
    expect(result.droppedIds, isEmpty);
    expect(result.usedIds, isEmpty);
  });

  test('密钥无效不重试，直接中止', () async {
    final fake = _FakeChat(
      (_, __) async => throw const LlmException(LlmErrorKind.auth, '无效'),
    );

    final result = await runRound(
      pool: _pool(3),
      chat: fake.call,
      isBlockedForUpload: (_) => false,
      random: Random(12),
      chunkSize: 3,
      retryDelay: Duration.zero,
    );

    expect(fake.calls, hasLength(1));
    expect(result.abortedBy, LlmErrorKind.auth);
    expect(result.abortMessage, '无效');
  });

  test('refused 两次失败则整批进 droppedIds', () async {
    final fake = _FakeChat(
      (_, __) async =>
          throw const LlmException(LlmErrorKind.refused, '拒绝了'),
    );

    final result = await runRound(
      pool: _pool(3),
      chat: fake.call,
      isBlockedForUpload: (_) => false,
      random: Random(7),
      chunkSize: 3,
    );

    expect(fake.calls, hasLength(2));
    expect(result.questions, isEmpty);
    expect(
      result.droppedIds,
      unorderedEquals(<String>['p1', 'p2', 'p3']),
    );
    expect(result.refusedChunks, 1);
    expect(result.processedChunks, 1);
    expect(result.abortedBy, isNull);
  });

  test('parse 两次失败也把整批丢进 droppedIds', () async {
    final fake = _FakeChat((_, __) async => '这不是 JSON');

    final result = await runRound(
      pool: _pool(3),
      chat: fake.call,
      isBlockedForUpload: (_) => false,
      random: Random(8),
      chunkSize: 3,
    );

    expect(fake.calls, hasLength(2));
    expect(result.questions, isEmpty);
    expect(result.droppedIds, hasLength(3));
    expect(result.refusedChunks, 1);
    expect(result.abortedBy, isNull);
  });

  test('timeout 中止整轮并保留已得到的题目', () async {
    final fake = _FakeChat((call, _) async {
      if (call == 1) {
        return _reply(<Object?>[
          _cluster(<int>[1, 2, 3]),
        ]);
      }
      throw const LlmException(LlmErrorKind.timeout, '超时');
    });
    final progress = <List<int>>[];

    final result = await runRound(
      pool: _pool(6),
      chat: fake.call,
      isBlockedForUpload: (_) => false,
      random: Random(9),
      chunkSize: 3,
      retryDelay: Duration.zero,
      onProgress: (done, total) => progress.add(<int>[done, total]),
    );

    expect(fake.calls, hasLength(4));
    expect(result.questions, hasLength(1));
    expect(result.usedIds, hasLength(3));
    expect(result.droppedIds, isEmpty);
    expect(result.abortedBy, LlmErrorKind.timeout);
    expect(result.abortMessage, '超时');
    expect(result.processedChunks, 2);
    expect(progress, <List<int>>[
      <int>[1, 2],
      <int>[2, 2],
    ]);
  });

  test('非 LlmException 按 network 中止且不动收集池', () async {
    final fake = _FakeChat((_, __) async => throw StateError('坏了'));

    final result = await runRound(
      pool: _pool(3),
      chat: fake.call,
      isBlockedForUpload: (_) => false,
      random: Random(10),
      chunkSize: 3,
      retryDelay: Duration.zero,
    );

    expect(result.abortedBy, LlmErrorKind.network);
    expect(result.abortMessage, 'Bad state: 坏了');
    expect(result.questions, isEmpty);
    expect(result.droppedIds, isEmpty);
    expect(result.usedIds, isEmpty);
    expect(result.processedChunks, 1);
  });

  test('被拦文本进 droppedIds 且绝不出现在 chat 提示里', () async {
    final fake = _FakeChat((_, __) async => '[]');
    final pool = <PoolItem>[
      _item('bad', '这里是绝密违规文本'),
      _item('a', '普通内容甲'),
      _item('b', '普通内容乙'),
      _item('c', '普通内容丙'),
    ];

    final result = await runRound(
      pool: pool,
      chat: fake.call,
      isBlockedForUpload: (text) => text.contains('绝密'),
      random: Random(11),
      chunkSize: 40,
    );

    expect(result.droppedIds, <String>{'bad'});
    expect(result.usedIds, isEmpty);
    expect(fake.calls, hasLength(1));
    for (final messages in fake.calls) {
      for (final message in messages) {
        expect(message.content, isNot(contains('绝密')));
        expect(message.content, isNot(contains('违规')));
      }
    }
  });

  test('shouldStop 为真时提前停止并保留已得题目', () async {
    final fake = _FakeChat(
      (_, __) async => _reply(<Object?>[
        _cluster(<int>[1, 2, 3]),
      ]),
    );
    var checked = 0;

    final result = await runRound(
      pool: _pool(6),
      chat: fake.call,
      isBlockedForUpload: (_) => false,
      random: Random(14),
      chunkSize: 3,
      shouldStop: () => checked++ > 0,
    );

    // 只用第一批，第二批开始前被 shouldStop 拦下
    expect(fake.calls, hasLength(1));
    expect(result.questions, hasLength(1));
    expect(result.usedIds, hasLength(3));
    expect(result.droppedIds, isEmpty);
    expect(result.abortedBy, LlmErrorKind.budget);
    expect(result.abortMessage, '已达今日用量上限');
    expect(result.processedChunks, 1);
  });

  test('每批结束都回调进度', () async {
    final fake = _FakeChat((_, __) async => '[]');
    final progress = <List<int>>[];

    final result = await runRound(
      pool: _pool(5),
      chat: fake.call,
      isBlockedForUpload: (_) => false,
      random: Random(12),
      chunkSize: 2,
      onProgress: (done, total) => progress.add(<int>[done, total]),
    );

    expect(result.questions, isEmpty);
    expect(result.processedChunks, 3);
    expect(progress, <List<int>>[
      <int>[1, 3],
      <int>[2, 3],
      <int>[3, 3],
    ]);
  });

  test('名称与描述会截断，名称为空时用描述前几个字', () async {
    const longName = '一二三四五六七八九十一二三四五六七八九十';
    final longDescription = '这是' * 40;
    final fake = _FakeChat(
      (_, __) async => _reply(<Object?>[
        _cluster(<int>[1, 2, 3], name: longName, description: longDescription),
        _cluster(<int>[4, 5, 6], name: '', description: '没有名称的类别描述'),
      ]),
    );

    final result = await runRound(
      pool: _pool(6),
      chat: fake.call,
      isBlockedForUpload: (_) => false,
      random: Random(13),
      chunkSize: 6,
    );

    expect(result.questions, hasLength(2));
    expect(result.questions.first.name.runes.length, 12);
    expect(result.questions.first.description.runes.length, 60);
    expect(result.questions.last.name, '没有名称的类别描');
  });
}
