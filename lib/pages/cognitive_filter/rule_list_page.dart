import 'package:PiliPlus/common/widgets/dialog/dialog.dart';
import 'package:PiliPlus/common/widgets/flutter/list_tile.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/view_safe_area.dart';
import 'package:PiliPlus/models/cognitive_filter/filter_rule.dart';
import 'package:PiliPlus/models/cognitive_filter/rule_scope.dart';
import 'package:PiliPlus/models/cognitive_filter/rule_type.dart';
import 'package:PiliPlus/pages/cognitive_filter/rule_edit_page.dart';
import 'package:PiliPlus/utils/cognitive_filter/rule_source.dart';
import 'package:PiliPlus/utils/cognitive_filter/rule_store.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart' hide ListTile;

/// 规则列表
///
/// 一行一条规则，右侧是开关和删除，点击左侧进入编辑页；默认展示屏蔽规则，
/// 传入 [source] 后也可以展示 AI 白名单。
class RuleListPage extends StatefulWidget {
  const RuleListPage({
    super.key,
    this.initialType,
    this.source,
    this.title = '屏蔽规则',
    this.allowedScopes,
  });

  /// 进入时默认筛选的类型，为空表示全部
  final RuleType? initialType;

  /// 数据源，为空时使用屏蔽规则
  final RuleSource? source;

  /// 页面标题
  final String title;

  /// 可选的适用范围，为空表示不限
  final Set<RuleScope>? allowedScopes;

  @override
  State<RuleListPage> createState() => _RuleListPageState();
}

class _RuleListPageState extends State<RuleListPage> {
  late RuleType? _filter = widget.initialType;
  String _query = '';
  bool _selecting = false;
  final Set<String> _selected = <String>{};

  RuleSource get _source => widget.source ?? RuleStore.instance;

  void _openEdit([FilterRule? rule]) {
    Get.to(
      () => RuleEditPage(
        rule: rule,
        source: _source,
        allowedScopes: widget.allowedScopes,
      ),
    );
  }

  List<FilterRule> _filtered(List<FilterRule> rules) {
    final filter = _filter;
    final query = _query.trim().toLowerCase();
    return [
      for (final rule in rules)
        if ((filter == null || rule.type == filter) &&
            (query.isEmpty || _matches(rule, query)))
          rule,
    ];
  }

  bool _matches(FilterRule rule, String query) {
    final text = rule.isHashOnly
        ? '${rule.midHash} b站 弹幕用户'
        : '${rule.content} ${rule.type.label} ${_scopesOf(rule)}';
    return text.toLowerCase().contains(query);
  }

  String _titleOf(FilterRule rule) {
    if (!rule.isHashOnly) return rule.content;
    final hash = rule.midHash ?? '';
    return 'B 站弹幕用户 ${hash.length > 8 ? hash.substring(0, 8) : hash}';
  }

  String _scopesOf(FilterRule rule) => [
    for (final scope in ruleScopeOrder)
      if (rule.scopes.contains(scope)) scope.label,
  ].join('、');

  bool _hasBadRegex(FilterRule rule) {
    if (rule.type != RuleType.regex) return false;
    try {
      RegExp(rule.content, caseSensitive: false);
      return false;
    } on FormatException {
      return true;
    }
  }

  void _enterSelecting([FilterRule? first]) {
    setState(() {
      _selecting = true;
      _selected
        ..clear()
        ..addAll([?first?.id]);
    });
  }

  void _exitSelecting() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  void _toggleSelected(FilterRule rule) {
    setState(() {
      if (!_selected.remove(rule.id)) _selected.add(rule.id);
    });
  }

  /// 已全选当前筛选结果时再点一次就取消全选
  void _toggleSelectAll(List<FilterRule> shown) {
    setState(() {
      final all = {for (final rule in shown) rule.id};
      if (all.isNotEmpty && _selected.containsAll(all)) {
        _selected.removeAll(all);
      } else {
        _selected.addAll(all);
      }
    });
  }

  Future<void> _deleteSelected() async {
    final ids = _selected.toList();
    if (ids.isEmpty) return;
    final confirmed = await showConfirmDialog(
      context: context,
      title: Text('确定删除选中的 ${ids.length} 条规则？'),
    );
    if (!confirmed || !mounted) return;
    for (final id in ids) {
      _source.remove(id);
    }
    _exitSelecting();
  }

