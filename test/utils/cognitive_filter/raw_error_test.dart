import 'package:PiliPlus/utils/cognitive_filter/raw_error.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

DioException _httpError(int status, Object? body) {
  final options = RequestOptions(path: '/v1/chat');
  return DioException(
    requestOptions: options,
    response: Response(
      requestOptions: options,
      statusCode: status,
      data: body,
    ),
    type: DioExceptionType.badResponse,
  );
}

void main() {
  group('redactSecrets', () {
    test('替换 Bearer 头与 sk- 密钥', () {
      const raw = 'Authorization: Bearer abcdef123456 key sk-abcdefgh1234';
      final text = redactSecrets(raw);
      expect(text, contains('Bearer ***'));
      expect(text, isNot(contains('abcdef123456')));
      expect(text, contains('sk-***'));
      expect(text, isNot(contains('sk-abcdefgh1234')));
    });

    test('替换显式给出的 secret，过短的不替换', () {
      expect(
        redactSecrets('token=my-secret-value', secrets: <String>[
          'my-secret-value',
        ]),
        'token=***',
      );
      expect(redactSecrets('id=abc', secrets: <String>['abc']), 'id=abc');
    });
  });

  group('truncateError', () {
    test('空白折叠成单个空格并去首尾', () {
      expect(truncateError('  a\n\nb\tc  '), 'a b c');
    });

    test('超过上限时截断并加省略号', () {
      expect(truncateError('abcdef', max: 3), 'abc…');
      expect(truncateError('abcdef', max: 10), 'abcdef');
    });

    test('按码点截断，不切坏代理对', () {
      final text = truncateError('😀😀😀', max: 2);
      expect(text, '😀😀…');
      expect(text.runes.length, 3);
      expect(text.contains('\uFFFD'), isFalse);
    });
  });

  group('describeDioError', () {
    test('有状态码时返回状态码与正文片段', () {
      expect(
        describeDioError(_httpError(502, 'upstream\nfailed')),
        'HTTP 502 upstream failed',
      );
    });

    test('正文是 Map 时编码成 JSON', () {
      expect(
        describeDioError(_httpError(400, <String, dynamic>{'error': 'bad'})),
        'HTTP 400 {"error":"bad"}',
      );
    });

    test('取不到正文时省略正文', () {
      expect(describeDioError(_httpError(500, null)), 'HTTP 500');
      expect(describeDioError(_httpError(500, '   ')), 'HTTP 500');
    });

    test('正文里的密钥先脱敏', () {
      final text = describeDioError(
        _httpError(401, 'Authorization: Bearer sk-abcdefgh1234'),
      );
      expect(text, contains('Bearer ***'));
      expect(text, isNot(contains('sk-abcdefgh1234')));
    });

    test('没有状态码时返回异常类型与原始错误', () {
      final options = RequestOptions(path: '/v1/chat');
      expect(
        describeDioError(
          DioException(
            requestOptions: options,
            type: DioExceptionType.connectionTimeout,
            error: 'boom',
          ),
        ),
        'connectionTimeout: boom',
      );
      expect(
        describeDioError(
          DioException(
            requestOptions: options,
            type: DioExceptionType.unknown,
            message: 'boom',
          ),
        ),
        'unknown: boom',
      );
      expect(
        describeDioError(
          DioException(
            requestOptions: options,
            type: DioExceptionType.cancel,
          ),
        ),
        'cancel',
      );
    });

    test('过长正文截断', () {
      final text = describeDioError(_httpError(500, 'x' * 500));
      expect(text.startsWith('HTTP 500 '), isTrue);
      expect(text.endsWith('…'), isTrue);
      expect(text.runes.length, 161);
    });
  });
}
