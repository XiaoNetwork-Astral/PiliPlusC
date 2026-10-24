import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:PiliPlus/pages/webdav/webdav.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/backup/backup_exception.dart';
import 'package:PiliPlus/utils/backup/backup_item.dart';
import 'package:PiliPlus/utils/backup/backup_method.dart';
import 'package:PiliPlus/utils/backup/clipboard_codec.dart';
import 'package:PiliPlus/utils/config_archive.dart';
import 'package:PiliPlus/utils/date_utils.dart';
import 'package:PiliPlus/utils/extension/file_ext.dart';
import 'package:PiliPlus/utils/font_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

/// 导入预览，页面用 [items] 显示确认信息后再原样传回 import
class BackupPreview {
  const BackupPreview({
    required this.method,
    required this.items,
    required this.warning,
    this.password,
    this.data,
  });

  final BackupMethod method;

  /// 备份文件中实际包含的备份项
  final Set<BackupItem> items;

  /// 版本、来源应用等警告，没有则为 null
  final String? warning;

  /// 解析时使用的密码，导入时可省略 [BackupService.import] 的 password
  final String? password;

  /// 服务内部使用，页面不要解析，原样传给 [BackupService.import]
  final Object? data;
}

/// 已获取的备份来源
///
/// 页面可先 [BackupService.openSource] 一次，再在密码错误时复用同一个
/// source 反复调用 [BackupService.inspect]，避免重复选择文件或下载
class BackupSource {
  const BackupSource._(this.method, this.data);

  final BackupMethod method;

  /// 服务内部使用，页面不要解析
  final Object? data;
}

/// 备份与恢复的底层逻辑
///
/// 服务层不弹对话框、不显示 toast，失败时抛出 [BackupException]，
/// 由页面决定如何展示
///
/// 推荐流程
/// 导出：预检查 [isWebDavConfigured]、[hasWebDavBackup]、[hasClipboardData]
/// 和 [needsAccountWarning]，然后调用 [export]
/// 导入：先 [openSource] 获取备份来源，再调用 [inspect] 拿到
/// [BackupPreview.items] 并弹确认框；加密包按 [savedPasswordOf] 先试密码，
/// 密码错误时复用同一个 [BackupSource] 重试，最后调用 [import] 并传回 preview
abstract final class BackupService {
  static bool get isWebDavConfigured => Pref.webdavUri.trim().isNotEmpty;

  /// 上次使用的备份方式
  static BackupMethod get lastMethod {
    final index = Pref.lastBackupMethod;
    if (index >= 0 && index < BackupMethod.values.length) {
      return BackupMethod.values[index];
    }
    return BackupMethod.webdav;
  }

  static set lastMethod(BackupMethod value) =>
      Pref.lastBackupMethod = value.index;

  static bool get archiveEncrypt => Pref.archiveEncrypt;

  static set archiveEncrypt(bool value) => Pref.archiveEncrypt = value;

  static String get archivePassword => Pref.archivePassword;

  static set archivePassword(String value) => Pref.archivePassword = value;

  static bool get webdavEncrypt => Pref.webdavEncrypt;

  static set webdavEncrypt(bool value) => Pref.webdavEncrypt = value;

  static String get webdavArchivePassword => Pref.webdavArchivePassword;

  static set webdavArchivePassword(String value) =>
      Pref.webdavArchivePassword = value;

  /// 该方式当前是否开启了压缩包加密
  static bool isEncrypted(BackupMethod method) {
    switch (method) {
      case BackupMethod.archive:
        return archiveEncrypt && archivePassword.isNotEmpty;
      case BackupMethod.webdav:
        return webdavEncrypt && webdavArchivePassword.isNotEmpty;
      case BackupMethod.clipboard:
        return false;
    }
  }

  /// 导出登录信息前是否需要弹危险警告
  static bool needsAccountWarning(
    BackupMethod method,
    Set<BackupItem> items,
  ) => items.contains(BackupItem.account) && !isEncrypted(method);

  /// 该方式上次保存的压缩包密码，没有则为空字符串
  static String savedPasswordOf(BackupMethod method) {
    switch (method) {
      case BackupMethod.archive:
        return archivePassword;
      case BackupMethod.webdav:
        return webdavArchivePassword;
      case BackupMethod.clipboard:
        return '';
    }
  }

