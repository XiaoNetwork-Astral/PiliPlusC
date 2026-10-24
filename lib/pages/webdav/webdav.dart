import 'dart:convert';
import 'dart:typed_data';

import 'package:PiliPlus/common/constants.dart';
import 'package:PiliPlus/common/widgets/pair.dart';
import 'package:PiliPlus/utils/device_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:dio/dio.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;

typedef _WebDavConfig = ({
  String uri,
  String username,
  String password,
  String directory,
});

class WebDav {
  _WebDavConfig? _clientConfig;
  webdav.Client? _client;

  WebDav._internal();
  static final WebDav _instance = WebDav._internal();
  factory WebDav() => _instance;

  /// 新的压缩包备份文件名
  String get archiveFileName =>
      'piliplus_backup_${DeviceUtils.platformName}.zip';

  /// 旧版纯设置 JSON 文件名，恢复时兼容
  String get legacyFileName =>
      'piliplus_settings_${DeviceUtils.platformName}.json';

  _WebDavConfig _getConfig() {
    String directory = Pref.webdavDirectory;
    if (!directory.endsWith('/')) {
      directory += '/';
    }
    return (
      uri: Pref.webdavUri,
      username: Pref.webdavUsername,
      password: Pref.webdavPassword,
      directory: '$directory${Constants.appName}',
    );
  }

  Future<webdav.Client> _connect(
    _WebDavConfig config, {
    bool force = false,
  }) async {
    final cachedClient = _client;
    if (!force && cachedClient != null && _clientConfig == config) {
      return cachedClient;
    }

    final client =
        webdav.newClient(
            config.uri,
            user: config.username,
            password: config.password,
          )
          ..setHeaders({'accept-charset': 'utf-8'})
          ..setConnectTimeout(12000)
          ..setReceiveTimeout(12000)
          ..setSendTimeout(12000);

    await client.mkdirAll(config.directory);
    _clientConfig = config;
    _client = client;
    return client;
  }

  Future<Pair<bool, String?>> init() async {
    try {
      await _connect(_getConfig(), force: true);

      return Pair(first: true, second: null);
    } catch (e) {
      return Pair(first: false, second: describeError(e));
    }
  }

  /// 把连接异常翻译成针对具体字段的提示
  static String describeError(Object e) {
    if (e is DioException) {
      final code = e.response?.statusCode;
      if (code == 401 || code == 403) return '用户或密码错误';
      if (code == 404) return '地址或路径不存在';
      if (code != null) {
        if (code >= 200 && code < 300) {
          return '服务器响应异常，请确认地址是 WebDAV 服务';
        }
        return 'HTTP $code';
      }
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.connectionError:
          return '无法连接到服务器，请检查地址与网络';
        default:
          break;
      }
    }
    final text = e.toString();
    if (text.contains('Unauthorized') || text.contains('Forbidden')) {
      return '用户或密码错误';
    }
    return text;
  }

  Future<Uint8List?> _readOrNull(
    webdav.Client client,
    String path,
  ) async {
    try {
      final data = await client.read(path);
      return Uint8List.fromList(data);
    } catch (_) {
      return null;
    }
  }

  /// 服务器上是否存在备份，优先检查新压缩包，再回退旧 JSON
  Future<bool> hasBackup() async {
    final config = _getConfig();
    final client = await _connect(config);
    final archivePath = '${config.directory}/$archiveFileName';
    if (await _readOrNull(client, archivePath) != null) {
      return true;
    }
    final legacyPath = '${config.directory}/$legacyFileName';
    return await _readOrNull(client, legacyPath) != null;
  }

  /// 上传压缩包备份
  Future<void> uploadArchive(Uint8List bytes) async {
    final config = _getConfig();
    final client = await _connect(config);
    final path = '${config.directory}/$archiveFileName';
    try {
      await client.remove(path);
    } catch (_) {}
    await client.write(path, bytes);
  }

  /// 下载新的压缩包备份，不存在时返回 null
  Future<Uint8List?> downloadArchive() async {
    final config = _getConfig();
    final client = await _connect(config);
    return _readOrNull(client, '${config.directory}/$archiveFileName');
  }

  /// 下载旧版纯设置 JSON，不存在时返回 null
  Future<String?> downloadLegacySettings() async {
    final config = _getConfig();
    final client = await _connect(config);
    final data = await _readOrNull(
      client,
      '${config.directory}/$legacyFileName',
    );
    return data == null ? null : utf8.decode(data);
  }
}
