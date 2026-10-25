import 'package:PiliPlus/common/widgets/dialog/text_input_dialog.dart';
import 'package:PiliPlus/common/widgets/flutter/pop_scope.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/view_safe_area.dart';
import 'package:PiliPlus/pages/backup/widgets/backup_dialogs.dart';
import 'package:PiliPlus/pages/backup/widgets/encryption_setting.dart';
import 'package:PiliPlus/pages/cognitive_filter/widgets.dart';
import 'package:PiliPlus/pages/webdav/webdav.dart';
import 'package:PiliPlus/utils/backup/backup.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class WebDavSettingPage extends StatefulWidget {
  const WebDavSettingPage({
    super.key,
    this.showAppBar = true,
  });

  final bool showAppBar;

  @override
  State<WebDavSettingPage> createState() => _WebDavSettingPageState();
}

class _WebDavSettingPageState extends State<WebDavSettingPage> {
  String _uri = Pref.webdavUri;
  String _username = Pref.webdavUsername;
  String _password = Pref.webdavPassword;
  String _directory = Pref.webdavDirectory;

  String _savedUri = Pref.webdavUri;
  String _savedUsername = Pref.webdavUsername;
  String _savedPassword = Pref.webdavPassword;
  String _savedDirectory = Pref.webdavDirectory;

  bool _testing = false;
  bool _encryptionDirty = false;

  bool get _infoDirty =>
      _uri != _savedUri ||
      _username != _savedUsername ||
      _password != _savedPassword ||
      _directory != _savedDirectory;

  bool get _dirty => _infoDirty || _encryptionDirty;

  String? _validateUri(String uri) {
    if (uri.isEmpty) return '地址不能为空';
    if (!uri.startsWith('http://') && !uri.startsWith('https://')) {
      return '地址需以 http:// 或 https:// 开头';
    }
    return null;
  }

  Future<void> _editUri() async {
    final result = await showTextInputDialog(
      context: context,
      title: '地址',
      initialValue: _uri,
      keyboardType: TextInputType.url,
      validator: _validateUri,
    );
    if (result != null) setState(() => _uri = result);
  }

  Future<void> _editUsername() async {
    final result = await showTextInputDialog(
      context: context,
      title: '用户',
      initialValue: _username,
    );
    if (result != null) setState(() => _username = result);
  }

  Future<void> _editPassword() async {
    final result = await showTextInputDialog(
      context: context,
      title: '密码',
      initialValue: _password,
      obscureText: true,
    );
    if (result != null) setState(() => _password = result);
  }

  Future<void> _editDirectory() async {
    final result = await showTextInputDialog(
      context: context,
      title: '路径',
      initialValue: _directory,
    );
    if (result != null) setState(() => _directory = result);
  }

  Future<void> _saveInfo() async {
    final error = _validateUri(_uri);
    if (error != null) {
      SmartDialog.showToast(error);
      return;
    }
    await GStorage.setting.putAll({
      SettingBoxKey.webdavUri: _uri,
      SettingBoxKey.webdavUsername: _username,
      SettingBoxKey.webdavPassword: _password,
      SettingBoxKey.webdavDirectory: _directory,
    });
    if (!mounted) return;
    setState(() {
      _savedUri = _uri;
      _savedUsername = _username;
      _savedPassword = _password;
      _savedDirectory = _directory;
    });
  }

  Future<void> _testConnection() async {
    final error = _validateUri(_uri);
    if (error != null) {
      SmartDialog.showToast(error);
      return;
    }
    setState(() => _testing = true);

    final origin = {
      SettingBoxKey.webdavUri: Pref.webdavUri,
      SettingBoxKey.webdavUsername: Pref.webdavUsername,
      SettingBoxKey.webdavPassword: Pref.webdavPassword,
      SettingBoxKey.webdavDirectory: Pref.webdavDirectory,
    };
    final target = {
      SettingBoxKey.webdavUri: _uri,
      SettingBoxKey.webdavUsername: _username,
      SettingBoxKey.webdavPassword: _password,
      SettingBoxKey.webdavDirectory: _directory,
    };
    String message;
    try {
      await GStorage.setting.putAll(target);
      final result = await WebDav().init();
      message = result.first ? '连接成功' : '连接失败：${result.second}';
    } catch (e) {
      message = '连接失败：${WebDav.describeError(e)}';
    } finally {
      await GStorage.setting.putAll(origin);
      if (mounted) {
        setState(() => _testing = false);
      }
    }
    if (mounted) {
      SmartDialog.showToast(message);
    }
  }

  Future<void> _saveEncryption(bool encrypt, String password) async {
    final value = encrypt ? password : '';
    BackupService.webdavEncrypt = encrypt;
    BackupService.webdavArchivePassword = value;
    await GStorage.setting.putAll({
      SettingBoxKey.webdavEncrypt: encrypt,
      SettingBoxKey.webdavArchivePassword: value,
    });
  }

  Future<void> _onBack() async {
    final discard = await showUnsavedChangesDialog(context);
    if (!discard || !mounted) return;
    setState(() {
      _savedUri = _uri;
      _savedUsername = _username;
      _savedPassword = _password;
      _savedDirectory = _directory;
      _encryptionDirty = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Get.back();
    });
  }

  @override
  Widget build(BuildContext context) {
    final showAppBar = widget.showAppBar;
    final padding = MediaQuery.viewPaddingOf(context);
    final page = SimpleScaffold(
      appBar: showAppBar ? AppBar(title: const Text('WebDAV 设置')) : null,
      body: ViewSafeArea(
        child: ListView(
          padding: EdgeInsets.only(bottom: padding.bottom + 100),
          children: [
            CfTile(
              icon: Icons.link,
              title: '地址',
              subtitle: _uri.isEmpty ? null : _uri,
              onTap: _editUri,
            ),
            CfTile(
              icon: Icons.person_outline,
              title: '用户',
              subtitle: _username.isEmpty ? null : _username,
              onTap: _editUsername,
            ),
            CfTile(
              icon: Icons.key,
              title: '密码',
              subtitle: _password.isEmpty ? null : '••••••••',
              onTap: _editPassword,
            ),
            CfTile(
              icon: Icons.folder_outlined,
              title: '路径',
              subtitle: _directory.isEmpty ? null : _directory,
              onTap: _editDirectory,
            ),
            CfTile(
              icon: Icons.wifi_tethering,
              title: '测试连接',
              enabled: !_testing,
              trailing: _testing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
              onTap: _testConnection,
            ),
            CfTile(
              icon: Icons.save_outlined,
              title: '保存',
              enabled: _infoDirty,
              onTap: _saveInfo,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: EncryptionSetting(
                initialEncrypt: BackupService.webdavEncrypt,
                initialPassword: BackupService.webdavArchivePassword,
                onDirtyChanged: (value) {
                  if (_encryptionDirty == value || !mounted) return;
                  setState(() => _encryptionDirty = value);
                },
                onSave: _saveEncryption,
              ),
            ),
          ],
        ),
      ),
    );
    if (!showAppBar) return page;
    return popScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _onBack();
      },
      child: page,
    );
  }
}
