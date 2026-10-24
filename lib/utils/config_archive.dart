import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:PiliPlus/build_config.dart';
import 'package:PiliPlus/common/constants.dart';
import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart'
    show ReplyInfo;
import 'package:PiliPlus/pages/my_reply/view.dart';
import 'package:PiliPlus/pages/search/controller.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/backup/backup_exception.dart';
import 'package:PiliPlus/utils/backup/backup_item.dart';
import 'package:PiliPlus/utils/device_utils.dart';
import 'package:PiliPlus/utils/font_utils.dart';
import 'package:PiliPlus/utils/global_data.dart';
import 'package:PiliPlus/utils/parse_int.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:archive/archive.dart';
import 'package:get/get.dart';

/// 备份压缩包解析结果
class ConfigArchiveContent {
  const ConfigArchiveContent({
    required this.items,
    required this.warning,
    required this.encrypted,
  });

  /// 压缩包实际包含的备份项
  final Set<BackupItem> items;

  /// 版本、来源应用等合并警告
  final String? warning;

  /// 压缩包是否加密
  final bool encrypted;
}

class _OpenedArchive {
  const _OpenedArchive({
    required this.archive,
    required this.content,
  });

  final Archive archive;
  final ConfigArchiveContent content;
}

abstract final class ConfigArchive {
  static const String metaFileName = 'meta.json';
  static const String settingFileName = 'setting.json';
  static const String accountFileName = 'account.json';
  static const String blacklistFileName = 'blacklist.json';
  static const String replyFileName = 'reply.json';
  static const String searchFileName = 'search.json';
  static const String fontFileName = FontUtils.kFontName;

  static const String _type = 'data_archive';

  /// 归档格式版本
  static const int _majorVersion = 0x0001;
  static const int _minorVersion = 0x0000;

  /// 搜索历史的存储 key
  static const String searchCacheKey = 'cacheList';

  /// 解压后总大小上限
  static const int _maxTotalBytes = 64 * 1024 * 1024;

  /// 按所选项导出，[items] 为 null 时导出全部项目
  ///
  /// [password] 非空时使用 AES-256 加密压缩包
  static void export(
    OutputStream stream, {
    Set<BackupItem>? items,
    String? password,
  }) {
    bool want(BackupItem item) => items == null || items.contains(item);

    final zip = ZipEncoder(password: _passwordOrNull(password))
      ..startEncode(stream);
    final files = <String>[];

    if (want(BackupItem.setting)) {
      zip.add(ArchiveFile.string(settingFileName, GStorage.exportAllSettings()));
      files.add(settingFileName);
    }

    if (want(BackupItem.account)) {
      zip.add(ArchiveFile.string(accountFileName, _exportAccount()));
      files.add(accountFileName);
    }

    if (want(BackupItem.blacklist)) {
      zip.add(ArchiveFile.string(blacklistFileName, _exportBlacklist()));
      files.add(blacklistFileName);
    }

    if (want(BackupItem.reply)) {
      final reply = _exportReply();
      if (reply != null) {
        zip.add(ArchiveFile.string(replyFileName, reply));
        files.add(replyFileName);
      }
    }

    if (want(BackupItem.search)) {
      zip.add(ArchiveFile.string(searchFileName, _exportSearch()));
      files.add(searchFileName);
    }

    if (want(BackupItem.customFont) && FontUtils.fontFile.existsSync()) {
      zip.add(
        ArchiveFile.stream(
          fontFileName,
          InputFileStream(FontUtils.fontFile.path),
        ),
      );
      files.add(fontFileName);
    }

    zip
      ..add(ArchiveFile.string(metaFileName, _buildMeta(files)))
      ..endEncode();
  }

  /// 导出为内存中的压缩包字节
  static Uint8List exportBytes({
    Set<BackupItem>? items,
    String? password,
  }) {
    final out = OutputMemoryStream();
    try {
      export(out, items: items, password: password);
      return Uint8List.fromList(out.getBytes());
    } finally {
      out.closeSync();
    }
  }

