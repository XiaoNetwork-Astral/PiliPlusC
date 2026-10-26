import 'dart:convert';

import 'package:PiliPlus/utils/cognitive_filter/ai/calibration/upload_guard.dart';

/// 固定密钥，仅用于避免规则明文直接出现在产物里，不承担加密职责
final List<int> _key = utf8.encode('pcf-guard-v1');

/// 解码规则 blob
///
/// 空串、非法 base64、非法 UTF-8、JSON 结构不对时返回空列表，不抛异常。
List<GuardRule> decodeGuardRules(String blob) {
  if (blob.trim().isEmpty) {
    return const <GuardRule>[];
  }
  try {
    final bytes = base64.decode(blob.trim());
    _xorWithKey(bytes);
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! List) {
      return const <GuardRule>[];
    }
    final rules = <GuardRule>[];
    for (final value in decoded) {
      if (value is! Map) {
        return const <GuardRule>[];
      }
      final rawRegex = value['r'];
      final content = value['c'];
      if (rawRegex is! num || (rawRegex != 0 && rawRegex != 1)) {
        return const <GuardRule>[];
      }
      if (content is! String) {
        return const <GuardRule>[];
      }
      rules.add(GuardRule(regex: rawRegex == 1, content: content));
    }
    return rules;
  } catch (_) {
    return const <GuardRule>[];
  }
}

void _xorWithKey(List<int> bytes) {
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] ^= _key[i % _key.length];
  }
}
