import 'package:PiliPlus/common/widgets/flutter/pop_scope.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/view_insets_safe_area.dart';
import 'package:PiliPlus/pages/backup/widgets/backup_dialogs.dart';
import 'package:PiliPlus/pages/backup/widgets/encryption_setting.dart';
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
  final _uriCtr = TextEditingController(text: Pref.webdavUri);
  final _usernameCtr = TextEditingController(text: Pref.webdavUsername);
  final _passwordCtr = TextEditingController(text: Pref.webdavPassword);
  final _directoryCtr = TextEditingController(text: Pref.webdavDirectory);

  String _savedUri = Pref.webdavUri;
  String _savedUsername = Pref.webdavUsername;
  String _savedPassword = Pref.webdavPassword;
  String _savedDirectory = Pref.webdavDirectory;

  bool _obscureText = true;
  bool _testing = false;
  bool _encryptionDirty = false;
  String? _uriError;

  bool get _infoDirty =>
      _uriCtr.text != _savedUri ||
      _usernameCtr.text != _savedUsername ||
      _passwordCtr.text != _savedPassword ||
      _directoryCtr.text != _savedDirectory;

  bool get _dirty => _infoDirty || _encryptionDirty;

  @override
  void dispose() {
    _uriCtr.dispose();
    _usernameCtr.dispose();
    _passwordCtr.dispose();
    _directoryCtr.dispose();
    super.dispose();
  }

  Future<void> _saveInfo() async {
    final uri = _uriCtr.text;
    final trimmed = uri.trim();
    String? error;
    if (trimmed.isEmpty) {
      error = '地址不能为空';
    } else if (!trimmed.startsWith('http://') &&
        !trimmed.startsWith('https://')) {
      error = '地址需以 http:// 或 https:// 开头';
    }
    if (error != null) {
      setState(() => _uriError = error);
      return;
    }

    await GStorage.setting.putAll({
      SettingBoxKey.webdavUri: uri,
      SettingBoxKey.webdavUsername: _usernameCtr.text,
      SettingBoxKey.webdavPassword: _passwordCtr.text,
      SettingBoxKey.webdavDirectory: _directoryCtr.text,
    });
    if (!mounted) return;
    setState(() {
      _savedUri = uri;
      _savedUsername = _usernameCtr.text;
      _savedPassword = _passwordCtr.text;
      _savedDirectory = _directoryCtr.text;
      _uriError = null;
    });
    SmartDialog.showToast('已保存');
  }

  Future<void> _testConnection() async {
    if (_uriCtr.text.trim().isEmpty) {
      setState(() => _uriError = '地址不能为空');
      return;
    }
    setState(() {
      _uriError = null;
      _testing = true;
    });

    final origin = {
      SettingBoxKey.webdavUri: Pref.webdavUri,
      SettingBoxKey.webdavUsername: Pref.webdavUsername,
      SettingBoxKey.webdavPassword: Pref.webdavPassword,
      SettingBoxKey.webdavDirectory: Pref.webdavDirectory,
    };
    final target = {
      SettingBoxKey.webdavUri: _uriCtr.text,
      SettingBoxKey.webdavUsername: _usernameCtr.text,
      SettingBoxKey.webdavPassword: _passwordCtr.text,
      SettingBoxKey.webdavDirectory: _directoryCtr.text,
    };
    String message;
    try {
      await GStorage.setting.putAll(target);
      final result = await WebDav().init();
      message = result.first ? '连接成功' : '连接失败：${result.second}';
    } catch (e) {
      message = '连接失败：$e';
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
      _savedUri = _uriCtr.text;
      _savedUsername = _usernameCtr.text;
      _savedPassword = _passwordCtr.text;
      _savedDirectory = _directoryCtr.text;
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
      body: ViewInsetsSafeArea(
        child: ListView(
          padding: EdgeInsets.only(
            top: 20,
            left: 20 + (showAppBar ? padding.left : 0),
            right: 20 + (showAppBar ? padding.right : 0),
            bottom: padding.bottom + 40,
          ),
          children: [
            TextField(
              controller: _uriCtr,
              keyboardType: TextInputType.url,
              onChanged: (_) => setState(() => _uriError = null),
              decoration: InputDecoration(
                labelText: '地址',
                border: const OutlineInputBorder(),
                errorText: _uriError,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _usernameCtr,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: '用户',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _passwordCtr,
              autofillHints: const [AutofillHints.password],
              obscureText: _obscureText,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: '密码',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscureText = !_obscureText),
                  icon: _obscureText
                      ? const Icon(Icons.visibility)
                      : const Icon(Icons.visibility_off),
                ),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _directoryCtr,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: '路径',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FilledButton.tonal(
                  onPressed: _testing ? null : _testConnection,
                  child: const Text('测试连接'),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _infoDirty ? _saveInfo : null,
                  child: const Text('保存'),
                ),
              ],
            ),
            const SizedBox(height: 28),
            EncryptionSetting(
              initialEncrypt: BackupService.webdavEncrypt,
              initialPassword: BackupService.webdavArchivePassword,
              onDirtyChanged: (value) {
                if (_encryptionDirty == value || !mounted) return;
                setState(() => _encryptionDirty = value);
              },
              onSave: _saveEncryption,
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