  /// WebDAV 上是否存在备份文件
  static Future<bool> hasWebDavBackup() async {
    if (!isWebDavConfigured) {
      throw const BackupNotConfiguredException();
    }
    try {
      return await WebDav().hasBackup();
    } on BackupException {
      rethrow;
    } catch (e) {
      throw BackupException('连接失败：$e');
    }
  }

  /// 剪贴板是否有数据
  static Future<bool> hasClipboardData() async {
    final data = await Clipboard.getData('text/plain');
    return data?.text?.trim().isNotEmpty ?? false;
  }

  /// 获取备份来源
  ///
  /// 压缩包方式会打开文件选择器，WebDAV 方式会下载备份，
  /// 剪贴板方式会读取剪贴板
  static Future<BackupSource> openSource(BackupMethod method) async {
    switch (method) {
      case BackupMethod.archive:
        return BackupSource._(method, await _pickArchive());
      case BackupMethod.webdav:
        if (!isWebDavConfigured) {
          throw const BackupNotConfiguredException();
        }
        final webdav = WebDav();
        final Uint8List? bytes;
        try {
          bytes = await webdav.downloadArchive();
        } on BackupException {
          rethrow;
        } catch (e) {
          throw BackupException('导入失败：$e');
        }
        if (bytes != null) {
          return BackupSource._(method, bytes);
        }
        final String? legacy;
        try {
          legacy = await webdav.downloadLegacySettings();
        } catch (e) {
          throw BackupException('导入失败：$e');
        }
        if (legacy == null) {
          throw const BackupNoBackupException();
        }
        return BackupSource._(method, legacy);
      case BackupMethod.clipboard:
        final text = await _readClipboard();
        if (text == null) {
          throw const BackupClipboardEmptyException();
        }
        return BackupSource._(method, text);
    }
  }

  /// 解析备份，得到其中包含的备份项和警告
  ///
  /// 不传 [source] 时会先调用 [openSource]；密码错误重试时请复用一个
  /// 已获取的 source，避免重复选择文件或下载
  static Future<BackupPreview> inspect(
    BackupMethod method, {
    String? password,
    BackupSource? source,
  }) async {
    if (source != null && source.method != method) {
      throw const BackupException('备份来源与备份方式不匹配');
    }
    final sourceOrOpened = source != null
        ? source
        : await openSource(method);
    final data = sourceOrOpened.data;

    switch (method) {
      case BackupMethod.archive:
      case BackupMethod.webdav:
        if (data is Uint8List) {
          final content = _inspectArchive(data, password);
          return BackupPreview(
            method: method,
            items: content.items,
            warning: content.warning,
            password: password,
            data: data,
          );
        }
        if (data is String) {
          return _inspectLegacySettings(data, method);
        }
        throw BackupParseException('未知的备份数据');
      case BackupMethod.clipboard:
        if (data is! String) {
          throw BackupParseException('未知的剪贴板数据');
        }
        final backup = ClipboardCodec.decode(data);
        return BackupPreview(
          method: method,
          items: backup.items,
          warning: null,
          data: backup,
        );
    }
  }

  /// 导出
  ///
  /// 压缩包方式沿用现有的平台保存/分享流程，WebDAV 上传压缩包，
  /// 剪贴板编码成一串字符串并复制
  static Future<void> export(
    BackupMethod method,
    Set<BackupItem> items,
  ) async {
    if (items.isEmpty) {
      throw const BackupSelectionEmptyException();
    }
    final supported = items
        .where((item) => item.isSupportedBy(method))
        .toSet();
    if (supported.isEmpty) {
      throw const BackupSelectionEmptyException();
    }

    try {
      switch (method) {
        case BackupMethod.archive:
          await _exportArchive(supported);
          break;
        case BackupMethod.webdav:
          await _exportWebDav(supported);
          break;
        case BackupMethod.clipboard:
          await _exportClipboard(supported);
          break;
      }
    } on BackupException {
      rethrow;
    } catch (e) {
      throw BackupException('导出失败：$e');
    }
    lastMethod = method;
  }

