import 'dart:convert';

import 'package:PiliPlus/utils/cognitive_filter/jev_proxy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('JevProxy.parse', () {
    test('不用代理时返回 null', () {
      expect(JevProxy.parse(JevProxyType.none, '127.0.0.1:7890'), isNull);
    });

    test('空地址返回 null', () {
      expect(JevProxy.parse(JevProxyType.http, ''), isNull);
      expect(JevProxy.parse(JevProxyType.http, '   '), isNull);
      expect(JevProxy.parse(JevProxyType.socks5, 'http://'), isNull);
    });

    test('解析 host:port 并容忍首尾空白', () {
      final proxy = JevProxy.parse(JevProxyType.http, '  127.0.0.1:7890  ')!;
      expect(proxy.type, JevProxyType.http);
      expect(proxy.host, '127.0.0.1');
      expect(proxy.port, 7890);
      expect(proxy.authority, '127.0.0.1:7890');
    });

    test('容忍 http:// 与 socks5:// 前缀', () {
      expect(
        JevProxy.parse(JevProxyType.http, 'http://127.0.0.1:7890')!.authority,
        '127.0.0.1:7890',
      );
      expect(
        JevProxy.parse(
          JevProxyType.socks5,
          'SOCKS5://proxy.example.com:1080',
        )!.authority,
        'proxy.example.com:1080',
      );
      expect(
        JevProxy.parse(JevProxyType.http, 'https://proxy.example.com:443')!
            .port,
        443,
      );
    });

    test('支持 IPv6 方括号写法', () {
      final loopback = JevProxy.parse(JevProxyType.socks5, '[::1]:7890')!;
      expect(loopback.host, '::1');
      expect(loopback.port, 7890);
      expect(loopback.authority, '[::1]:7890');

      final long = JevProxy.parse(JevProxyType.http, 'http://[2001:db8::1]:8080')!;
      expect(long.host, '2001:db8::1');
      expect(long.port, 8080);
      expect(long.authority, '[2001:db8::1]:8080');
    });

    test('非法地址返回 null', () {
      for (final address in <String>[
        '127.0.0.1',
        '127.0.0.1:',
        ':7890',
        '127.0.0.1:0',
        '127.0.0.1:65536',
        '127.0.0.1:abc',
        '[::1]',
        '[::1]7890',
        '[::1',
        '::1',
        'http://:80',
        'http://127.0.0.1:7890/path',
      ]) {
        expect(
          JevProxy.parse(JevProxyType.http, address),
          isNull,
          reason: address,
        );
      }
    });
  });

  group('SOCKS5 问候', () {
    test('无认证问候字节固定', () {
      expect(buildSocks5Greeting(), <int>[0x05, 0x01, 0x00]);
    });

    test('解析问候应答', () {
      expect(parseSocks5GreetingReply(<int>[0x05, 0x00]), isNull);
      expect(parseSocks5GreetingReply(<int>[0x05, 0x02]), contains('认证'));
      expect(parseSocks5GreetingReply(<int>[0x04, 0x00]), contains('版本'));
      expect(parseSocks5GreetingReply(<int>[0x05]), contains('不完整'));
      expect(parseSocks5GreetingReply(const <int>[]), contains('不完整'));
    });
  });

  group('SOCKS5 CONNECT', () {
    test('目标地址按域名类型编码，端口为大端', () {
      final request = buildSocks5ConnectRequest('example.com', 443);
      expect(request.sublist(0, 5), <int>[0x05, 0x01, 0x00, 0x03, 11]);
      expect(
        request.sublist(5, 5 + 11),
        utf8.encode('example.com'),
      );
      expect(request.sublist(request.length - 2), <int>[0x01, 0xbb]);
    });

    test('域名长度按 UTF-8 字节数计算', () {
      final request = buildSocks5ConnectRequest('例子.测试', 80);
      final hostBytes = utf8.encode('例子.测试');
      expect(request[4], hostBytes.length);
      expect(request.sublist(5, 5 + hostBytes.length), hostBytes);
      expect(request.sublist(request.length - 2), <int>[0x00, 0x50]);
    });

    test('非法域名或端口抛 ArgumentError', () {
      expect(
        () => buildSocks5ConnectRequest('', 80),
        throwsArgumentError,
      );
      expect(
        () => buildSocks5ConnectRequest('example.com', 0),
        throwsArgumentError,
      );
      expect(
        () => buildSocks5ConnectRequest('example.com', 65536),
        throwsArgumentError,
      );
    });

    test('解析成功的应答', () {
      expect(
        parseSocks5ConnectReply(<int>[
          0x05,
          0x00,
          0x00,
          0x01,
          127,
          0,
          0,
          1,
          0x1f,
          0x90,
        ]),
        isNull,
      );
      expect(
        parseSocks5ConnectReply(<int>[
          0x05,
          0x00,
          0x00,
          0x03,
          4,
          116,
          101,
          115,
          116,
          0x01,
          0xbb,
        ]),
        isNull,
      );
      expect(
        parseSocks5ConnectReply(<int>[
          0x05,
          0x00,
          0x00,
          0x04,
          ...List<int>.filled(16, 0),
          0x00,
          0x50,
        ]),
        isNull,
      );
    });

    test('解析失败的应答', () {
      expect(
        parseSocks5ConnectReply(<int>[0x05, 0x05, 0x00, 0x01, 0, 0, 0, 0, 0, 0]),
        contains('错误码 5'),
      );
      expect(
        parseSocks5ConnectReply(<int>[0x04, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0]),
        contains('版本'),
      );
      expect(
        parseSocks5ConnectReply(<int>[0x05, 0x00, 0x00, 0x01, 0, 0, 0]),
        contains('不完整'),
      );
      expect(
        parseSocks5ConnectReply(<int>[0x05, 0x00, 0x00, 0x02, 0, 0, 0, 0]),
        contains('地址类型'),
      );
      expect(parseSocks5ConnectReply(const <int>[0x05]), contains('不完整'));
    });
  });
}