  /// 只解析压缩包，不写入任何数据
  ///
  /// 加密压缩包需要提供正确密码，否则抛出
  /// [BackupPasswordRequiredException] 或 [BackupPasswordWrongException]
  static ConfigArchiveContent inspect(Uint8List bytes, {String? password}) {
    return _open(bytes, password).content;
  }

  /// 按所选项导入
  ///
  /// [items] 为 null 时尝试导入全部项目，备份中不存在的项目静默跳过
  /// 返回值为部分项目导入失败的说明，全部成功时返回 null
  static Future<String?> import(
    Uint8List bytes, {
    Set<BackupItem>? items,
    String? password,
    required Future<bool> Function(String warning) onWarning,
  }) async {
    final opened = _open(bytes, password);
    final warning = opened.content.warning;
    if (warning != null && !await onWarning(warning)) {
      return null;
    }

    final archive = opened.archive;
    final sb = StringBuffer();
    var totalBytes = 0;

    Future<void> applyItem(
      BackupItem item,
      String name,
      FutureOr<void> Function(Object?) action,
    ) async {
      if (!_want(item, items)) return;
      final file = archive.find(name);
      if (file == null) return;

      totalBytes += file.size;
      if (totalBytes > _maxTotalBytes) {
        throw const BackupException('压缩包过大');
      }

      try {
        await action(jsonDecode(utf8.decode(file.content)));
      } catch (e) {
        sb.writeln('$name：$e');
      } finally {
        file.closeSync();
      }
    }

    await applyItem(BackupItem.setting, settingFileName, applySetting);
    await applyItem(BackupItem.account, accountFileName, applyAccount);
    await applyItem(
      BackupItem.blacklist,
      blacklistFileName,
      (data) async => applyBlacklist(data),
    );
    await applyItem(
      BackupItem.reply,
      replyFileName,
      (data) async => applyReply(data),
    );
    await applyItem(
      BackupItem.search,
      searchFileName,
      (data) async => applySearch(data),
    );

    if (_want(BackupItem.customFont, items)) {
      if (archive.find(fontFileName) case final file?) {
        totalBytes += file.size;
        if (totalBytes > _maxTotalBytes) {
          throw const BackupException('压缩包过大');
        }
        final family = GStorage.setting.get(SettingBoxKey.appFont);
        if (family is String && family.contains('/')) {
          try {
            final content = file.content;
            await ui.loadFontFromList(content, fontFamily: family);
            await FontUtils.fontFile.writeAsBytes(content);
            FontUtils.appFont = (fontFamily: family, isCustom: true);
          } catch (e) {
            sb.writeln('$fontFileName：$e');
          } finally {
            file.closeSync();
          }
        } else {
          sb.writeln('$fontFileName：无法获取字体名');
          file.closeSync();
        }
      }
    }

    return sb.toString();
  }

  /// 读取单项数据，供剪贴板编码使用
  ///
  /// 自定义字体只存在于压缩包中，这里返回 null
  static Object? exportDataOf(BackupItem item) {
    switch (item) {
      case BackupItem.setting:
        return jsonDecode(GStorage.exportAllSettings());
      case BackupItem.account:
        return jsonDecode(_exportAccount());
      case BackupItem.blacklist:
        return Pref.blackMids.toList();
      case BackupItem.reply:
        final reply = _exportReply();
        return reply == null ? const <Object?>[] : jsonDecode(reply);
      case BackupItem.search:
        return jsonDecode(_exportSearch());
      case BackupItem.customFont:
        return null;
    }
  }

  /// 写入设置，供压缩包和剪贴板导入共用
  static Future<void> applySetting(Object? data) async {
    if (data is! Map<String, dynamic> ||
        data[GStorage.setting.name] is! Map ||
        data[GStorage.video.name] is! Map) {
      throw const BackupException('设置数据格式不正确');
    }
    await GStorage.importAllJsonSettings(data);
  }

