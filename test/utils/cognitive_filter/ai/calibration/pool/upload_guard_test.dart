import 'package:PiliPlus/utils/cognitive_filter/ai/calibration/upload_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('关键词大小写不敏感的子串匹配', () {
    final guard = UploadGuard(<GuardRule>[
      const GuardRule(regex: false, content: 'Alpha'),
    ]);

    expect(guard.matches('前面 ALPHA 后面'), isTrue);
    expect(guard.matches('alphabet'), isTrue);
    expect(guard.matches('alp'), isFalse);
  });

  test('全角、零宽字符与空白绕过都会被规整', () {
    final guard = UploadGuard(<GuardRule>[
      const GuardRule(regex: false, content: 'alpha'),
    ]);

    expect(guard.matches('ＡＬＰＨＡ'), isTrue);
    expect(guard.matches('al\u200Bpha'), isTrue);
    expect(guard.matches('a l p h a'), isTrue);
    expect(guard.matches('al\uFEFFpha'), isTrue);
  });

  test('原文命中与规整后命中都算命中', () {
    final guard = UploadGuard(<GuardRule>[
      const GuardRule(regex: false, content: 'a b'),
      const GuardRule(regex: false, content: 'cd'),
    ]);

    expect(guard.matches('x a b y'), isTrue);
    expect(guard.matches('c d'), isTrue);
    expect(guard.matches('c\u200Bd'), isTrue);
  });

  test('正则大小写不敏感，非法正则被忽略', () {
    final guard = UploadGuard(<GuardRule>[
      const GuardRule(regex: true, content: 'b+eta'),
      const GuardRule(regex: true, content: '('),
      const GuardRule(regex: false, content: 'gamma'),
    ]);

    expect(guard.matches('xx BETA xx'), isTrue);
    expect(guard.matches('bbeta'), isTrue);
    expect(guard.matches('gamma'), isTrue);
    expect(guard.matches('delta'), isFalse);
  });

  test('全角文字参与正则匹配', () {
    final guard = UploadGuard(<GuardRule>[
      const GuardRule(regex: true, content: 'b+eta'),
    ]);

    expect(guard.matches('ＢＥＴＡ'), isTrue);
  });

  test('非法正则不会让其他规则失效', () {
    final onlyInvalid = UploadGuard(<GuardRule>[
      const GuardRule(regex: true, content: '['),
    ]);
    expect(onlyInvalid.matches('anything'), isFalse);
  });

  test('空检查器不命中任何内容', () {
    final guard = UploadGuard.empty();
    expect(guard.matches(''), isFalse);
    expect(guard.matches('anything'), isFalse);
  });
}
