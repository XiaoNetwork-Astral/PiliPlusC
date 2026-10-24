import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart';

/// 压缩包加密设置，WebDAV 设置页与压缩包设置页共用
class EncryptionSetting extends StatefulWidget {
  const EncryptionSetting({
    super.key,
    required this.initialEncrypt,
    required this.initialPassword,
    required this.onDirtyChanged,
    required this.onSave,
  });

  final bool initialEncrypt;
  final String initialPassword;
  final ValueChanged<bool> onDirtyChanged;
  final Future<void> Function(bool encrypt, String password) onSave;

  @override
  State<EncryptionSetting> createState() => _EncryptionSettingState();
}

class _EncryptionSettingState extends State<EncryptionSetting> {
  bool _encrypt = false;
  bool _savedEncrypt = false;
  String _savedPassword = '';
  final _passwordCtr = TextEditingController();
  final _confirmCtr = TextEditingController();
  String? _passwordError;
  String? _confirmError;
  bool _criteriaVisible = false;
  bool _criteriaError = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _encrypt = widget.initialEncrypt;
    _savedEncrypt = widget.initialEncrypt;
    _savedPassword = widget.initialEncrypt ? widget.initialPassword : '';
    _passwordCtr.text = _savedPassword;
    _confirmCtr.text = _savedPassword;
  }

  @override
  void dispose() {
    _passwordCtr.dispose();
    _confirmCtr.dispose();
    super.dispose();
  }

  bool get _hasLowerAndUpper =>
      RegExp('[a-z]').hasMatch(_passwordCtr.text) &&
      RegExp('[A-Z]').hasMatch(_passwordCtr.text);

  bool get _hasDigit => RegExp('[0-9]').hasMatch(_passwordCtr.text);

  bool get _hasSpecial => RegExp('[^A-Za-z0-9]').hasMatch(_passwordCtr.text);

  bool get _allCriteriaMet =>
      _passwordCtr.text.length >= 8 &&
      _hasLowerAndUpper &&
      _hasDigit &&
      _hasSpecial;

  void _syncDirty() {
    final dirty =
        _encrypt != _savedEncrypt ||
        _passwordCtr.text != _savedPassword ||
        _confirmCtr.text != _savedPassword;
    if (dirty == _dirty) return;
    _dirty = dirty;
    widget.onDirtyChanged(dirty);
  }

  void _onEncryptChanged(bool value) {
    setState(() {
      _encrypt = value;
      _passwordError = null;
      _confirmError = null;
      _criteriaVisible = false;
      _criteriaError = false;
      if (!value) {
        _passwordCtr.clear();
        _confirmCtr.clear();
      }
    });
    _syncDirty();
  }

  void _onPasswordChanged(String value) {
    setState(() {
      _passwordError = null;
      _criteriaVisible = value.isNotEmpty;
      _criteriaError = false;
    });
    _syncDirty();
  }

  void _onConfirmChanged(String _) {
    setState(() => _confirmError = null);
    _syncDirty();
  }

  Future<void> _save() async {
    if (!_encrypt) {
      await _persist(false, '');
      return;
    }

    final password = _passwordCtr.text;
    final confirm = _confirmCtr.text;
    String? passwordError;
    String? confirmError;
    if (password.isEmpty) {
      passwordError = '密码不能为空';
    } else if (!_allCriteriaMet) {
      passwordError = '密码不符合要求';
    }
    if (confirm.isEmpty) {
      confirmError = '确认密码不能为空';
    } else if (confirm != password) {
      confirmError = '两次输入的密码不一致';
    }
    setState(() {
      _passwordError = passwordError;
      _confirmError = confirmError;
      _criteriaVisible = password.isNotEmpty;
      _criteriaError = password.isNotEmpty && !_allCriteriaMet;
    });
    if (passwordError != null || confirmError != null) return;

    await _persist(true, password);
  }

  Future<void> _persist(bool encrypt, String password) async {
    await widget.onSave(encrypt, password);
    if (!mounted) return;
    setState(() {
      _savedEncrypt = encrypt;
      _savedPassword = encrypt ? password : '';
      _passwordError = null;
      _confirmError = null;
      _criteriaError = false;
    });
    _syncDirty();
    SmartDialog.showToast('已保存');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('加密压缩包', style: theme.textTheme.titleMedium),
            ),
            Switch(value: _encrypt, onChanged: _onEncryptChanged),
          ],
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          child: _encrypt
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passwordCtr,
                      obscureText: true,
                      onChanged: _onPasswordChanged,
                      decoration: InputDecoration(
                        labelText: '压缩包密码',
                        border: const OutlineInputBorder(),
                        errorText: _passwordError,
                      ),
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeInOut,
                      child: _criteriaVisible
                          ? Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: _buildCriteria(theme),
                            )
                          : const SizedBox(
                              width: double.infinity,
                              height: 0,
                            ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _confirmCtr,
                      obscureText: true,
                      onChanged: _onConfirmChanged,
                      decoration: InputDecoration(
                        labelText: '确认密码',
                        border: const OutlineInputBorder(),
                        errorText: _confirmError,
                      ),
                    ),
                  ],
                )
              : const SizedBox(width: double.infinity, height: 0),
        ),
        if (_encrypt || _savedEncrypt) ...[
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _dirty ? _save : null,
              child: const Text('保存'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCriteria(ThemeData theme) {
    final items = [
      ('至少 8 位', _passwordCtr.text.length >= 8),
      ('同时包含大小写字母', _hasLowerAndUpper),
      ('包含数字', _hasDigit),
      ('包含特殊字符', _hasSpecial),
    ];
    final errorColor = theme.colorScheme.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (label, met) in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                if (met)
                  Icon(
                    Icons.check,
                    size: 16,
                    color: theme.colorScheme.primary,
                  )
                else
                  const SizedBox(width: 16),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    color: met
                        ? theme.colorScheme.primary
                        : _criteriaError
                        ? errorColor
                        : null,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
