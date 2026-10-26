/// 屏蔽统计的纯逻辑
///
/// 只依赖 Dart 语言本身：累计条数与起始日期都通过注入的读写函数取得，
/// 时钟也可以注入，便于脱离 Flutter/Hive 单独测试。
class BlockStatsCore {
  BlockStatsCore({
    required int Function() loadCount,
    required String Function() loadSince,
    required void Function(int count, String since) save,
    DateTime Function()? now,
  }) : _loadCount = loadCount,
       _loadSince = loadSince,
       _save = save,
       _now = now ?? DateTime.now;

  final int Function() _loadCount;
  final String Function() _loadSince;
  final void Function(int count, String since) _save;
  final DateTime Function() _now;

  int? _count;
  String? _since;
  bool _dirty = false;

  /// 累计屏蔽条数，包含尚未落盘的改动
  int get total {
    _ensureLoaded();
    return _count!;
  }

  /// 从起始日期到今天的天数（同一天为 1）；没有起始日期为 0
  ///
  /// 起始日期坏掉或在未来时按 1 处理。
  int get days {
    _ensureLoaded();
    final since = _since!;
    if (since.isEmpty) {
      return 0;
    }
    final start = _parseDay(since);
    if (start == null) {
      return 1;
    }
    final today = _today();
    final diff = today.difference(start).inDays;
    return diff < 0 ? 1 : diff + 1;
  }

  /// 累计 [n] 条；首次统计时把今天记为起始日期
  ///
  /// 不立即落盘，由外部在合适的时机调用 [flushIfDirty]。
  void add([int n = 1]) {
    if (n <= 0) {
      return;
    }
    _ensureLoaded();
    if (_since!.isEmpty) {
      _since = dayKeyOf(_now());
    }
    _count = _count! + n;
    _dirty = true;
  }

  /// 有未落盘的改动时保存并返回 true，否则返回 false
  bool flushIfDirty() {
    if (!_dirty) {
      return false;
    }
    _save(_count!, _since!);
    _dirty = false;
    return true;
  }

  /// 累计清零、起始日期清空，并立即落盘
  void reset() {
    _count = 0;
    _since = '';
    _dirty = false;
    _save(0, '');
  }

  void _ensureLoaded() {
    if (_count != null) {
      return;
    }
    final since = _loadSince().trim();
    final count = _loadCount();
    _count = count < 0 ? 0 : count;
    _since = since;
  }

  DateTime _today() {
    final time = _now();
    return DateTime.utc(time.year, time.month, time.day);
  }

  static DateTime? _parseDay(String value) {
    final match = _dayPattern.firstMatch(value);
    if (match == null) {
      return null;
    }
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    if (month < 1 || month > 12 || day < 1 || day > 31) {
      return null;
    }
    final date = DateTime.utc(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    return date;
  }

  static final RegExp _dayPattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
}

/// 本地日期键，格式 yyyy-MM-dd
String dayKeyOf(DateTime time) {
  final year = time.year.toString().padLeft(4, '0');
  final month = time.month.toString().padLeft(2, '0');
  final day = time.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}
