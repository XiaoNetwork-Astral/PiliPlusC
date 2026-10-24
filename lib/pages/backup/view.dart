import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/view_insets_safe_area.dart';
import 'package:PiliPlus/pages/backup/archive_setting.dart';
import 'package:PiliPlus/pages/backup/widgets/app_dialog.dart';
import 'package:PiliPlus/pages/backup/widgets/backup_dialogs.dart';
import 'package:PiliPlus/pages/webdav/view.dart';
import 'package:PiliPlus/utils/backup/backup.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

enum _BackupAction { export, import }

class BackupPage extends StatefulWidget {
  const BackupPage({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  BackupMethod _method = BackupService.lastMethod;
  final Set<BackupItem> _selected = {...BackupItem.defaultSelected};

  @override
  void initState() {
    super.initState();
    if (!_method.supportsCustomFont) {
      _selected.remove(BackupItem.customFont);
    }
  }

  IconData _iconOf(BackupMethod method) {
    switch (method) {
      case BackupMethod.webdav:
        return Icons.cloud_outlined;
      case BackupMethod.archive:
        return Icons.archive_outlined;
      case BackupMethod.clipboard:
        return Icons.content_paste_outlined;
    }
  }

  Future<void> _showMethodDialog() async {
    final method = await showAppSelectionDialog<BackupMethod>(
      context: context,
      title: '备份方式',
      options: BackupMethod.values,
      labelOf: (value) => value.label,
      current: _method,
    );
    if (method == null || !mounted) return;
    setState(() {
      _method = method;
      if (!method.supportsCustomFont) {
        _selected.remove(BackupItem.customFont);
      }
    });
    BackupService.lastMethod = method;
  }

  Future<void> _openConfig() async {
    switch (_method) {
      case BackupMethod.webdav:
        await Get.to(() => const WebDavSettingPage());
      case BackupMethod.archive:
        await Get.to(() => const ArchiveSettingPage());
      case BackupMethod.clipboard:
        break;
    }
  }

  void _toggleItem(BackupItem item) {
    if (!item.isSupportedBy(_method)) return;
    setState(() {
      if (!_selected.remove(item)) {
        _selected.add(item);
      }
    });
  }

  Future<void> _openActionDialog() async {
    final count = _selected.length;
    final action = await showAppSelectionDialog<_BackupAction>(
      context: context,
      title: '备份操作',
      options: _BackupAction.values,
      labelOf: (value) =>
          value == _BackupAction.export ? '导出 $count 项' : '导入 $count 项',
    );
    if (action == null || !mounted) return;
    switch (action) {
      case _BackupAction.export:
        await _export();
      case _BackupAction.import:
        await _import();
    }
  }

  Future<void> _export() async {
    if (_selected.isEmpty) {
      SmartDialog.showToast('请至少勾选一项');
      return;
    }
    if (_method == BackupMethod.webdav && !BackupService.isWebDavConfigured) {
      SmartDialog.showToast('请先配置 WebDAV');
      return;
    }
    if (BackupService.needsAccountWarning(_method, _selected)) {
      final isClipboard = _method == BackupMethod.clipboard;
      final result = await showExportWarningDialog(
        context,
        title: isClipboard ? '登录信息不会被加密' : '登录信息未加密',
        summary: isClipboard
            ? '检测到尝试在备份方式为剪贴板的情况下导出登录信息，这是非常危险的行为，可能会导致盗号乃至财产损失！'
            : '检测到尝试在未加密压缩包的情况下导出登录信息，这是非常危险的行为，可能会导致盗号乃至财产损失！',
        points: isClipboard
            ? const [
                '建议不要通过剪贴板的形式导出登录信息',
                '切忌将登录信息分享给其他人',
              ]
            : const [
                '建议先开启压缩包加密后再尝试导出登录信息',
                '一定要慎重保存备份文件，不要将备份文件分享给其他人',
              ],
        countdown: isClipboard ? 10 : 5,
        showOpenEncryption: !isClipboard,
      );
      if (!mounted) return;
      if (result == ExportWarningResult.openEncryption) {
        await _openConfig();
        return;
      }
      if (result != ExportWarningResult.confirm) return;
    }

    SmartDialog.showLoading();
    String message;
    try {
      await BackupService.export(_method, _selected);
      message = switch (_method) {
        BackupMethod.webdav => '上传成功',
        BackupMethod.archive => '导出成功',
        BackupMethod.clipboard => '已复制到剪贴板',
      };
    } on BackupCancelledException {
      message = '已取消';
    } on BackupException catch (e) {
      message = e.toString();
    } catch (e) {
      message = '导出失败：$e';
    }
    SmartDialog.dismiss();
    if (mounted) {
      SmartDialog.showToast(message);
    }
  }

  Future<void> _import() async {
    if (_selected.isEmpty) {
      SmartDialog.showToast('请至少勾选一项');
      return;
    }
    if (_method == BackupMethod.webdav && !BackupService.isWebDavConfigured) {
      SmartDialog.showToast('请先配置 WebDAV');
      return;
    }

    if (_method == BackupMethod.webdav) {
      SmartDialog.showLoading();
      var hasBackup = false;
      try {
        hasBackup = await BackupService.hasWebDavBackup();
      } on BackupException catch (e) {
        SmartDialog.dismiss();
        SmartDialog.showToast(e.toString());
        return;
      } catch (e) {
        SmartDialog.dismiss();
        SmartDialog.showToast('连接失败：$e');
        return;
      }
      SmartDialog.dismiss();
      if (!hasBackup) {
        SmartDialog.showToast('WebDAV 上没有备份文件');
        return;
      }
    } else if (_method == BackupMethod.clipboard) {
      var hasData = false;
      try {
        hasData = await BackupService.hasClipboardData();
      } catch (e) {
        SmartDialog.showToast('剪贴板无数据');
        return;
      }
      if (!hasData) {
        SmartDialog.showToast('剪贴板无数据');
        return;
      }
    }

    BackupSource? source;
    var loading = false;
    try {
      if (_method != BackupMethod.archive) {
        SmartDialog.showLoading();
        loading = true;
      }
      source = await BackupService.openSource(_method);
    } on BackupCancelledException {
      if (loading) SmartDialog.dismiss();
      SmartDialog.showToast('已取消');
      return;
    } on BackupException catch (e) {
      if (loading) SmartDialog.dismiss();
      SmartDialog.showToast(e.toString());
      return;
    } catch (e) {
      if (loading) SmartDialog.dismiss();
      SmartDialog.showToast('导入失败：$e');
      return;
    }
    if (loading) {
      SmartDialog.dismiss();
    }
    final backupSource = source;
    if (backupSource == null) return;

    BackupPreview? preview;
    String password = BackupService.savedPasswordOf(_method);
    var wrongPassword = false;
    var needPassword = false;
    try {
      preview = await BackupService.inspect(
        _method,
        source: backupSource,
        password: password.isEmpty ? null : password,
      );
    } on BackupPasswordRequiredException {
      needPassword = true;
    } on BackupPasswordWrongException {
      needPassword = true;
      wrongPassword = true;
    } on BackupException catch (e) {
      SmartDialog.showToast(e.toString());
      return;
    } catch (e) {
      SmartDialog.showToast('解析失败：$e');
      return;
    }

    String? enteredPassword;
    while (preview == null && needPassword) {
      if (!mounted) return;
      final input = await showArchivePasswordDialog(
        context,
        wrongPassword: wrongPassword,
        validate: (value) async {
          try {
            preview = await BackupService.inspect(
              _method,
              source: backupSource,
              password: value.isEmpty ? null : value,
            );
            return null;
          } on BackupPasswordWrongException {
            return '密码错误';
          } on BackupPasswordRequiredException {
            return '密码错误';
          } on BackupException catch (e) {
            return e.toString();
          } catch (e) {
            return '解析失败：$e';
          }
        },
      );
      if (input == null) {
        if (mounted) {
          SmartDialog.showToast('已取消');
        }
        return;
      }
      if (!mounted) return;
      enteredPassword = input;
      if (preview == null) {
        needPassword = false;
      }
    }

    final ready = preview;
    if (ready == null) return;
    if (enteredPassword != null && enteredPassword.isNotEmpty) {
      switch (_method) {
        case BackupMethod.archive:
          BackupService.archivePassword = enteredPassword;
        case BackupMethod.webdav:
          BackupService.webdavArchivePassword = enteredPassword;
        case BackupMethod.clipboard:
          break;
      }
    }

    if (!mounted) return;
    if (!await showConfirmImportDialog(context) || !mounted) return;

    String message;
    try {
      final note = await BackupService.import(
        _method,
        _selected,
        preview: ready,
        onWarning: (warning) {
          if (!mounted) return Future.value(false);
          return showImportWarningDialog(context, warning);
        },
      );
      message = note == null ? '导入成功' : '导入失败：$note';
    } on BackupCancelledException {
      message = '已取消';
    } on BackupException catch (e) {
      message = e.toString();
    } catch (e) {
      message = '导入失败：$e';
    }
    if (!mounted) return;
    setState(() {});
    SmartDialog.showToast(message);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showAppBar = widget.showAppBar;
    final padding = MediaQuery.viewPaddingOf(context);
    final double leftInset = 16 + (showAppBar ? padding.left : 0.0);
    final double rightInset = 16 + (showAppBar ? padding.right : 0.0);
    return SimpleScaffold(
      appBar: showAppBar ? AppBar(title: const Text('备份与恢复')) : null,
      body: ViewInsetsSafeArea(
        child: ListView(
          padding: EdgeInsets.only(top: 16, bottom: padding.bottom + 100),
          children: [
            Padding(
              padding: EdgeInsets.only(left: leftInset, right: rightInset),
              child: _buildMethodCard(theme),
            ),
            const SizedBox(height: 16),
            for (final item in BackupItem.values)
              _buildItem(theme, item, leftInset, rightInset),
          ],
        ),
      ),
      fab: Padding(
        padding: EdgeInsets.only(
          right: kFloatingActionButtonMargin + (showAppBar ? padding.right : 0),
          bottom: kFloatingActionButtonMargin + padding.bottom,
        ),
        child: FloatingActionButton(
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
          backgroundColor: theme.colorScheme.primary,
          foregroundColor: theme.colorScheme.onPrimary,
          onPressed: _openActionDialog,
          child: const Icon(Icons.swap_horiz),
        ),
      ),
    );
  }

  Widget _buildMethodCard(ThemeData theme) {
    final configurable = _method.configurable;
    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _showMethodDialog,
        child: SizedBox(
          height: 52,
          child: Row(
            children: [
              const SizedBox(width: 16),
              Icon(_iconOf(_method), size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _method.label,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              if (configurable)
                InkWell(
                  onTap: _openConfig,
                  child: const SizedBox(
                    width: 48,
                    height: 52,
                    child: Icon(Icons.chevron_right),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildItem(
    ThemeData theme,
    BackupItem item,
    double leftInset,
    double rightInset,
  ) {
    final supported = item.isSupportedBy(_method);
    final checked = _selected.contains(item);
    final disabledColor = theme.colorScheme.outline.withValues(alpha: 0.5);
    final labelColor = supported
        ? theme.colorScheme.onSurface
        : disabledColor;
    final descriptionColor = supported
        ? (item.sensitive ? theme.colorScheme.error : theme.colorScheme.outline)
        : disabledColor;
    return InkWell(
      onTap: supported ? () => _toggleItem(item) : null,
      child: Padding(
        padding: EdgeInsets.only(
          top: 8,
          bottom: 8,
          left: leftInset,
          right: rightInset,
        ),
        child: Row(
          children: [
            Checkbox(
              value: checked,
              onChanged: supported ? (_) => _toggleItem(item) : null,
              shape: const CircleBorder(),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.label,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: labelColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: descriptionColor,
                    ),
                  ),
                  if (!supported)
                    Text(
                      BackupItem.unsupportedTip,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: disabledColor,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              BackupService.sizeText(item),
              style: theme.textTheme.bodySmall?.copyWith(
                color: supported ? theme.colorScheme.outline : disabledColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
