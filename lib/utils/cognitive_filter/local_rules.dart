import 'dart:math' as math;

/// 本地可解释的弹幕规则，逐条移植自 Python 原型
/// `.claude/tool/jev-eval/final/rules.py`，只做高置信、低误伤的屏蔽判断。
abstract final class LocalRules {
  static const String templateCurse = 'template_curse';
  static const String homophoneCurse = 'homophone_curse';
  static const String promoLink = 'promo_link';
  static const String symbolWall = 'symbol_wall';
  static const String digitFlood = 'digit_flood';
  static const String longPaste = 'long_paste';

  /// 规则名按原型固定顺序排列，`hits` 与 `verdict` 都依赖这个顺序。
  static const List<String> ruleNames = <String>[
    templateCurse,
    homophoneCurse,
    promoLink,
    symbolWall,
    digitFlood,
    longPaste,
  ];

  // Python `str.isspace()` / `re` 的 `\s` 字符集。Dart 的 `\s` 不含
  // U+001C-U+001F，却额外包含 U+FEFF；所以手工路径统一用 `_isPySpace`，
  // 正则里的 `\s` 也展开成这个字符类，保证与原型一致。
  static const String _pySpaceChars =
      r' \t\n\r\f\v\x1C-\x1F\x85\xA0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000';
  static const String _pySpaceClass = '[$_pySpaceChars]';

  // 这些字样是在遮挡别人的弹幕，用户裁定为“一律屏蔽”，优先于“防剧透”类保护词。
  static final RegExp _obstructRe = RegExp(
    '防$_pySpaceClass*(?:网暴|部分弹幕|部分彈幕|刷屏)|'
    '防止$_pySpaceClass*部分(?:弹幕|彈幕)|'
    '战术$_pySpaceClass*防御墙|'
    '遮(?:挡|住)(?:他人)?弹幕',
    unicode: true,
  );

  // 这些字样是在遮挡视频画面、保护观众，用户裁定为保留，不按符号墙处理。
  static final RegExp _protectRe = RegExp(
    '防$_pySpaceClass*(?:剧透|高能)|高能预警|前方高能|打码|马赛克',
    unicode: true,
  );

  // 纯情绪标点/爱心：问号是正常疑问情绪，心形墙常用于表达喜欢，不算遮挡墙。
  static final RegExp _softSymbolRe = RegExp(
    '^[$_pySpaceChars?？!！…、♡❤♥]+\$',
    unicode: true,
  );

  // 短句 + 颜文字，如“好听！(*¯︶¯*)”，不是遮挡画面的墙。
  static final RegExp _kaomojiRe = RegExp(
    r'[（(][^）)]{1,12}[）)]',
    unicode: true,
  );

  // 父母/全家 + 死亡 + 殡葬流程的复制粘贴模板。单独一个“父母”或“死亡”绝不命中。
  // Python 的 `.` 只排除 `\n`，Dart 的 `.` 还会排除 `\r` 与 U+2028/U+2029，
  // 因此这里展开为 `[^\n]`，保持与原型相同的跨行语义。
  static final RegExp _templateRe = RegExp(
    r'(?:如果|若|假如|要是|万一)[^\n]{0,30}'
    r'(?:父母|全家|家人|亲人|双亲|爸妈|爹妈|老小)[^\n]{0,30}'
    r'(?:死亡|去世|离世|身亡|丧命|死光|死完|没了|不在了)',
    unicode: true,
  );

  static const List<String> _templateProc = <String>[
    '殡仪馆',
    '丧葬',
    '遗体',
    '后事',
    '死亡证明',
    '火化',
    '葬礼',
    '110',
    '120',
    '保持冷静',
    '法定义务',
  ];

