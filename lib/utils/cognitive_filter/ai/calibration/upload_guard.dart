/// 一条不外传规则：关键词子串或正则
class GuardRule {
  const GuardRule({required this.regex, required this.content});

  /// true 表示 [content] 是正则，false 表示普通关键词
  final bool regex;

  /// 关键词或正则表达式原文
  final String content;
}

/// 上传前的内容检查器
///
/// 关键词按大小写不敏感的子串匹配；正则也大小写不敏感，非法正则直接忽略。
/// 比较时先做全角转半角、去掉零宽字符与空白，原文与规整后的文字任一命中
/// 即视为命中，防止用空格或不可见字符绕过。
class UploadGuard {
  UploadGuard(List<GuardRule> rules)
    : _keywords = <String>[],
      _patterns = <RegExp>[] {
    for (final rule in rules) {
      if (rule.regex) {
        try {
          _patterns.add(RegExp(rule.content, caseSensitive: false));
        } catch (_) {
          // 非法正则直接忽略
        }
      } else {
        _keywords.add(rule.content.toLowerCase());
      }
    }
  }

  /// 没有任何规则的检查器
  UploadGuard.empty()
    : _keywords = const <String>[],
      _patterns = const <RegExp>[];

  final List<String> _keywords;
  final List<RegExp> _patterns;

  /// 文本是否命中任一规则
  bool matches(String text) {
    final normalized = _normalize(text);
    final lowerText = text.toLowerCase();
    final lowerNormalized = normalized.toLowerCase();
    for (final keyword in _keywords) {
      if (lowerText.contains(keyword) ||
          lowerNormalized.contains(keyword)) {
        return true;
      }
    }
    for (final pattern in _patterns) {
      if (pattern.hasMatch(text) || pattern.hasMatch(normalized)) {
        return true;
      }
    }
    return false;
  }

  /// 全角转半角，去掉零宽字符与空白
  static String _normalize(String text) {
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      if (_isZeroWidth(rune) || _isWhitespace(rune)) {
        continue;
      }
      if (rune >= 0xff01 && rune <= 0xff5e) {
        buffer.writeCharCode(rune - 0xfee0);
      } else {
        buffer.writeCharCode(rune);
      }
    }
    return buffer.toString();
  }

  static bool _isWhitespace(int rune) {
    if (rune >= 0x09 && rune <= 0x0d) {
      return true;
    }
    return rune == 0x20 ||
        rune == 0x85 ||
        rune == 0xa0 ||
        rune == 0x1680 ||
        (rune >= 0x2000 && rune <= 0x200a) ||
        rune == 0x2028 ||
        rune == 0x2029 ||
        rune == 0x202f ||
        rune == 0x205f ||
        rune == 0x3000;
  }

  static bool _isZeroWidth(int rune) {
    return rune == 0x00ad ||
        rune == 0x061c ||
        rune == 0x180e ||
        (rune >= 0x200b && rune <= 0x200f) ||
        (rune >= 0x202a && rune <= 0x202e) ||
        (rune >= 0x2060 && rune <= 0x206f) ||
        (rune >= 0xfe00 && rune <= 0xfe0f) ||
        rune == 0xfeff ||
        (rune >= 0xe0100 && rune <= 0xe01ef);
  }
}
