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

ResponseBody _okContent(String content, {Object? totalTokens}) =>
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
      if (totalTokens != null)
        'usage': <String, dynamic>{'total_tokens': totalTokens},
    });

LlmClient _client(
  _FakeAdapter adapter, {
  bool jsonMode = true,
  void Function(int totalTokens)? onUsage,
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
    test('响应带 usage.total_tokens 时回调一次', () async {
      final adapter = _FakeAdapter(
        (_) async => _okContent('你好', totalTokens: 1234),
      );
      final usages = <int>[];

      final reply = await _client(adapter, onUsage: usages.add).chat(
        const <LlmMessage>[LlmMessage(role: 'user', content: '你好')],
      );

      expect(reply, '你好');
      expect(usages, <int>[1234]);
    });

    test('缺少 usage 时不回调', () async {
      final adapter = _FakeAdapter((_) async => _okContent('你好'));
      final usages = <int>[];

      await _client(adapter, onUsage: usages.add).chat(
        const <LlmMessage>[LlmMessage(role: 'user', content: '你好')],
      );

      expect(usages, isEmpty);
    });

    test('total_tokens 不是整数时不回调', () async {
      final adapter = _FakeAdapter(
        (_) async => _okContent('你好', totalTokens: '1234'),
      );
      final usages = <int>[];

      await _client(adapter, onUsage: usages.add).chat(
        const <LlmMessage>[LlmMessage(role: 'user', content: '你好')],
      );

      expect(usages, isEmpty);
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
    });

    test('返回的不是 JSON 按 parse 处理', () async {
      final adapter = _FakeAdapter(
        (_) async => ResponseBody.fromString('<html>bad gateway</html>', 200),
      );

      final error = await _capture(_client(adapter));

      expect(error.kind, LlmErrorKind.parse);
    });

    test('缺少 choices 按 parse 处理', () async {
      final adapter = _FakeAdapter(
        (_) async => _json(200, <String, dynamic>{'foo': 1}),
      );

      final error = await _capture(_client(adapter));

      expect(error.kind, LlmErrorKind.parse);
    });

    test('content 为空按 parse 处理', () async {
      final adapter = _FakeAdapter((_) async => _okContent('   '));

      final error = await _capture(_client(adapter));

      expect(error.kind, LlmErrorKind.parse);
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
      expect(error.message, contains('证书'));
    });
  });

  group('llmErrorText', () {
    test('每个类别都有中文提示且句中不用句号', () {
      for (final kind in LlmErrorKind.values) {
        final text = llmErrorText(kind);
        expect(text, isNotEmpty);
        expect(text.endsWith('。'), isFalse);
      }
    });

    test('常见提示文案固定', () {
      expect(llmErrorText(LlmErrorKind.auth), '密钥无效');
      expect(llmErrorText(LlmErrorKind.rateLimit), '请求太频繁');
      expect(llmErrorText(LlmErrorKind.timeout), '连接超时，可能需要配置代理');
      expect(llmErrorText(LlmErrorKind.budget), '已达今日用量上限');
    });
  });
}