  /// 导入
  ///
  /// 只恢复已勾选且备份中存在的项，缺项静默跳过
  /// [preview] 为 [inspect] 的返回值，传入后可避免重复选择文件或下载
  /// 返回部分项目导入失败的说明，全部成功时返回 null
  static Future<String?> import(
    BackupMethod method,
    Set<BackupItem> items, {
    String? password,
    BackupPreview? preview,
    Future<bool> Function(String warning)? onWarning,
  }) async {
    if (items.isEmpty) {
      throw const BackupSelectionEmptyException();
    }
    if (preview != null && preview.method != method) {
      throw const BackupException('备份预览与备份方式不匹配');
    }

    final source = preview ?? await inspect(method, password: password);
    final selected = items.where(source.items.contains).toSet();
    if (selected.isEmpty) {
      return null;
    }
    final pwd = password == null || password.isEmpty
        ? source.password
        : password;

    switch (method) {
      case BackupMethod.archive:
      case BackupMethod.webdav:
        return _importArchiveLike(source, selected, pwd, onWarning);
      case BackupMethod.clipboard:
        return _importClipboard(source, selected);
    }
  }

  /// 单个备份项在列表右侧显示的体积或条数
  static String sizeText(BackupItem item) {
    switch (item) {
      case BackupItem.setting:
        return _formatBytes(bytesOf(item) ?? 0);
      case BackupItem.account:
        return '${countOf(item) ?? 0} 个';
      case BackupItem.blacklist:
        return '${countOf(item) ?? 0} 个';
      case BackupItem.reply:
        return '${countOf(item) ?? 0} 条';
      case BackupItem.search:
        return '${countOf(item) ?? 0} 条';
      case BackupItem.customFont:
        final bytes = bytesOf(item);
        return bytes == null ? '0 B' : _formatBytes(bytes);
    }
  }

  /// 真实字节数，没有体积概念时返回 null
  static int? bytesOf(BackupItem item) {
    switch (item) {
      case BackupItem.setting:
        return utf8.encode(GStorage.exportAllSettings()).length;
      case BackupItem.account:
        return utf8.encode(jsonEncode(Accounts.account.toMap())).length;
      case BackupItem.blacklist:
        return null;
      case BackupItem.reply:
        return null;
      case BackupItem.search:
        return null;
      case BackupItem.customFont:
        return FontUtils.fontFile.existsSync()
            ? FontUtils.fontFile.lengthSync()
            : null;
    }
  }

  /// 真实条数，没有条数概念时返回 null
  static int? countOf(BackupItem item) {
    switch (item) {
      case BackupItem.setting:
        return null;
      case BackupItem.account:
        return Accounts.account.length;
      case BackupItem.blacklist:
        return Pref.blackMids.length;
      case BackupItem.reply:
        return GStorage.reply?.length ?? 0;
      case BackupItem.search:
        final list = GStorage.historyWord.get(ConfigArchive.searchCacheKey);
        return list is List ? list.length : 0;
      case BackupItem.customFont:
        return null;
    }
  }

  static Future<void> _exportArchive(Set<BackupItem> items) async {
    final password = _archiveZipPassword();
    final name =
        'piliplus_data_'
        '${DateFormatUtils.only0_9.format(DateTime.now())}.zip';
    try {
      if (PlatformUtils.isDesktop) {
        final path = await FilePicker.saveFile(
          allowedExtensions: const ['zip'],
          type: FileType.custom,
          fileName: name,
          bytes: Uint8List(0),
        );
        if (path == null) {
          throw const BackupCancelledException();
        }
        final out = OutputFileStream(path.toFilePath());
        try {
          ConfigArchive.export(out, items: items, password: password);
          await out.close();
        } catch (_) {
          try {
            await out.close();
          } catch (_) {}
          await File.fromUri(path).tryDel();
          rethrow;
        }
      } else {
        final bytes = ConfigArchive.exportBytes(
          items: items,
          password: password,
        );
        final path = await FilePicker.saveFile(
          allowedExtensions: const ['zip'],
          type: FileType.custom,
          fileName: name,
          bytes: bytes,
        );
        if (path == null) {
          throw const BackupCancelledException();
        }
      }
    } on BackupException {
      rethrow;
    } catch (e) {
      throw BackupException('导出失败：$e');
    }
  }

  static Future<void> _exportWebDav(Set<BackupItem> items) async {
    if (!isWebDavConfigured) {
      throw const BackupNotConfiguredException();
    }
    final password = _webdavZipPassword();
    final bytes = ConfigArchive.exportBytes(
      items: items,
      password: password,
    );
    try {
      await WebDav().uploadArchive(bytes);
    } on BackupException {
      rethrow;
    } catch (e) {
      throw BackupException('上传失败：$e');
    }
  }

