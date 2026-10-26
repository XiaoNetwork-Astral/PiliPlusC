import 'dart:convert';

import 'package:PiliPlus/utils/cognitive_filter/ai/calibration/upload_guard.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/calibration/upload_guard_codec.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/calibration/upload_guard_data.dart';
import 'package:flutter_test/flutter_test.dart';

/// 按约定算法手工编码一段 JSON，用来构造结构非法的 blob
String _encodeRawJson(String json) {
  final bytes = utf8.encode(json);
  final key = utf8.encode('pcf-guard-v1');
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] ^= key[i % key.length];
  }
  return base64.encode(bytes);
}

void main() {
  test('单条规则固定向量', () {
    const rules = <GuardRule>[GuardRule(regex: false, content: 'ab')];

    expect(encodeGuardRules(rules), 'KxhEX0VPUV5GTlQLUgIEDxoo');

    final decoded = decodeGuardRules('KxhEX0VPUV5GTlQLUgIEDxoo');
    expect(decoded.length, 1);
    expect(decoded.single.regex, isFalse);
    expect(decoded.single.content, 'ab');
  });

  test('编码解码往返保持规则顺序与字段', () {
    final rules = <GuardRule>[
      const GuardRule(regex: false, content: 'alpha'),
      const GuardRule(regex: true, content: 'b+eta'),
      const GuardRule(regex: false, content: '假词'),
    ];

    final blob = encodeGuardRules(rules);
    expect(blob, isNotEmpty);
    expect(blob.contains('\n'), isFalse);

    final decoded = decodeGuardRules(blob);
    expect(decoded.length, rules.length);
    for (var i = 0; i < rules.length; i++) {
      expect(decoded[i].regex, rules[i].regex);
      expect(decoded[i].content, rules[i].content);
    }
  });

  test('固定向量与手工异或结果一致', () {
    final expected = _encodeRawJson('[{"r":0,"c":"ab"}]');
    expect(encodeGuardRules(<GuardRule>[
      const GuardRule(regex: false, content: 'ab'),
    ]), expected);
  });

  test('空串、乱码与错误结构都解出空列表', () {
    expect(decodeGuardRules(''), isEmpty);
    expect(decodeGuardRules('   '), isEmpty);
    expect(decodeGuardRules('not base64 !!!'), isEmpty);
    expect(
      decodeGuardRules(base64.encode(utf8.encode('plain text'))),
      isEmpty,
    );
    expect(decodeGuardRules(_encodeRawJson('{"a":1}')), isEmpty);
    expect(decodeGuardRules(_encodeRawJson('not json')), isEmpty);
    expect(decodeGuardRules(_encodeRawJson('[{"r":2,"c":"x"}]')), isEmpty);
    expect(decodeGuardRules(_encodeRawJson('[{"r":0}]')), isEmpty);
    expect(decodeGuardRules(_encodeRawJson('[{"r":0,"c":1}]')), isEmpty);
  });

  test('内置数据能解出规则，且互相不重复', () {
    final rules = defaultGuardRules();
    expect(rules, isNotEmpty);
    final keys = rules.map((rule) => '${rule.regex}:${rule.content}');
    expect(keys.toSet().length, rules.length);
  });
}
