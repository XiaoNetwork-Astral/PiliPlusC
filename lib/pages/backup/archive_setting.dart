import 'package:PiliPlus/common/widgets/flutter/pop_scope.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/view_insets_safe_area.dart';
import 'package:PiliPlus/pages/backup/widgets/backup_dialogs.dart';
import 'package:PiliPlus/pages/backup/widgets/encryption_setting.dart';
import 'package:PiliPlus/utils/backup/backup.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class ArchiveSettingPage extends StatefulWidget {
  const ArchiveSettingPage({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  State<ArchiveSettingPage> createState() => _ArchiveSettingPageState();
}

class _ArchiveSettingPageState extends State<ArchiveSettingPage> {
  bool _dirty = false;

  Future<void> _saveEncryption(bool encrypt, String password) async {
    final value = encrypt ? password : '';
    BackupService.archiveEncrypt = encrypt;
    BackupService.archivePassword = value;
    await GStorage.setting.putAll({
      SettingBoxKey.archiveEncrypt: encrypt,
      SettingBoxKey.archivePassword: value,
    });
  }

  Future<void> _onBack() async {
    final discard = await showUnsavedChangesDialog(context);
    if (!discard || !mounted) return;
    setState(() => _dirty = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Get.back();
    });
  }

  @override
  Widget build(BuildContext context) {
    final showAppBar = widget.showAppBar;
    final padding = MediaQuery.viewPaddingOf(context);
    final page = SimpleScaffold(
      appBar: showAppBar ? AppBar(title: const Text('压缩包设置')) : null,
      body: ViewInsetsSafeArea(
        child: ListView(
          padding: EdgeInsets.only(
            top: 20,
            left: 20 + (showAppBar ? padding.left : 0),
            right: 20 + (showAppBar ? padding.right : 0),
            bottom: padding.bottom + 40,
          ),
          children: [
            EncryptionSetting(
              initialEncrypt: BackupService.archiveEncrypt,
              initialPassword: BackupService.archivePassword,
              onDirtyChanged: (value) {
                if (_dirty == value || !mounted) return;
                setState(() => _dirty = value);
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