  // 社区谐音/变形咒骂：浮木=父母、亖冯=死妈、老冯=老母、私募=死妈、
  // 司马/死马=死妈、法死=发死/去死。每条都要求上下文，避免误伤本义。
  static final List<RegExp> _homophoneRes = <RegExp>[
    RegExp(
      r'(?:你|他|她|作者|up|阿婆主|乐子|刷屏的)[^\n]{0,6}浮木|'
      r'浮木[^\n]{0,6}(?:没|死|s|四|飞|升天|消失|双亡|亖|不在)',
      unicode: true,
    ),
    RegExp(
      '亖$_pySpaceClass*冯|'
      r'(?:你|他|她|作者|up|阿婆主|乐子|浮木)[^\n]{0,6}亖',
      unicode: true,
    ),
    RegExp(
      r'(?:老冯|老母)[^\n]{0,3}(?:飞|死|没|亖|升天)',
      unicode: true,
    ),
    RegExp(
      r'(?:乐子|你|他|她|作者|up|阿婆主|刷屏的)[^\n]{0,4}私募(?:了|的|东西|仔)',
      unicode: true,
    ),
    RegExp(
      r'(?:引战|音乐|全家|你|他|她|作者|up|阿婆主|乐子)[^\n]{0,4}(?:司马|死马)|'
      r'(?:司马|死马)(?:音乐|东西|玩意|了|吧|仔|狗)',
      unicode: true,
    ),
    RegExp(
      r'(?:直接|赶紧|去|就|再)[^\n]{0,3}法死|法死(?:你|他|她|了|吧)',
      unicode: true,
    ),
  ];

  // 链接与站外引流话术，只收明确的“加/进/扫码/群号/URL”。
  static final List<RegExp> _promoRes = <RegExp>[
    // `\b` 按 Python 的 Unicode `\w` 语义改为负向前瞻：Dart 的 `\b` 只认
    // ASCII 单词字符，会把“com中文”这种位置误判成边界。
    RegExp(
      r'https?://|www\.|(?:[a-z0-9-]+\.)+(?:com|cn|net|tv|top|xyz)(?![0-9A-Za-z_\p{L}\p{N}])',
      unicode: true,
      caseSensitive: false,
    ),
    RegExp(
      '加$_pySpaceClass*群|进$_pySpaceClass*群|群$_pySpaceClass*号|'
      '粉丝群|交流群|福利群',
      unicode: true,
    ),
    RegExp(
      '加$_pySpaceClass*微信|加$_pySpaceClass*vx|加$_pySpaceClass*wx|'
      'vx$_pySpaceClass*号|v信|微信号',
      unicode: true,
      caseSensitive: false,
    ),
    RegExp('(?:qq|q)$_pySpaceClass*群', unicode: true, caseSensitive: false),
    RegExp(
      '扫$_pySpaceClass*码|扫$_pySpaceClass*二维码|二维码',
      unicode: true,
    ),
    RegExp(
      r'复制[^\n]{0,8}弹幕[^\n]{0,8}(?:发送|刷)',
      unicode: true,
    ),
  ];

  static final RegExp _alnumRe = RegExp(r'[\p{L}\p{N}]', unicode: true);
  static final RegExp _ndRe = RegExp(r'^\p{Nd}$', unicode: true);

  /// 返回全部命中的规则名，按 `ruleNames` 的固定顺序，用于审计与归因。
  static List<String> hits(String content) {
    if (content.isEmpty) {
      return <String>[];
    }
    final matched = <String>[];
    if (_templateCurse(content)) {
      matched.add(templateCurse);
    }
    if (_homophoneCurse(content)) {
      matched.add(homophoneCurse);
    }
    if (_promoLink(content)) {
      matched.add(promoLink);
    }
    if (_symbolWall(content)) {
      matched.add(symbolWall);
    }
    if (_digitFlood(content)) {
      matched.add(digitFlood);
    }
    if (_longPaste(content)) {
      matched.add(longPaste);
    }
    return matched;
  }

  /// 返回是否屏蔽与首条命中规则名；未命中时规则名为空字符串。
  static ({bool blocked, String rule}) verdict(String content) {
    final matched = hits(content);
    return (
      blocked: matched.isNotEmpty,
      rule: matched.isEmpty ? '' : matched.first,
    );
  }

