import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:PiliPlus/utils/cognitive_filter/ai/calibration/llm_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// 假的 dio 适配器，记录请求并按回调返回响应
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this._handler);

  final Future<ResponseBody> Function(RequestOptions options) _handler;
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requests.add(options);
    return _handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(int status, Object body) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: <String, List<String>>{
    Headers.contentTypeHeader: <String>['application/json'],
  },
);

ResponseBody _okContent(String content, {Map<String, Object?>? usage}) =>
    _json(200, <String, dynamic>{
      'choices': <dynamic>[
        <String, dynamic>{
          'message': <String, dynamic>{
            'role': 'assistant',
            'content': content,
          },
          'finish_reason': 'stop',
        },
      ],
      if (usage != null) 'usage': usage,
    });

/// 由多个字节块拼出的流式响应，用来模拟一个网络块含半行或多行
ResponseBody _sseResponse(List<Uint8List> chunks, {int status = 200}) =>
    ResponseBody(
      Stream<Uint8List>.fromIterable(chunks),
      status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['text/event-stream'],
      },
    );

/// 一行 SSE；载荷是字符串时原样发出（如 [DONE]），否则编码成 JSON
String _sseData(Object payload) =>
    'data: ${payload is String ? payload : jsonEncode(payload)}\n';

String _sseReasoning(String reasoning) => _sseData(<String, dynamic>{
  'choices': <dynamic>[
    <String, dynamic>{
      'delta': <String, dynamic>{'reasoning_content': reasoning},
      'finish_reason': null,
    },
  ],
});

String _sseContent(String content) => _sseData(<String, dynamic>{
  'choices': <dynamic>[
    <String, dynamic>{
      'delta': <String, dynamic>{'content': content},
      'finish_reason': null,
    },
  ],
});

String _sseUsage(Map<String, Object?> usage) => _sseData(<String, dynamic>{
  'choices': <dynamic>[],
  'usage': usage,
});

LlmClient _client(
  _FakeAdapter adapter, {
  bool jsonMode = true,
  void Function(int inputTokens, int outputTokens)? onUsage,
  void Function(String delta)? onReasoning,
}) {
  final dio = Dio();
  dio.httpClientAdapter = adapter;
  return LlmClient(
    baseUrl: 'https://api.example.com/v1/',
    apiKey: 'sk-test-secret',
    model: 'test-model',
    timeout: const Duration(seconds: 2),
    jsonMode: jsonMode,
    dio: dio,
    onUsage: onUsage,
    onReasoning: onReasoning,
  );
}

String? _header(RequestOptions request, String name) {
  for (final entry in request.headers.entries) {
    if (entry.key.toLowerCase() == name.toLowerCase()) {
      return entry.value?.toString();
    }
  }
  return null;
}

Map<String, dynamic> _bodyOf(RequestOptions request) =>
    jsonDecode(request.data! as String) as Map<String, dynamic>;

Future<LlmException> _capture(LlmClient client) async {
  try {
    await client.chat(
      const <LlmMessage>[LlmMessage(role: 'user', content: '你好')],
    );
  } on LlmException catch (error) {
    return error;
  }
  throw StateError('应当抛出 LlmException');
}

