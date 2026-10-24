import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// 弹窗按钮的配色，带颜色的按钮一律实心
enum AppDialogButtonStyle {
  primary,
  danger,
  neutral,
}

class AppDialogAction {
  const AppDialogAction({
    required this.label,
    required this.onPressed,
    this.style = AppDialogButtonStyle.primary,
    this.sizingLabel,
  });

  /// 按钮文字，倒计时按钮需要在重建时读取最新值
  final String Function() label;

  /// 用于固定按钮宽度的最长文字，倒计时按钮用它避免宽度随数字变化
  final String? sizingLabel;

  final VoidCallback? onPressed;

  final AppDialogButtonStyle style;
}

/// 居中圆角小弹窗
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.title,
    this.content,
    this.actions = const [],
  });

  final String title;
  final Widget? content;
  final List<AppDialogAction> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(28)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SizedBox(
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: theme.textTheme.titleLarge),
                if (content != null) ...[
                  const SizedBox(height: 16),
                  Flexible(
                    child: SingleChildScrollView(child: content),
                  ),
                ],
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  AppDialogActions(actions: actions),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 按钮能放下就横排，放不下就每个按钮独占一行
class AppDialogActions extends StatelessWidget {
  const AppDialogActions({
    super.key,
    required this.actions,
  });

  final List<AppDialogAction> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textStyle = theme.textTheme.labelLarge ?? const TextStyle();
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    var neededWidth = 0.0;
    for (final action in actions) {
      neededWidth += _buttonWidth(action, textStyle, textScale);
    }
    neededWidth += (actions.length - 1) * 8;
    return LayoutBuilder(
      builder: (context, constraints) {
        final buttons = [
          for (final action in actions) _buildButton(context, action),
        ];
        if (neededWidth <= constraints.maxWidth) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              for (var i = 0; i < buttons.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                buttons[i],
              ],
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < buttons.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              SizedBox(width: double.infinity, child: buttons[i]),
            ],
          ],
        );
      },
    );
  }

  static const _tabularFigures = [FontFeature.tabularFigures()];

  /// 按钮宽度，文字宽度加左右各 24 的内边距，带 [AppDialogAction.sizingLabel] 时按它算
  double _buttonWidth(
    AppDialogAction action,
    TextStyle textStyle,
    double textScale,
  ) {
    final text = action.sizingLabel ?? action.label();
    return _measure(text, textStyle) * textScale + 48;
  }

  Widget _buildButton(BuildContext context, AppDialogAction action) {
    final theme = Theme.of(context);
    final child = Text(
      action.label(),
      style: action.sizingLabel == null
          ? null
          : const TextStyle(fontFeatures: _tabularFigures),
    );
    final Widget button;
    switch (action.style) {
      case AppDialogButtonStyle.neutral:
        button = TextButton(
          onPressed: action.onPressed,
          style: TextButton.styleFrom(
            foregroundColor: theme.colorScheme.outline,
          ),
          child: child,
        );
      case AppDialogButtonStyle.danger:
        button = FilledButton(
          onPressed: action.onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
            disabledBackgroundColor: theme.colorScheme.onSurface.withValues(
              alpha: 0.12,
            ),
            disabledForegroundColor: theme.colorScheme.onSurface.withValues(
              alpha: 0.38,
            ),
          ),
          child: child,
        );
      case AppDialogButtonStyle.primary:
        button = FilledButton(
          onPressed: action.onPressed,
          child: child,
        );
    }
    if (action.sizingLabel == null) return button;
    final textStyle = theme.textTheme.labelLarge ?? const TextStyle();
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: _buttonWidth(action, textStyle, textScale),
      ),
      child: button,
    );
  }

  double _measure(String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    return painter.width;
  }
}

Future<T?> showAppDialog<T>({
  required BuildContext context,
  required String title,
  Widget? content,
  List<AppDialogAction> actions = const [],
  bool barrierDismissible = true,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (context) => AppDialog(
      title: title,
      content: content,
      actions: actions,
    ),
  );
}

/// 选择类弹窗，点选项即选中并关闭，当前项带对勾
Future<T?> showAppSelectionDialog<T>({
  required BuildContext context,
  required String title,
  required List<T> options,
  required String Function(T value) labelOf,
  T? current,
}) {
  return showAppDialog<T>(
    context: context,
    title: title,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final option in options)
          InkWell(
            borderRadius: const BorderRadius.all(Radius.circular(12)),
            onTap: () => Get.back(result: option),
            child: SizedBox(
              height: 52,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        labelOf(option),
                        strutStyle: const StrutStyle(
                          height: 1.4,
                          forceStrutHeight: true,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 24,
                      child: option == current
                          ? const Icon(Icons.check)
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