  /// 写入登录信息
  static Future<void> applyAccount(Object? data) async {
    if (data is! Map<String, dynamic>) {
      throw const BackupException('登录信息格式不正确');
    }
    await Accounts.importJsonAccount(data);
  }

  /// 写入黑名单
  static void applyBlacklist(Object? data) {
    if (data is! List) {
      throw const BackupException('黑名单数据格式不正确');
    }
    _importBlacklist(data);
  }

  /// 写入历史评论
  static void applyReply(Object? data) {
    if (data is! List) {
      throw const BackupException('历史评论数据格式不正确');
    }
    _importReply(data);
  }

  /// 写入搜索记录
  static void applySearch(Object? data) {
    if (data is! List) {
      throw const BackupException('搜索记录数据格式不正确');
    }
    _importSearch(data);
  }

  /// 根据压缩包内文件名反查备份项
  static BackupItem? itemOfFile(String name) {
    switch (name) {
      case settingFileName:
        return BackupItem.setting;
      case accountFileName:
        return BackupItem.account;
      case blacklistFileName:
        return BackupItem.blacklist;
      case replyFileName:
        return BackupItem.reply;
      case searchFileName:
        return BackupItem.search;
      case fontFileName:
        return BackupItem.customFont;
      default:
        return null;
    }
  }

  static _OpenedArchive _open(Uint8List bytes, String? password) {
    if (bytes.length > _maxTotalBytes) {
      throw const BackupException('压缩包过大');
    }

    final encrypted = _isEncryptedZip(bytes);
    final pwd = _passwordOrNull(password);
    if (encrypted && pwd == null) {
      throw const BackupPasswordRequiredException();
    }

    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(
        bytes,
        password: encrypted ? pwd : null,
      );
    } catch (_) {
      if (encrypted) {
        throw const BackupPasswordWrongException();
      }
      throw const BackupException('不是有效的备份压缩包');
    }

    // 校验 meta
    final metaFile = archive.find(metaFileName);
    if (metaFile == null) {
      throw BackupException('不是有效的备份压缩包（缺少 $metaFileName）');
    }

    final Object? metaJson;
    try {
      metaJson = jsonDecode(utf8.decode(metaFile.content));
    } catch (_) {
      if (encrypted) {
        throw const BackupPasswordWrongException();
      }
      throw const BackupException('不是有效的备份压缩包');
    }
    if (metaJson is! Map || metaJson['type'] != _type) {
      throw const BackupException('不是有效的备份压缩包');
    }

    // 校验 formatVersion
    final format = _parseFormat(metaJson['formatVersion']);
    if (format == null) {
      throw BackupException('不是有效的备份压缩包（缺少合法的 formatVersion）');
    }
    if (format.major > _majorVersion) {
      throw BackupException(
        '压缩包格式过新（${format.toVersionString()}），请升级应用后再导入',
      );
    }