  /// 一键重置：只动规则本身，回到出厂规则（没有任何用户规则）
  Future<void> _resetRules() async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: const Text('确定重置规则？'),
      content: const Text('将删除列表里的全部规则，回到出厂规则'),
    );
    if (!confirmed || !mounted) return;
    for (final rule in _source.rules.toList()) {
      _source.remove(rule.id);
    }
  }

  Future<void> _confirmDelete(FilterRule rule) async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: const Text('确定删除该规则？'),
    );
    if (confirmed) _source.remove(rule.id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final padding = MediaQuery.viewPaddingOf(context);
    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selecting) _exitSelecting();
      },
      child: ValueListenableBuilder<int>(
        valueListenable: _source.version,
        builder: (context, _, _) => _scaffold(theme, padding),
      ),
    );
  }

  Widget _scaffold(ThemeData theme, EdgeInsets padding) {
    final shown = _filtered(_source.rules);
    final selectedCount = _selected.length;
    return SimpleScaffold(
      appBar: AppBar(
        leading: _selecting
            ? IconButton(
                tooltip: '退出选择',
                icon: const Icon(Icons.close),
                onPressed: _exitSelecting,
              )
            : null,
        title: Text(_selecting ? '已选 $selectedCount 项' : widget.title),
        actions: [
          if (_selecting) ...[
            IconButton(
              tooltip: '全选',
              icon: const Icon(Icons.select_all),
              onPressed: () => _toggleSelectAll(shown),
            ),
            IconButton(
              tooltip: '删除',
              icon: Icon(
                Icons.delete_outline,
                color: selectedCount == 0 ? null : theme.colorScheme.error,
              ),
              onPressed: selectedCount == 0 ? null : _deleteSelected,
            ),
          ] else ...[
            if (shown.isNotEmpty)
              IconButton(
                tooltip: '批量选择',
                icon: const Icon(Icons.checklist),
                onPressed: _enterSelecting,
              ),
            PopupMenuButton<String>(
              onSelected: (_) => _resetRules(),
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'reset', child: Text('一键重置')),
              ],
            ),
          ],
        ],
      ),
      body: ViewSafeArea(
        child: Builder(
          builder: (context) {
            final rules = shown;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: TextField(
                    onChanged: (value) => setState(() => _query = value),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: '搜索规则',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                    ),
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Row(
                    spacing: 8,
                    children: [
                      for (final filter in <RuleType?>[
                        null,
                        ...RuleType.values,
                      ])
                        ChoiceChip(
                          label: Text(filter?.label ?? '全部'),
                          selected: _filter == filter,
                          showCheckmark: false,
                          onSelected: (_) => setState(() => _filter = filter),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: rules.isEmpty
                      ? Center(
                          child: Text(
                            '还没有规则',
                            style: TextStyle(color: theme.colorScheme.outline),
                          ),
                        )
                      : ListView.builder(
                          padding: EdgeInsets.only(bottom: padding.bottom + 100),
                          itemCount: rules.length,
                          itemBuilder: (context, index) =>
                              _ruleTile(theme, rules[index]),
                        ),
                ),
              ],
            );
          },
        ),
      ),
      fab: _selecting
          ? null
          : Padding(
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

  /// 右侧留 12：开关与删除按钮自带留白，视觉上与左侧 16 对齐
  static const EdgeInsetsDirectional _tilePadding = EdgeInsetsDirectional.only(
    start: 16,
    end: 12,
  );

  Widget _ruleTile(ThemeData theme, FilterRule rule) {
    final outline = theme.colorScheme.outline;
    if (_selecting) {
      final selected = _selected.contains(rule.id);
      return ListTile(
        contentPadding: _tilePadding,
        leading: Checkbox(
          value: selected,
          onChanged: (_) => _toggleSelected(rule),
        ),
        title: Text(
          _titleOf(rule),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            color: rule.enabled || rule.isHashOnly ? null : outline,
          ),
        ),
        subtitle: Text(
          rule.isHashOnly
              ? '无法修改'
              : '${rule.type.label}，${_scopesOf(rule)}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelMedium?.copyWith(color: outline),
        ),
        selected: selected,
        onTap: () => _toggleSelected(rule),
      );
    }
    final deleteButton = IconButton(
      tooltip: '删除',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
      onPressed: () => _confirmDelete(rule),
    );
    // B 站云端只给出发送者哈希，没有 UID，所以只能删除，不能启停或修改
    if (rule.isHashOnly) {
      return ListTile(
        contentPadding: _tilePadding,
        title: Text(
          _titleOf(rule),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium,
        ),
        subtitle: Text(
          '无法修改',
          style: theme.textTheme.labelMedium?.copyWith(color: outline),
        ),
        trailing: deleteButton,
        onLongPress: () => _enterSelecting(rule),
      );
    }
    return ListTile(
      contentPadding: _tilePadding,
      title: Text(
        _titleOf(rule),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleMedium?.copyWith(
          color: rule.enabled ? null : outline,
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
        style: theme.textTheme.labelMedium?.copyWith(color: outline),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          deleteButton,
          Transform.scale(
            scale: 0.8,
            alignment: Alignment.centerRight,
            child: Switch(
              value: rule.enabled,
              onChanged: (value) =>
                  _source.setEnabled(rule.id, value),
            ),
          ),
        ],
      ),
      onTap: () => _openEdit(rule),
      onLongPress: () => _enterSelecting(rule),
    );
  }
}
