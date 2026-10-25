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
  });

  final String title;
  final IconData? icon;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// 为 false 时整行置灰且不响应点击
  final bool enabled;

  /// 副标题最多显示的行数，超出以省略号截断
  final int? subtitleMaxLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      onTap: enabled ? onTap : null,
      enabled: enabled,
      leading: icon == null ? null : Icon(icon),
      title: Text(
        title,
        style: theme.textTheme.titleMedium!.copyWith(
          color: enabled ? null : theme.colorScheme.outline,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              maxLines: subtitleMaxLines,
              overflow: subtitleMaxLines == null ? null : TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium!.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
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
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  final IconData? icon;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return CfTile(
      icon: icon,
      title: title,
      subtitle: subtitle,
      onTap: () => onChanged(!value),
      trailing: Transform.scale(
        scale: 0.8,
        alignment: Alignment.centerRight,
        child: Switch(value: value, onChanged: onChanged),
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
