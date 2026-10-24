import 'dart:async';

import 'package:PiliPlus/pages/backup/widgets/app_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

enum ExportWarningResult { cancel, confirm, openEncryption }

/// 导出登录信息的危险警告，仍然导出带倒计时
Future<ExportWarningResult> showExportWarningDialog(
  BuildContext context, {
  required String title,
  required String summary,
  required List<String> points,
  required int countdown,
  required bool showOpenEncryption,
}) async {
  final result = await showDialog<ExportWarningResult>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _ExportWarningDialog(
      title: title,
      summary: summary,
      points: points,
      countdown: countdown,
      showOpenEncryption: showOpenEncryption,
    ),
  );
  return result ?? ExportWarningResult.cancel;
}

class _ExportWarningDialog extends StatefulWidget {
  const _ExportWarningDialog({
    super.key,
    required this.title,
    required this.summary,
    required this.points,
    required this.countdown,
    required this.showOpenEncryption,
  });

  final String title;
  final String summary;
  final List<String> points;
  final int countdown;
  final bool showOpenEncryption;

  @override
  State<_ExportWarningDialog> createState() => _ExportWarningDialogState();
}

class _ExportWarningDialogState extends State<_ExportWarningDialog> {
  int _seconds = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _seconds = widget.countdown;
    if (_seconds > 0) {
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) return;
        setState(() {
          _seconds--;
          if (_seconds <= 0) {
            _seconds = 0;
            timer.cancel();
          }
        });
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppDialog(
      title: widget.title,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.summary),
          const SizedBox(height: 12),
          for (var i = 0; i < widget.points.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.outline,
                      shape: BoxShape.circle,
                    ),
                    child: const SizedBox(width: 6, height: 6),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(widget.points[i])),
              ],
            ),
          ],
        ],
      ),
      actions: [
        AppDialogAction(
          label: () => '取消',
          style: AppDialogButtonStyle.neutral,
          onPressed: () => Get.back(result: ExportWarningResult.cancel),
        ),
        if (widget.showOpenEncryption)
          AppDialogAction(
            label: () => '去开启加密',
            onPressed: () =>
                Get.back(result: ExportWarningResult.openEncryption),
          ),
        AppDialogAction(
          label: () => _seconds > 0 ? '仍然导出 ($_seconds)' : '仍然导出',
          sizingLabel: '仍然导出 (${widget.countdown})',
          style: AppDialogButtonStyle.danger,
          onPressed: _seconds > 0
              ? null
              : () => Get.back(result: ExportWarningResult.confirm),
        ),
      ],
    );
  }
}

/// 确认导入
Future<bool> showConfirmImportDialog(BuildContext context) async {
  final result = await showAppDialog<bool>(
    context: context,
    title: '确认导入',
    content: const Text('将使用备份覆盖当前数据，此操作无法撤销！'),
    actions: [
      AppDialogAction(
        label: () => '取消',
        style: AppDialogButtonStyle.neutral,
        onPressed: () => Get.back(result: false),
      ),
      AppDialogAction(
        label: () => '继续',
        style: AppDialogButtonStyle.danger,
        onPressed: () => Get.back(result: true),
      ),
    ],
  );
  return result ?? false;
}

/// 加密包密码弹窗，[validate] 返回错误文案时留在弹窗内并在输入框下显示
Future<String?> showArchivePasswordDialog(
  BuildContext context, {
  required Future<String?> Function(String password) validate,
  bool wrongPassword = false,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _ArchivePasswordDialog(
      validate: validate,
      wrongPassword: wrongPassword,
    ),
  );
}

class _ArchivePasswordDialog extends StatefulWidget {
  const _ArchivePasswordDialog({
    super.key,
    required this.validate,
    required this.wrongPassword,
  });

  final Future<String?> Function(String password) validate;
  final bool wrongPassword;

  @override
  State<_ArchivePasswordDialog> createState() => _ArchivePasswordDialogState();
}

class _ArchivePasswordDialogState extends State<_ArchivePasswordDialog> {
  final _controller = TextEditingController();
  String? _error;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    if (widget.wrongPassword) {
      _error = '密码错误';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final error = await widget.validate(_controller.text);
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _submitting = false;
        _error = error;
      });
      return;
    }
    Get.back(result: _controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: '请输入压缩包密码',
      content: TextField(
        controller: _controller,
        autofocus: true,
        enabled: !_submitting,
        obscureText: true,
        onChanged: (_) {
          if (_error != null) {
            setState(() => _error = null);
          }
        },
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          errorText: _error,
          errorMaxLines: 3,
        ),
      ),
      actions: [
        AppDialogAction(
          label: () => '取消',
          style: AppDialogButtonStyle.neutral,
          onPressed: _submitting ? null : () => Get.back(),
        ),
        AppDialogAction(
          label: () => '确定',
          onPressed: _submitting ? null : _submit,
        ),
      ],
    );
  }
}

/// 有未保存的修改时返回，返回 true 表示放弃修改
Future<bool> showUnsavedChangesDialog(BuildContext context) async {
  final result = await showAppDialog<bool>(
    context: context,
    title: '有未保存的修改',
    content: const Text('现在返回将导致未保存的修改丢失！'),
    actions: [
      AppDialogAction(
        label: () => '继续编辑',
        onPressed: () => Get.back(result: false),
      ),
      AppDialogAction(
        label: () => '放弃修改',
        style: AppDialogButtonStyle.danger,
        onPressed: () => Get.back(result: true),
      ),
    ],
  );
  return result ?? false;
}

/// 导入压缩包时的版本或来源提醒，返回 true 表示继续导入
Future<bool> showImportWarningDialog(
  BuildContext context,
  String warning,
) async {
  final result = await showAppDialog<bool>(
    context: context,
    title: '注意',
    content: Text(warning),
    actions: [
      AppDialogAction(
        label: () => '取消',
        style: AppDialogButtonStyle.neutral,
        onPressed: () => Get.back(result: false),
      ),
      AppDialogAction(
        label: () => '继续',
        onPressed: () => Get.back(result: true),
      ),
    ],
  );
  return result ?? false;
}