  static Future<void> _exportClipboard(Set<BackupItem> items) async {
    final data = <BackupItem, Object?>{};
    for (final item in items) {
      if (!item.isSupportedBy(BackupMethod.clipboard)) continue;
      final value = ConfigArchive.exportDataOf(item);
      if (value != null) {
        data[item] = value;
      }
    }
    if (data.isEmpty) {
      throw const BackupSelectionEmptyException();
    }
    final text = ClipboardCodec.encode(data);
    try {
      await Clipboard.setData(ClipboardData(text: text));
    } catch (e) {
      throw BackupException('导出失败：$e');
    }
  }

  static Future<String?> _importArchiveLike(
    BackupPreview preview,
    Set<BackupItem> items,
    String? password,
    Future<bool> Function(String warning)? onWarning,
  ) async {
    final data = preview.data;
    if (data is Uint8List) {
      var accepted = true;
      try {
        final note = await ConfigArchive.import(
          data,
          items: items,
          password: password,
          onWarning: (warning) async {
            if (onWarning == null) return true;
            accepted = await onWarning(warning);
            return accepted;
          },
        );
        if (!accepted) {
          throw const BackupCancelledException();
        }
        return note == null || note.isEmpty ? null : note;
      } on BackupException {
        rethrow;
      } catch (e) {
        throw BackupParseException('$e');
      }
    }

    // 旧版 WebDAV 纯设置 JSON
    if (data is String) {
      try {
        await GStorage.importAllSettings(data);
        return null;
      } catch (e) {
        throw BackupParseException(
          e is ArgumentError && e.message != null ? '${e.message}' : '$e',
        );
      }
    }

    throw BackupParseException('未知的备份数据');
  }

  static Future<String?> _importClipboard(
    BackupPreview preview,
    Set<BackupItem> items,
  ) async {
    final data = preview.data;
    if (data is! ClipboardBackup) {
      throw BackupParseException('未知的剪贴板数据');
    }

    final sb = StringBuffer();
    for (final entry in data.data.entries) {
      if (!items.contains(entry.key)) continue;
      try {
        switch (entry.key) {
          case BackupItem.setting:
            await ConfigArchive.applySetting(entry.value);
            break;
          case BackupItem.account:
            await ConfigArchive.applyAccount(entry.value);
            break;
          case BackupItem.blacklist:
            ConfigArchive.applyBlacklist(entry.value);
            break;
          case BackupItem.reply:
            ConfigArchive.applyReply(entry.value);
            break;
          case BackupItem.search:
            ConfigArchive.applySearch(entry.value);
            break;
          case BackupItem.customFont:
            break;
        }
      } catch (e) {
        sb.writeln('${entry.key.label}：$e');
      }
    }
    final message = sb.toString();
    return message.isEmpty ? null : message;
  }

  static BackupPreview _inspectLegacySettings(
    String legacy,
    BackupMethod method,
  ) {
    final Object? json;
    try {
      json = jsonDecode(legacy);
    } catch (e) {
      throw BackupParseException('$e');
    }
    if (json is! Map ||
        json['setting'] is! Map ||
        json['video'] is! Map) {
      throw BackupParseException('设置数据格式不正确');
    }
    return BackupPreview(
      method: method,
      items: const {BackupItem.setting},
      warning: null,
      data: legacy,
    );
  }

  static ConfigArchiveContent _inspectArchive(
    Uint8List bytes,
    String? password,
  ) {
    try {
      return ConfigArchive.inspect(bytes, password: password);
    } on BackupException {
      rethrow;
    } catch (e) {
      throw BackupParseException('$e');
    }
  }

  static Future<Uint8List> _pickArchive() async {
    final result = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
    );
    if (result == null) {
      throw const BackupCancelledException();
    }
    try {
      return await result.readAsBytes();
    } catch (e) {
      throw BackupParseException('无法读取文件：$e');
    }
  }

  static Future<String?> _readClipboard() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text?.trim();
    return text == null || text.isEmpty ? null : text;
  }

  static String? _archiveZipPassword() {
    if (!archiveEncrypt) return null;
    if (archivePassword.isEmpty) {
      throw const BackupException('压缩包密码不能为空');
    }
    return archivePassword;
  }

  static String? _webdavZipPassword() {
    if (!webdavEncrypt) return null;
    if (webdavArchivePassword.isEmpty) {
      throw const BackupException('压缩包密码不能为空');
    }
    return webdavArchivePassword;
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
