/// 去掉所有空白与常见标点引号后不再参与判定的字符
const String _ignoredSymbols = '。，、！？!?,.~～…·`\'"“”‘’';

final RegExp _spaceRe = RegExp(r'\s', unicode: true);

/// 缓存键与去重键：去首尾空白，同一字符连续出现 4 次以上压缩到 3 次
String normalizeJudgeText(String text) {
  final runes = text.trim().runes.toList(growable: false);
  if (runes.isEmpty) {
    return '';
  }
  final result = <int>[];
  var i = 0;
  while (i < runes.length) {
    final rune = runes[i];
    var end = i + 1;
    while (end < runes.length && runes[end] == rune) {
      end++;
    }
    final count = end - i;
    final keep = count >= 4 ? 3 : count;
    for (var k = 0; k < keep; k++) {
      result.add(rune);
    }
    i = end;
  }
  return String.fromCharCodes(result);
}

/// 去掉空白、标点与引号，压缩连续 3 次以上的字符后按字符数判断是否太短
bool isTooShortToJudge(String text) {
  final stripped = <int>[];
  for (final rune in text.runes) {
    final char = String.fromCharCode(rune);
    if (_spaceRe.hasMatch(char) || _ignoredSymbols.contains(char)) {
      continue;
    }
    stripped.add(rune);
  }

  final compact = <int>[];
  var i = 0;
  while (i < stripped.length) {
    final rune = stripped[i];
    var end = i + 1;
    while (end < stripped.length && stripped[end] == rune) {
      end++;
    }
    final count = end - i;
    final keep = count >= 3 ? 2 : count;
    for (var k = 0; k < keep; k++) {
      compact.add(rune);
    }
    i = end;
  }
  return compact.length <= 2;
}