void main() {
  group('chat 请求格式', () {
    test('POST 到 chat/completions 并带齐字段', () async {
      final adapter = _FakeAdapter((_) async => _okContent('你好'));
      final client = _client(adapter);

      final reply = await client.chat(
        const <LlmMessage>[
          LlmMessage(role: 'system', content: '你是助手'),
          LlmMessage(role: 'user', content: '打个招呼'),
        ],
      );

      expect(reply, '你好');
      expect(adapter.requests, hasLength(1));
      final request = adapter.requests.single;
      expect(
        request.path,
        'https://api.example.com/v1/chat/completions',
      );
      expect(_header(request, 'Authorization'), 'Bearer sk-test-secret');
      expect(_header(request, 'Content-Type'), 'application/json');
      expect(_header(request, 'Accept'), 'application/json');

      final body = _bodyOf(request);
      expect(body['model'], 'test-model');
      expect(body['temperature'], 0.2);
      expect(body['stream'], false);
      expect(body['response_format'], <String, dynamic>{'type': 'json_object'});
      final messages = body['messages'] as List<dynamic>;
      expect(messages, hasLength(2));
      expect(
        (messages.first as Map<String, dynamic>)['role'],
        'system',
      );
      expect(
        (messages.last as Map<String, dynamic>)['content'],
        '打个招呼',
      );
    });

    test('jsonMode 为假时不带 response_format', () async {
      final adapter = _FakeAdapter((_) async => _okContent('你好'));
      final client = _client(adapter, jsonMode: false);

      await client.chat(
        const <LlmMessage>[LlmMessage(role: 'user', content: '你好')],
      );

      expect(_bodyOf(adapter.requests.single).containsKey('response_format'),
          isFalse);
    });

    test('test() 发最小请求且不带 JSON 模式', () async {
      final adapter = _FakeAdapter((_) async => _okContent('ok'));
      final client = _client(adapter);

      await client.test();

      final body = _bodyOf(adapter.requests.single);
      expect(body['max_tokens'], 16);
      expect(body.containsKey('response_format'), isFalse);
      final messages = body['messages'] as List<dynamic>;
      expect(messages, hasLength(1));
      expect((messages.single as Map<String, dynamic>)['content'], '回复 ok');
    });

    test('test() 返回从发请求到拿到有效响应的耗时', () async {
      final adapter = _FakeAdapter((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 60));
        return _okContent('ok');
      });

      final elapsed = await _client(adapter).test();

      expect(
        elapsed,
        greaterThanOrEqualTo(const Duration(milliseconds: 50)),
      );
      expect(adapter.requests, hasLength(1));
    });

    test('test() 失败仍抛 LlmException', () async {
      final adapter = _FakeAdapter(
        (_) async => _json(500, <String, dynamic>{
          'error': <String, dynamic>{'message': '挂了'},
        }),
      );

      await expectLater(
        _client(adapter).test(),
        throwsA(
          isA<LlmException>().having(
            (error) => error.kind,
            'kind',
            LlmErrorKind.server,
          ),
        ),
      );
    });

    test('DeepSeek 官方地址：整理开最高思考且不发 JSON 模式，测试关思考', () async {
      final chatAdapter = _FakeAdapter((_) async => _okContent('ok'));
      LlmClient deepseek(_FakeAdapter adapter) => LlmClient(
        baseUrl: 'https://api.deepseek.com',
        apiKey: 'sk-test-secret',
        model: 'deepseek-flash',
        dio: Dio()..httpClientAdapter = adapter,
      );
      await deepseek(chatAdapter).chat(
        const <LlmMessage>[LlmMessage(role: 'user', content: '你好')],
      );
      final chatBody = _bodyOf(chatAdapter.requests.single);
      expect(chatBody['thinking'], {'type': 'enabled'});
      expect(chatBody['reasoning_effort'], 'max');
      expect(chatBody.containsKey('response_format'), isFalse);

      final testAdapter = _FakeAdapter((_) async => _okContent('ok'));
      await deepseek(testAdapter).test();
      final testBody = _bodyOf(testAdapter.requests.single);
      expect(testBody['thinking'], {'type': 'disabled'});
      expect(testBody.containsKey('reasoning_effort'), isFalse);
    });

    test('其它服务商不发思考字段，照常带 JSON 模式', () async {
      final otherAdapter = _FakeAdapter((_) async => _okContent('ok'));
      await _client(otherAdapter).chat(
        const <LlmMessage>[LlmMessage(role: 'user', content: '你好')],
      );
      final body = _bodyOf(otherAdapter.requests.single);
      expect(body.containsKey('thinking'), isFalse);
      expect(body.containsKey('reasoning_effort'), isFalse);
      expect(body['response_format'], {'type': 'json_object'});
    });

    test('空密钥直接抛 auth 且不发请求', () async {
      final adapter = _FakeAdapter((_) async => _okContent('你好'));
      final dio = Dio();
      dio.httpClientAdapter = adapter;
      final client = LlmClient(
        baseUrl: 'https://api.example.com/v1',
        apiKey: '   ',
        model: 'test-model',
        dio: dio,
      );

      await expectLater(
        client.chat(
          const <LlmMessage>[LlmMessage(role: 'user', content: '你好')],
        ),
        throwsA(
          isA<LlmException>()
              .having((error) => error.kind, 'kind', LlmErrorKind.auth),
        ),
      );
      expect(adapter.requests, isEmpty);
    });
  });

  group('用量上报', () {
    test('响应带 prompt_tokens 与 completion_tokens 时按两者回调', () async {
      final adapter = _FakeAdapter(
        (_) async => _okContent(
          '你好',
          usage: <String, Object?>{
            'prompt_tokens': 12,
            'completion_tokens': 34,
            'total_tokens': 46,
          },
        ),
      );
      final usages = <List<int>>[];

      final reply = await _client(
        adapter,
        onUsage: (input, output) => usages.add(<int>[input, output]),
      ).chat(const <LlmMessage>[LlmMessage(role: 'user', content: '你好')]);

      expect(reply, '你好');
      expect(usages, <List<int>>[
        <int>[12, 34],
      ]);
    });

    test('只有 total_tokens 时按输入 0、输出=总数回调', () async {
      final adapter = _FakeAdapter(
        (_) async => _okContent(
          '你好',
          usage: <String, Object?>{'total_tokens': 1234},
        ),
      );
      final usages = <List<int>>[];

      await _client(
        adapter,
        onUsage: (input, output) => usages.add(<int>[input, output]),
      ).chat(const <LlmMessage>[LlmMessage(role: 'user', content: '你好')]);

      expect(usages, <List<int>>[
        <int>[0, 1234],
      ]);
    });

    test('缺 usage 时不回调', () async {
      final adapter = _FakeAdapter((_) async => _okContent('你好'));
      final usages = <List<int>>[];

      await _client(
        adapter,
        onUsage: (input, output) => usages.add(<int>[input, output]),
      ).chat(const <LlmMessage>[LlmMessage(role: 'user', content: '你好')]);

      expect(usages, isEmpty);
    });

    test('total_tokens 不是整数时不回调', () async {
      final adapter = _FakeAdapter(
        (_) async => _okContent(
          '你好',
          usage: <String, Object?>{'total_tokens': '1234'},
        ),
      );
      final usages = <List<int>>[];

      await _client(
        adapter,
        onUsage: (input, output) => usages.add(<int>[input, output]),
      ).chat(const <LlmMessage>[LlmMessage(role: 'user', content: '你好')]);

      expect(usages, isEmpty);
    });

    test('两项 token 只有一项是整数时仍用 total 兜底', () async {
      final adapter = _FakeAdapter(
        (_) async => _okContent(
          '你好',
          usage: <String, Object?>{
            'prompt_tokens': 12,
            'total_tokens': 46,
          },
        ),
      );
      final usages = <List<int>>[];

      await _client(
        adapter,
        onUsage: (input, output) => usages.add(<int>[input, output]),
      ).chat(const <LlmMessage>[LlmMessage(role: 'user', content: '你好')]);

      expect(usages, <List<int>>[
        <int>[0, 46],
      ]);
    });
  });

  group('状态码映射', () {
    const cases = <int, LlmErrorKind>{
      401: LlmErrorKind.auth,
      403: LlmErrorKind.auth,
      429: LlmErrorKind.rateLimit,
      400: LlmErrorKind.refused,
      422: LlmErrorKind.refused,
      451: LlmErrorKind.refused,
      500: LlmErrorKind.server,
      503: LlmErrorKind.server,
    };

    for (final entry in cases.entries) {
      test('HTTP ${entry.key} 映射为 ${entry.value.name}', () async {
        final adapter = _FakeAdapter(
          (_) async => _json(entry.key, <String, dynamic>{
            'error': <String, dynamic>{'message': '请求失败'},
          }),
        );

        final error = await _capture(_client(adapter));

        expect(error.kind, entry.value);
        expect(error.statusCode, entry.key);
        expect(error.message, startsWith('HTTP ${entry.key}'));
        expect(error.message, contains('请求失败'));
        expect(error.message, isNot(contains('sk-test-secret')));
        expect(error.message, isNot(contains('Bearer')));
        expect(error.toString(), isNot(contains('sk-test-secret')));
      });
    }
  });

  group('响应结构映射', () {
    test('finish_reason 为 content_filter 按 refused 处理', () async {
      final adapter = _FakeAdapter(
        (_) async => _json(200, <String, dynamic>{
          'choices': <dynamic>[
            <String, dynamic>{
              'message': <String, dynamic>{'content': ''},
              'finish_reason': 'content_filter',
            },
          ],
        }),
      );

      final error = await _capture(_client(adapter));

      expect(error.kind, LlmErrorKind.refused);
      expect(error.message, contains('content_filter'));
    });

    test('返回的不是 JSON 按 parse 处理', () async {
      final adapter = _FakeAdapter(
        (_) async => ResponseBody.fromString('<html>bad gateway</html>', 200),
      );

      final error = await _capture(_client(adapter));

      expect(error.kind, LlmErrorKind.parse);
      expect(error.message, contains('bad gateway'));
    });

    test('缺少 choices 按 parse 处理', () async {
      final adapter = _FakeAdapter(
        (_) async => _json(200, <String, dynamic>{'foo': 1}),
      );

      final error = await _capture(_client(adapter));

      expect(error.kind, LlmErrorKind.parse);
      expect(error.message, contains('foo'));
    });

    test('content 为空按 parse 处理', () async {
      final adapter = _FakeAdapter((_) async => _okContent('   '));

      final error = await _capture(_client(adapter));

      expect(error.kind, LlmErrorKind.parse);
      expect(error.message, contains('choices'));
    });
  });

  group('网络异常映射', () {
    test('连接超时映射为 timeout', () async {
      final adapter = _FakeAdapter((options) async {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionTimeout,
        );
      });

      final error = await _capture(_client(adapter));

      expect(error.kind, LlmErrorKind.timeout);
      expect(error.statusCode, isNull);
      expect(error.message, startsWith('connectionTimeout'));
    });

    test('连接失败映射为 network', () async {
      final adapter = _FakeAdapter((options) async {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        );
      });

      final error = await _capture(_client(adapter));

      expect(error.kind, LlmErrorKind.network);
      expect(error.message, startsWith('connectionError'));
    });

    test('证书错误映射为 network', () async {
      final adapter = _FakeAdapter((options) async {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.badCertificate,
        );
      });

      final error = await _capture(_client(adapter));

      expect(error.kind, LlmErrorKind.network);
      expect(error.message, startsWith('badCertificate'));
    });
  });

  group('流式整理', () {
    test('思考与正文交错，块里含两行或半行，usage 照常上报', () async {
      final lines = <String>[
        _sseReasoning('先想'),
        _sseContent('{"名称"'),
        _sseReasoning('再想'),
        _sseContent(': "类"}'),
        _sseUsage(<String, Object?>{
          'prompt_tokens': 11,
          'completion_tokens': 22,
          'total_tokens': 33,
        }),
        _sseData('[DONE]'),
      ];
      final bytes = utf8.encode(lines.join());
      // 第一刀落在第三行中间，第二刀落在 [DONE] 中间
      final firstCut = utf8.encode('${lines[0]}${lines[1]}').length + 10;
      final secondCut =
          utf8
              .encode(
                '${lines[0]}${lines[1]}${lines[2]}${lines[3]}${lines[4]}',
              )
              .length +
          3;
      final adapter = _FakeAdapter(
        (_) async => _sseResponse(<Uint8List>[
          Uint8List.fromList(bytes.sublist(0, firstCut)),
          Uint8List.fromList(bytes.sublist(firstCut, secondCut)),
          Uint8List.fromList(bytes.sublist(secondCut)),
        ]),
      );
      final thinking = <String>[];
      final usages = <List<int>>[];

      final reply = await _client(
        adapter,
        onReasoning: thinking.add,
        onUsage: (input, output) => usages.add(<int>[input, output]),
      ).chat(const <LlmMessage>[LlmMessage(role: 'user', content: '你好')]);

      expect(reply, '{"名称": "类"}');
      expect(thinking, <String>['先想', '再想']);
      expect(usages, <List<int>>[
        <int>[11, 22],
      ]);
      final request = adapter.requests.single;
      expect(request.responseType, ResponseType.stream);
      final body = _bodyOf(request);
      expect(body['stream'], isTrue);
      expect(body['stream_options'], <String, dynamic>{'include_usage': true});
      expect(_header(request, 'Accept'), 'text/event-stream');
    });

    test('流式 usage 只有 total_tokens 时按输入 0 上报', () async {
      final adapter = _FakeAdapter(
        (_) async => _sseResponse(<Uint8List>[
          Uint8List.fromList(
            utf8.encode(
              <String>[
                _sseContent('ok'),
                _sseUsage(<String, Object?>{'total_tokens': 46}),
                _sseData('[DONE]'),
              ].join(),
            ),
          ),
        ]),
      );
      final usages = <List<int>>[];

      final reply = await _client(
        adapter,
        onReasoning: (_) {},
        onUsage: (input, output) => usages.add(<int>[input, output]),
      ).chat(const <LlmMessage>[LlmMessage(role: 'user', content: '你好')]);

      expect(reply, 'ok');
      expect(usages, <List<int>>[
        <int>[0, 46],
      ]);
    });

    test('test() 即使带思考回调也走非流式', () async {
      final adapter = _FakeAdapter((_) async => _okContent('ok'));
      final thinking = <String>[];

      await _client(adapter, onReasoning: thinking.add).test();

      final body = _bodyOf(adapter.requests.single);
      expect(body['stream'], isFalse);
      expect(body.containsKey('stream_options'), isFalse);
      expect(thinking, isEmpty);
    });

    test('流式非 2xx 先读出错误体再映射，消息不含密钥', () async {
      final adapter = _FakeAdapter(
        (_) async => _sseResponse(
          <Uint8List>[
            Uint8List.fromList(
              utf8.encode(
                jsonEncode(<String, dynamic>{
                  'error': <String, dynamic>{'message': '密钥 sk-test-secret 无权限'},
                }),
              ),
            ),
          ],
          status: 401,
        ),
      );

      final error = await _capture(_client(adapter, onReasoning: (_) {}));

      expect(error.kind, LlmErrorKind.auth);
      expect(error.statusCode, 401);
      expect(error.message, startsWith('HTTP 401'));
      expect(error.message, contains('无权限'));
      expect(error.message, isNot(contains('sk-test-secret')));
      expect(error.toString(), isNot(contains('sk-test-secret')));
    });

    test('流式只有思考没有正文按 parse 处理', () async {
      final adapter = _FakeAdapter(
        (_) async => _sseResponse(<Uint8List>[
          Uint8List.fromList(
            utf8.encode(
              <String>[
                _sseReasoning('想完了'),
                _sseUsage(<String, Object?>{
                  'prompt_tokens': 1,
                  'completion_tokens': 2,
                }),
                _sseData('[DONE]'),
              ].join(),
            ),
          ),
        ]),
      );
      final thinking = <String>[];

      final error = await _capture(
        _client(adapter, onReasoning: thinking.add),
      );

      expect(error.kind, LlmErrorKind.parse);
      expect(error.message, contains('内容为空'));
      expect(thinking, <String>['想完了']);
    });

    test('流式没有结束标记按 parse 处理', () async {
      final adapter = _FakeAdapter(
        (_) async => _sseResponse(<Uint8List>[
          Uint8List.fromList(utf8.encode(_sseContent('半截'))),
        ]),
      );

      final error = await _capture(_client(adapter, onReasoning: (_) {}));

      expect(error.kind, LlmErrorKind.parse);
      expect(error.message, contains('意外结束'));
    });

    test('流式中途断开按 parse 处理，不返回半截正文', () async {
      final controller = StreamController<Uint8List>();
      controller.add(Uint8List.fromList(utf8.encode(_sseContent('半截'))));
      controller.addError(StateError('连接被重置'));
      unawaited(controller.close());
      final adapter = _FakeAdapter(
        (_) async => ResponseBody(
          controller.stream,
          200,
          headers: <String, List<String>>{
            Headers.contentTypeHeader: <String>['text/event-stream'],
          },
        ),
      );

      final error = await _capture(_client(adapter, onReasoning: (_) {}));

      expect(error.kind, LlmErrorKind.parse);
      expect(error.message, contains('流式响应中断'));
      expect(error.message, contains('连接被重置'));
    });
  });
}
