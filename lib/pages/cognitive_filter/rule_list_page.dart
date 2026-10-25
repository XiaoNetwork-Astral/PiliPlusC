import 'package:PiliPlus/common/widgets/flutter/list_tile.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/view_safe_area.dart';
import 'package:PiliPlus/models/cognitive_filter/filter_rule.dart';
import 'package:PiliPlus/models/cognitive_filter/rule_scope.dart';
import 'package:PiliPlus/models/cognitive_filter/rule_type.dart';
import 'package:PiliPlus/pages/cognitive_filter/rule_edit_page.dart';
import 'package:PiliPlus/utils/cognitive_filter/rule_store.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart' hide ListTile;

const List<RuleScope> _scopeOrder = [
  RuleScope.danmaku,
  RuleScope.reply,
  RuleScope.dynamic,
  RuleScope.video,
  RuleScope.live,
  RuleScope.whisper,
];

/// 统一规则列表
///
/// 一行一条规则，右侧开关控制启用，点击左侧进入编辑页
class RuleListPage extends StatefulWidget {
  const RuleListPage({super.key, this.initialType});

  /// 进入时默认筛选的类型，为空表示全部
  final RuleType? initialType;

  @override
  State<RuleListPage> createState() => _RuleListPageState();
}

class _RuleListPageState extends State<RuleListPage> {
  late RuleType? _filter = widget.initialType;

  void _openEdit([FilterRule? rule]) {
    Get.to(() => RuleEditPage(rule: rule));
  }

  List<FilterRule> _filtered(List<FilterRule> rules) {
    final filter = _filter;
    if (filter == null) return rules;
    return [
      for (final rule in rules)
        if (rule.type == filter) rule,
    ];
  }

  String _titleOf(FilterRule rule) {
    if (!rule.isHashOnly) return rule.content;
    final hash = rule.midHash ?? '';
    return '弹幕用户 ${hash.length > 8 ? hash.substring(0, 8) : hash}';
  }

  String _scopesOf(FilterRule rule) {
    final labels = <String>[];
    for (final scope in _scopeOrder) {
      if (rule.scopes.contains(scope)) labels.add(scope.label);
    }
    return labels.join('、');
  }

  bool _hasBadRegex(FilterRule rule) {
    if (rule.type != RuleType.regex && rule.type != RuleType.zone) {
      return false;
    }
    try {
      RegExp(rule.content, caseSensitive: false);
      return false;
    } on FormatException {
      return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final padding = MediaQuery.viewPaddingOf(context);
    return SimpleScaffold(
      appBar: AppBar(title: const Text('规则')),
      body: ViewSafeArea(
        child: ValueListenableBuilder<int>(
          valueListenable: RuleStore.instance.version,
          builder: (context, _, _) {
            final rules = _filtered(RuleStore.instance.rules);
            return Column(
              children: [
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      for (final filter in <RuleType?>[
                        null,
                        ...RuleType.values,
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _filterChip(
                            theme,
                            filter?.label ?? '全部',
                            _filter == filter,
                            () => setState(() => _filter = filter),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: rules.isEmpty
                      ? Center(
                          child: Text(
                            '还没有规则',
                            style: TextStyle(color: theme.colorScheme.outline),
                          ),
                        )
                      : ListView.builder(
                          padding: EdgeInsets.only(
                            top: 4,
                            bottom: padding.bottom + 100,
                          ),
                          itemCount: rules.length,
                          itemBuilder: (context, index) {
                            return _ruleTile(theme, rules[index]);
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
      fab: Padding(
        padding: EdgeInsets.only(
          right: kFloatingActionButtonMargin + padding.right,
          bottom: kFloatingActionButtonMargin + padding.bottom,
        ),
        child: FloatingActionButton(
          tooltip: '添加',
          onPressed: _openEdit,
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  Widget _filterChip(
    ThemeData theme,
    String label,
    bool selected,
    VoidCallback onTap,
  ) {
    final foreground = selected
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurfaceVariant;
    return Material(
      color: selected
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: foreground,
              fontWeight: selected ? FontWeight.w600 : null,
            ),
          ),
        ),
      ),
    );
  }

  Widget _ruleTile(ThemeData theme, FilterRule rule) {
    final baseStyle = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.outline,
    );
    return ListTile(
      title: Text(
        _titleOf(rule),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleMedium?.copyWith(
          color: rule.enabled ? null : theme.colorScheme.outline,
        ),
      ),
      subtitle: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '${rule.type.label}，${_scopesOf(rule)}'),
            if (_hasBadRegex(rule))
              TextSpan(
                text: ' 正则无法编译',
                style: TextStyle(color: theme.colorScheme.error),
              ),
          ],
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: baseStyle,
      ),
      trailing: Transform.scale(
        scale: 0.8,
        alignment: Alignment.centerRight,
        child: Switch(
          value: rule.enabled,
          onChanged: (value) => RuleStore.instance.setEnabled(rule.id, value),
        ),
      ),
      onTap: () => _openEdit(rule),
    );
  }
}