  /// 符号/方块/制表符/标点占比不低于 70% 且长度不小于 8 的墙。
  static bool _symbolWall(String text) {
    final body = _pyStrip(text);
    final runes = body.runes.toList(growable: false);
    if (runes.length < 8) {
      return false;
    }

    if (_obstructRe.hasMatch(body)) {
      return true;
    }
    if (_protectRe.hasMatch(body)) {
      return false;
    }
    if (_fullMatch(_softSymbolRe, body)) {
      return false;
    }
    if (runes.length < 20 && _kaomojiRe.hasMatch(body)) {
      var alnum = 0;
      for (final rune in runes) {
        if (_isAlnum(rune)) {
          alnum++;
        }
      }
      if (alnum >= 2) {
        return false;
      }
    }

    var symbolCount = 0;
    for (final rune in runes) {
      if (rune == 0x09 || rune == 0x0A || rune == 0x0D) {
        // 原型把制表符/换行视为遮挡字符，但普通空格不算。
        symbolCount++;
      } else if (_isPySpace(rune)) {
        continue;
      } else if (!_isAlnum(rune)) {
        symbolCount++;
      }
    }
    return symbolCount / runes.length >= 0.70;
  }

  /// 纯数字（可含空格）的灌水：数字种类 <=2，或由 <=4 位短块周期重复。
  static bool _digitFlood(String text) {
    final compact = text.runes.where((rune) => !_isPySpace(rune)).toList();
    if (compact.isEmpty) {
      return false;
    }
    for (final rune in compact) {
      if (!_isNd(rune)) {
        return false;
      }
    }
    if (compact.length < 8) {
      return false;
    }

    final distinct = compact.toSet();
    // 8888 是鼓掌、666 是夸赞、555 是社区情绪，纯 5/6/8 保留。
    if (distinct.every(
      (rune) => rune == 0x35 || rune == 0x36 || rune == 0x38,
    )) {
      return false;
    }
    if (distinct.length <= 2) {
      return true;
    }
    final n = compact.length;
    final maxPeriod = math.min(4, n ~/ 2);
    for (var period = 1; period <= maxPeriod; period++) {
      if (n % period != 0) {
        continue;
      }
      var periodic = true;
      for (var i = 0; i < n; i++) {
        if (compact[i] != compact[i % period]) {
          periodic = false;
          break;
        }
      }
      if (periodic) {
        return true;
      }
    }
    return false;
  }

  /// 模板诅咒：必须同时出现模板句式与至少两个殡葬/报警流程词。
  static bool _templateCurse(String text) {
    if (!_templateRe.hasMatch(text)) {
      return false;
    }
    var count = 0;
    for (final word in _templateProc) {
      if (text.contains(word)) {
        count++;
      }
    }
    return count >= 2;
  }

  /// 社区谐音咒骂词表，六个模式任一命中即屏蔽。
  static bool _homophoneCurse(String text) {
    for (final pattern in _homophoneRes) {
      if (pattern.hasMatch(text)) {
        return true;
      }
    }
    return false;
  }

  /// URL、加群/加微信/vx/QQ 群/扫码，以及“复制弹幕发送”的引流话术。
  static bool _promoLink(String text) {
    for (final pattern in _promoRes) {
      if (pattern.hasMatch(text)) {
        return true;
      }
    }
    return false;
  }

  /// 整段复制：长度 >=40，同一段 >=20 字、非短口号重复 >=3 次且覆盖 >=45%。
  static bool _longPaste(String text) {
    // Python 的 len 按下标按码点计数；Dart 的 String.length 是 UTF-16 码元，
    // 所以整条规则只在 runes 列表上切片、计数与比较。
    final runes = text.runes.toList(growable: false);
    final n = runes.length;
    if (n < 40) {
      return false;
    }
    var alnum = 0;
    var hasChinese = false;
    for (final rune in runes) {
      if (_isAlnum(rune)) {
        alnum++;
      }
      if (rune >= 0x4E00 && rune <= 0x9FFF) {
        hasChinese = true;
      }
    }
    if (alnum == 0) {
      return false;
    }
    // 纯 ASCII 的 kksk/英文口令多为社区应援，不当作中文整段复制模板。
    if (!hasChinese) {
      return false;
    }
    if (alnum / n < 0.60) {
      return false;
    }
    if (_protectRe.hasMatch(text) || _basePeriod(runes) < 20) {
      return false;
    }
    // 与原型相同的剪枝顺序：长度、汉字、字母数字占比、保护词、
    // 全段最小周期都在三重循环之前完成。
    final maxLen = math.min(40, n ~/ 3);
    if (maxLen < 20) {
      return false;
    }
    for (var start = 0; start < n - 7; start++) {
      for (var length = maxLen; length > 19; length--) {
        if (start + length > n) {
          continue;
        }
        final segment = runes.sublist(start, start + length);
        if (_basePeriod(segment) < 20) {
          continue;
        }
        final count = _countNonOverlapping(runes, segment);
        if (count >= 3 && count * length >= n * 0.45) {
          return true;
        }
      }
    }
    return false;
  }