    return _OpenedArchive(
      archive: archive,
      content: ConfigArchiveContent(
        items: _itemsOf(archive, metaJson),
        warning: _warningOf(metaJson),
        encrypted: encrypted,
      ),
    );
  }

  static Set<BackupItem> _itemsOf(Archive archive, Map meta) {
    final names = <String>{};
    final files = meta['files'];
    if (files is List) {
      for (final file in files) {
        if (file is String) names.add(file);
      }
    }
    for (final file in archive.files) {
      names.add(file.name);
    }

    final items = <BackupItem>{};
    for (final name in names) {
      final item = itemOfFile(name);
      if (item != null) items.add(item);
    }
    return items;
  }

  /// 判断 ZIP 是否加密
  ///
  /// ZIP 本地文件头的通用标志位 bit0 表示加密，AES 加密同样会置位
  static bool _isEncryptedZip(Uint8List bytes) {
    const signature = [0x50, 0x4b, 0x03, 0x04];
    final limit = bytes.length - 8 < 0x10000
        ? bytes.length - 8
        : 0x10000;
    for (var i = 0; i <= limit; i++) {
      if (bytes[i] == signature[0] &&
          bytes[i + 1] == signature[1] &&
          bytes[i + 2] == signature[2] &&
          bytes[i + 3] == signature[3]) {
        return (bytes[i + 6] & 0x01) != 0;
      }
    }
    return false;
  }

  static bool _want(BackupItem item, Set<BackupItem>? items) =>
      items == null || items.contains(item);

  static String? _passwordOrNull(String? password) =>
      password == null || password.isEmpty ? null : password;

  /// 生成合并警告
  static String? _warningOf(Map meta) {
    final warnings = StringBuffer();

    final format = _parseFormat(meta['formatVersion']);
    if (format != null &&
        format.major == _majorVersion &&
        format.minor > _minorVersion) {
      warnings.writeln('此压缩包使用更新的归档格式（${format.toVersionString()}），部分数据可能无法识别');
    }

    final sourceApp = meta['appName'];
    if (sourceApp != Constants.appName) {
      warnings.writeln('此压缩包来自「$sourceApp」，与当前应用不同，可能不完全兼容');
    }

    final packageCode = safeToInt(meta['versionCode']);
    if (packageCode != null && packageCode > BuildConfig.versionCode) {
      final versionName = meta['versionName'];
      warnings.writeln(
        '此压缩包来自更新版本（v$versionName，构建号 $packageCode），'
        '当前应用较旧（v${BuildConfig.versionName}，构建号 ${BuildConfig.versionCode}），'
        '部分数据可能无法正确还原',
      );
    }
    return warnings.isEmpty ? null : warnings.toString();
  }

  /// 解析 [主, 次] 格式版本
  static VersionCode? _parseFormat(Object? value) {
    if (value is int) {
      return VersionCode(value);
    }
    return null;
  }

  static String _exportAccount() => jsonEncode(Accounts.account.toMap());

  static String _exportBlacklist() => jsonEncode(Pref.blackMids.toList());

  static String? _exportReply() {
    final box = GStorage.reply;
    if (box == null) return null;
    return jsonEncode(
      box.values.map((e) => ReplyInfo.fromBuffer(e).toProto3Json()).toList(),
    );
  }

  static String _exportSearch() {
    final list = GStorage.historyWord.get(searchCacheKey);
    return jsonEncode(list ?? const <String>[]);
  }

  static String _buildMeta(List<String> files) => jsonEncode({
    'type': _type,
    'formatVersion': const VersionCode.fromMajorMinor(
      _majorVersion,
      _minorVersion,
    ),
    'appName': Constants.appName,
    'versionCode': BuildConfig.versionCode,
    'versionName': BuildConfig.versionName,
    'commitHash': BuildConfig.commitHash,
    'buildTime': BuildConfig.buildTime,
    'platform': DeviceUtils.platformName,
    'exportTime': DateTime.now().toIso8601String(),
    'files': files,
  });

  static void _importBlacklist(List<dynamic> list) {
    // 就地覆盖，保持已有引用
    final set = GlobalData().blackMids
      ..clear()
      ..addAll(Set<int>.from(list));
    Pref.blackMids = set;
  }

  static void _importReply(List<dynamic> list) {
    final box = GStorage.reply;
    if (box == null) return;
    box.putAll(MyReply.json2ReplyProto(list));
  }

  static void _importSearch(List<dynamic> list) {
    final history = List<String>.from(list);
    GStorage.historyWord.put(searchCacheKey, history);
    // 同步刷新内存单例，避免被旧列表覆盖
    if (Get.isRegistered<BaseSearchController>()) {
      Get.find<BaseSearchController>().historyList.assignAll(history);
    }
  }
}

extension type VersionCode(int _version) {
  int get major => _version >>> 16;
  int get minor => _version & 0xFFFF;

  const VersionCode.fromMajorMinor(int major, int minor)
    : _version = (major << 16) | minor;

  String toVersionString() => '$major.$minor';
}
