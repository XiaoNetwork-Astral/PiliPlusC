import 'dart:convert' show ascii;
import 'dart:ui' show Color;

import 'package:archive/archive.dart' show getCrc32;
import 'package:canvas_danmaku/models/danmaku_content_item.dart'
    show DanmakuItemType;

abstract final class DmUtils {
  static Color decimalToColor(int decimalColor) =>
      Color(decimalColor | 0xFF000000);

  static DanmakuItemType getPosition(int mode) => switch (mode) {
    4 => DanmakuItemType.bottom,
    5 => DanmakuItemType.top,
    7 => DanmakuItemType.special,
    _ => DanmakuItemType.scroll,
  };

  /// 用户 UID 对应的弹幕发送者哈希，与云端用户屏蔽规则的写法一致
  static String midToHash(int mid) =>
      getCrc32(ascii.encode(mid.toString()), 0).toRadixString(16);

  static const int segLength = 60 * 6 * 1000;

  static int calcSegment(int progress) {
    return progress ~/ segLength;
  }
}