  // Python `str.count(segment)` 是不重叠计数，不能直接用 allMatches
  // （后者从每个位置继续搜索，会把重叠出现也数进去）。
  static int _countNonOverlapping(List<int> haystack, List<int> needle) {
    if (needle.isEmpty) {
      return 0;
    }
    var count = 0;
    var i = 0;
    while (i + needle.length <= haystack.length) {
      var matched = true;
      for (var j = 0; j < needle.length; j++) {
        if (haystack[i + j] != needle[j]) {
          matched = false;
          break;
        }
      }
      if (matched) {
        count++;
        i += needle.length;
      } else {
        i++;
      }
    }
    return count;
  }

  // 返回最小重复周期（允许最后一段不完整），无周期则返回长度。
  static int _basePeriod(List<int> segment) {
    final half = segment.length ~/ 2;
    for (var period = 1; period <= half; period++) {
      var periodic = true;
      for (var i = 0; i < segment.length; i++) {
        if (segment[i] != segment[i % period]) {
          periodic = false;
          break;
        }
      }
      if (periodic) {
        return period;
      }
    }
    return segment.length;
  }

  // Python `re.fullmatch` 的等价判断；Dart 的 `$` 允许匹配末尾换行之前，
  // 所以用 start/end 显式比较而不是 `hasMatch`。
  static bool _fullMatch(RegExp pattern, String value) {
    final match = pattern.firstMatch(value);
    return match != null && match.start == 0 && match.end == value.length;
  }

  // Python `str.strip()` 的精确空白集合，含 U+001C-U+001F，不含 U+FEFF。
  static String _pyStrip(String value) {
    final runes = value.runes.toList(growable: false);
    var start = 0;
    var end = runes.length;
    while (start < end && _isPySpace(runes[start])) {
      start++;
    }
    while (end > start && _isPySpace(runes[end - 1])) {
      end--;
    }
    if (start == 0 && end == runes.length) {
      return value;
    }
    return String.fromCharCodes(runes, start, end);
  }

  static bool _isPySpace(int rune) {
    return rune == 0x20 ||
        (rune >= 0x09 && rune <= 0x0D) ||
        (rune >= 0x1C && rune <= 0x1F) ||
        rune == 0x85 ||
        rune == 0xA0 ||
        rune == 0x1680 ||
        (rune >= 0x2000 && rune <= 0x200A) ||
        rune == 0x2028 ||
        rune == 0x2029 ||
        rune == 0x202F ||
        rune == 0x205F ||
        rune == 0x3000;
  }

  // Python `str.isalnum()`：Unicode 字母或数字（含汉字、全角数字）。
  static bool _isAlnum(int rune) {
    if (rune < 0x80) {
      return (rune >= 0x30 && rune <= 0x39) ||
          (rune >= 0x41 && rune <= 0x5A) ||
          (rune >= 0x61 && rune <= 0x7A);
    }
    return _alnumRe.hasMatch(String.fromCharCode(rune));
  }

  // Python `str.isdigit()` 的 Unicode 十进制数字（含全角数字），按 `\p{Nd}` 处理。
  static bool _isNd(int rune) {
    if (rune >= 0x30 && rune <= 0x39) {
      return true;
    }
    return rune > 0x7F && _ndRe.hasMatch(String.fromCharCode(rune));
  }
}
