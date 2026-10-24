import 'dart:convert';

import 'package:PiliPlus/utils/backup/backup_exception.dart';
import 'package:PiliPlus/utils/backup/backup_item.dart';
import 'package:PiliPlus/utils/backup/backup_method.dart';

/// 剪贴板备份内容
///
/// key 为备份项，value 为可直接 JSON 编码的数据
class ClipboardBackup {
  const ClipboardBackup(this.data);

  final Map<BackupItem, Object?> data;

  Set<BackupItem> get items => data.keys.toSet();
}

/// 剪贴板备份的编码与解码
///
/// 新格式是一串带前缀的 base64 字符串，编码不是加密
/// 解码同时兼容旧版明文 JSON，包括旧设置 JSON、登录信息 JSON
/// 以及旧版黑名单、历史评论、搜索记录列表
abstract final class ClipboardCodec {
  /// 新格式前缀
  static const String prefix = 'piliplus_backup_v1:';

  static const String _type = 'clipboard_backup';
  static const int _version = 1;

  /// 编码成一串字符串
  static String encode(Map<BackupItem, Object?> data) {
    final payload = {
      'type': _type,
      'version': _version,
      'items': <String, Object?>{
        for (final entry in data.entries) entry.key.name: entry.value,
      },
    };
    return '$prefix${base64Encode(utf8.encode(jsonEncode(payload)))}';
  }

  /// 解码剪贴板字符串
  ///
  /// 无法识别时抛出 [BackupParseException]，剪贴板为空时抛出
  /// [BackupClipboardEmptyException]
  static ClipboardBackup decode(String text) {
    final value = text.trim();
    if (value.isEmpty) {
      throw const BackupClipboardEmptyException();
    }
    if (value.startsWith(prefix)) {
      return _decodeNew(value);
    }
    return _decodeLegacy(value);
  }

  static ClipboardBackup _decodeNew(String text) {
    try {
      final raw = text.substring(prefix.length).replaceAll(RegExp(r'\s'), '');
      final json = jsonDecode(utf8.decode(base64Decode(raw)));
      if (json is! Map ||
          json['type'] != _type ||
          json['version'] != _version ||
          json['items'] is! Map) {
        throw BackupParseException('剪贴板数据格式不正确');
      }
      final items = json['items'] as Map;
      final data = <BackupItem, Object?>{};
      for (final entry in items.entries) {
        final item = _itemOf(entry.key);
        if (item != null && item.isSupportedBy(BackupMethod.clipboard)) {
          data[item] = entry.value;
        }
      }
      if (data.isEmpty) {
        throw BackupParseException('没有可导入的数据');
      }
      return ClipboardBackup(data);
    } on BackupException {
      rethrow;
    } catch (e) {
      throw BackupParseException('$e');
    }
  }

  static ClipboardBackup _decodeLegacy(String text) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } catch (e) {
      throw BackupParseException('$e');
    }

    if (json is Map) {
      // 旧设置 JSON：{"setting": {...}, "video": {...}}
      if (json['setting'] is Map || json['video'] is Map) {
        return ClipboardBackup({BackupItem.setting: json});
      }
      // 旧登录信息 JSON：{账户 ID: 账户信息}
      if (json.values.every((value) => value is Map)) {
        return ClipboardBackup({BackupItem.account: json});
      }
      throw BackupParseException('无法识别的 JSON 数据');
    }

    if (json is List) {
      // 空列表无法区分黑名单、历史评论和搜索记录，按解析失败处理
      if (json.isEmpty) {
        throw BackupParseException('无法识别的 JSON 数据');
      }
      if (json.every((value) => value is int)) {
        return ClipboardBackup({BackupItem.blacklist: json});
      }
      if (json.every((value) => value is String)) {
        return ClipboardBackup({BackupItem.search: json});
      }
      if (json.every((value) => value is Map)) {
        return ClipboardBackup({BackupItem.reply: json});
      }
    }

    throw BackupParseException('无法识别的 JSON 数据');
  }

  static BackupItem? _itemOf(Object? key) {
    if (key is! String) return null;
    for (final item in BackupItem.values) {
      if (item.name == key) return item;
    }
    return null;
  }
}
