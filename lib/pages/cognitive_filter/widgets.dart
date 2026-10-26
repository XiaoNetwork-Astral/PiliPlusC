import 'package:PiliPlus/common/widgets/flutter/list_tile.dart';
import 'package:material_ui/material_ui.dart' hide ListTile;

/// 认知滤网页面里的列表行，字号与颜色沿用设置页
class CfTile extends StatelessWidget {
  const CfTile({
    super.key,
    required this.title,
    this.icon,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.enabled = true,
    this.subtitleMaxLines,
    this.titleMaxLines,
    this.subtitleWidget,
    this.contentPadding,
  });

  final String title;
  final IconData? icon;
  final String? subtitle;
  final Widget? trailing;

  /// 行内边距，为空时用 ListTile 默认值（右侧 24）
  final EdgeInsetsGeometry? contentPadding;
  final VoidCallback? onTap;

  /// 为 false 时整行置灰且不响应点击
  final bool enabled;

  /// 副标题最多显示的行数，超出以省略号截断
  final int? subtitleMaxLines;

  /// 标题最多显示的行数，超出以省略号截断
  final int? titleMaxLines;

  /// 自定义副标题，设置后忽略 [subtitle]
  final Widget? subtitleWidget;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: contentPadding,
      onTap: enabled ? onTap : null,
      enabled: enabled,
      leading: icon == null ? null : Icon(icon),
      title: Text(
        title,
        maxLines: titleMaxLines,
        overflow: titleMaxLines == null ? null : TextOverflow.ellipsis,
        style: theme.textTheme.titleMedium!.copyWith(
          color: enabled ? null : theme.colorScheme.outline,
        ),
      ),
      subtitle:
          subtitleWidget ??
          (subtitle == null
              ? null
              : Text(
                  subtitle!,
                  maxLines: subtitleMaxLines,
                  overflow: subtitleMaxLines == null
                      ? null
                      : TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium!.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                )),
      trailing: trailing,
    );
  }
}

/// 带开关的列表行
class CfSwitchTile extends StatelessWidget {
  const CfSwitchTile({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.icon,
    this.subtitle,
    this.enabled = true,
    this.onDisabledTap,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  final IconData? icon;
  final String? subtitle;

  /// 为 false 时开关置灰且不能切换，点击行只触发 [onDisabledTap]
  final bool enabled;
  final VoidCallback? onDisabledTap;

  @override
  Widget build(BuildContext context) {
    return CfTile(
      icon: icon,
      title: title,
      subtitle: subtitle,
      onTap: enabled ? () => onChanged(!value) : onDisabledTap,
      trailing: Transform.scale(
        scale: 0.8,
        alignment: Alignment.centerRight,
        child: Switch(value: value, onChanged: enabled ? onChanged : null),
      ),
    );
  }
}

/// 列表里的灰色说明文字
class CfHint extends StatelessWidget {
  const CfHint(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        text,
        style: theme.textTheme.labelMedium!.copyWith(
          color: theme.colorScheme.outline,
        ),
      ),
    );
  }
}

/// 列表里一组设置的小标题
class CfGroupHeader extends StatelessWidget {
  const CfGroupHeader(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        text,
        style: theme.textTheme.labelLarge!.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

/// 靠右的椭圆形「测试连接」按钮，测试中显示转圈并不可点
class CfTestButton extends StatelessWidget {
  const CfTestButton({
    super.key,
    required this.testing,
    required this.onPressed,
  });

  final bool testing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Align(
        alignment: Alignment.centerRight,
        child: FilledButton.tonal(
          onPressed: testing ? null : onPressed,
          child: testing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('测试连接'),
        ),
      ),
    );
  }
}

/// 小标签，用来标出来源、适用面、类别、分数这类短信息
class CfBadge extends StatelessWidget {
  const CfBadge(this.text, {super.key, this.tone = CfBadgeTone.neutral});

  final String text;
  final CfBadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground) = switch (tone) {
      .primary => (scheme.primaryContainer, scheme.onPrimaryContainer),
      .secondary => (scheme.secondaryContainer, scheme.onSecondaryContainer),
      .neutral => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Text(
          text,
          style: TextStyle(fontSize: 12, height: 1.3, color: foreground),
        ),
      ),
    );
  }
}

enum CfBadgeTone { primary, secondary, neutral }
