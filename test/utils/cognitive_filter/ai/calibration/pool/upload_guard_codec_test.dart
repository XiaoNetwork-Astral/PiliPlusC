import 'dart:convert';

import 'package:PiliPlus/utils/cognitive_filter/ai/calibration/upload_guard_codec.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/calibration/upload_guard_data.dart';
import 'package:flutter_test/flutter_test.dart';

/// 测试专用的规则编码：按约定算法手工编码一段 JSON，用来构造结构非法的 blob
String _encodeRawJson(String json) {
  final bytes = utf8.encode(json);
  final key = utf8.encode('pcf-guard-v1');
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] ^= key[i % key.length];
  }
  return base64.encode(bytes);
}

void main() {
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
