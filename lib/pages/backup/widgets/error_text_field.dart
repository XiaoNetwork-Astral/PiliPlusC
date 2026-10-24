import 'package:PiliPlus/pages/backup/widgets/smooth_visibility.dart';
import 'package:material_ui/material_ui.dart';

/// 带自绘错误提示的输入框，出错时边框与标签变红，红字紧贴输入框左缘
class ErrorTextField extends StatefulWidget {
  const ErrorTextField({
    super.key,
    required this.controller,
    required this.label,
    this.errorText,
    this.onChanged,
    this.obscureText = false,
    this.keyboardType,
    this.autofillHints,
    this.suffixIcon,
  });

  final TextEditingController controller;
  final String label;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final bool obscureText;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final Widget? suffixIcon;

  @override
  State<ErrorTextField> createState() => _ErrorTextFieldState();
}

class _ErrorTextFieldState extends State<ErrorTextField> {
  /// 收起动画期间继续显示上一条错误，避免文字提前消失
  String _lastError = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = widget.errorText;
    final hasError = error != null;
    if (error != null) _lastError = error;
    final errorColor = theme.colorScheme.error;
    final errorStyle = TextStyle(color: errorColor);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: widget.controller,
          obscureText: widget.obscureText,
          keyboardType: widget.keyboardType,
          autofillHints: widget.autofillHints,
          onChanged: widget.onChanged,
          decoration: InputDecoration(
            labelText: widget.label,
            suffixIcon: widget.suffixIcon,
            border: const OutlineInputBorder(),
            enabledBorder: hasError
                ? OutlineInputBorder(borderSide: BorderSide(color: errorColor))
                : null,
            focusedBorder: hasError
                ? OutlineInputBorder(
                    borderSide: BorderSide(color: errorColor, width: 2),
                  )
                : null,
            labelStyle: hasError ? errorStyle : null,
            floatingLabelStyle: hasError ? errorStyle : null,
          ),
        ),
        SmoothVisibility(
          visible: hasError,
          duration: const Duration(milliseconds: 180),
          child: Padding(
            padding: const EdgeInsets.only(left: 4, top: 6),
            child: Text(
              _lastError,
              style: theme.textTheme.bodySmall?.copyWith(color: errorColor),
            ),
          ),
        ),
      ],
    );
  }
}
