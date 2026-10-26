import 'dart:convert';

import 'package:dio/dio.dart';

/// 把文本里可能出现的密钥替换成占位符
///
/// 除了 [secrets] 里显式给出的密钥，还会处理常见的 `Bearer xxx` 头与
/// `sk-xxx` 形式的密钥；长度不足 6 的 [secrets] 项不做替换，避免误伤。
String redactSecrets(String text, {Iterable<String> secrets = const []}) {
  var result = text.replaceAll(RegExp(r'Bearer\s+\S+'), 'Bearer ***');
  result = result.replaceAll(RegExp(r'sk-[A-Za-z0-9_\-]{8,}'), 'sk-***');
  for (final secret in secrets) {
    if (secret.length < 6) {
      continue;
    }
    result = result.replaceAll(secret, '***');
  }
  return result;
}

/// 把错误文本压成一行并截断到 [max] 个字符（按码点计数，不切坏代理对）
String truncateError(String text, {int max = 160}) {
  final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (flat.isEmpty) {
    return flat;
  }
  if (max < 1) {
    return '…';
  }
  final runes = flat.runes.toList(growable: false);
  if (runes.length <= max) {
    return flat;
  }
  return '${String.fromCharCodes(runes.take(max))}…';
}

/// 用接口/网络的原始信息描述一次 dio 请求失败
///
/// 有状态码时返回 `HTTP <状态码> <响应正文片段>`，正文是 String 就直接用，
/// 是 Map/List 就编码成 JSON，取不到就省略；没有状态码时返回
/// `<异常类型>: <原始错误或消息>`。结果会先脱敏再截断。
String describeDioError(
  DioException error, {
  Iterable<String> secrets = const [],
}) {
  final status = error.response?.statusCode;
  final String raw;
  if (status != null) {
    final body = _bodyText(error.response?.data);
    raw = body.isEmpty ? 'HTTP $status' : 'HTTP $status $body';
  } else {
    final detail = error.error ?? error.message;
    final text = detail?.toString().trim() ?? '';
    raw = text.isEmpty ? error.type.name : '${error.type.name}: $text';
  }
  return truncateError(redactSecrets(raw, secrets: secrets));
}

/// 取响应正文里能读出来的一段文本
String _bodyText(Object? data) {
  if (data is String) {
    return data.trim();
  }
  if (data is Map || data is List) {
    try {
      final text = jsonEncode(data).trim();
      return text == 'null' ? '' : text;
    } catch (_) {
      return '';
    }
  }
  return '';
}
