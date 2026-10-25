import 'package:PiliPlus/utils/cognitive_filter/jev_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('send 的前置校验', () {
    test('空 API Key 抛 auth 异常', () async {
      await expectLater(
        JevClient.send(
          endpoint: 'https://example.com/api',
          apiKey: '   ',
          model: 'm',
          timeout: const Duration(seconds: 1),
          body: const <String, dynamic>{},
        ),
        throwsA(
          isA<JevException>().having(
            (error) => error.kind,
            'kind',
            JevErrorKind.auth,
          ),
        ),
      );
    });

    test('非法接口地址抛 badRequest 异常', () async {
      await expectLater(
        JevClient.send(
          endpoint: 'not-a-url',
          apiKey: 'key',
          model: 'm',
          timeout: const Duration(seconds: 1),
          body: const <String, dynamic>{},
        ),
        throwsA(
          isA<JevException>().having(
            (error) => error.kind,
            'kind',
            JevErrorKind.badRequest,
          ),
        ),
      );
    });

    test('makeTransport 返回可调用的闭包', () async {
      final transport = JevClient.makeTransport(
        endpoint: 'https://example.com/api',
        apiKey: '',
        model: 'm',
        timeout: const Duration(seconds: 1),
      );
      await expectLater(
        transport(const <String, dynamic>{}),
        throwsA(isA<JevException>()),
      );
    });
  });

  group('testConnection', () {
    test('空 API Key 直接返回失败说明', () async {
      final result = await JevClient.testConnection(
        endpoint: 'https://example.com/api',
        apiKey: '',
        model: 'm',
        timeout: const Duration(seconds: 1),
      );
      expect(result.ok, isFalse);
      expect(result.message, '请先填写 API Key');
    });

    test('非法接口地址返回失败且不抛异常', () async {
      final result = await JevClient.testConnection(
        endpoint: 'http://',
        apiKey: 'key',
        model: 'm',
        timeout: const Duration(seconds: 1),
      );
      expect(result.ok, isFalse);
      expect(result.message, contains('接口地址不正确'));
    });
  });

  group('兼容常量与异常', () {
    test('单请求题数上限保持 160', () {
      expect(JevClient.maxQuestions, 160);
    });

    test('JevException 的字符串包含类别与说明', () {
      const error = JevException(JevErrorKind.parse, '结构不正确');
      expect(error.toString(), contains('parse'));
      expect(error.toString(), contains('结构不正确'));
    });
  });
}
