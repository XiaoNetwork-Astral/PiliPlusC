import 'package:PiliPlus/common/widgets/dialog/dialog.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/view_insets_safe_area.dart';
import 'package:PiliPlus/common/widgets/view_safe_area.dart';
import 'package:PiliPlus/models/cognitive_filter/filter_rule.dart';
import 'package:PiliPlus/models/cognitive_filter/rule_scope.dart';
import 'package:PiliPlus/models/cognitive_filter/rule_type.dart';
import 'package:PiliPlus/utils/cognitive_filter/rule_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

const List<RuleScope> _scopeOrder = [
  RuleScope.danmaku,
  RuleScope.reply,
  RuleScope.dynamic,
  RuleScope.video,
  RuleScope.live,
  RuleScope.whisper,
];

const Map<RuleType, String> _typeDescriptions = {
  RuleType.keyword: '按关键词匹配内容，不区分大小写',
  RuleType.regex: '按正则表达式匹配内容',
  RuleType.zone: '按视频分区名匹配，支持正则',
  RuleType.user: '按 UID 屏蔽用户的内容',
};

const Map<RuleScope, String> _scopeDescriptions = {
  RuleScope.danmaku: '包含直播间弹幕屏蔽词',
  RuleScope.reply: '评论内容',
  RuleScope.dynamic: '动态正文',
  RuleScope.video: '标题与分区',
  RuleScope.live: '直播间标题与主播',
  RuleScope.whisper: 'B 站私信屏蔽词，仅关键词',
};

/// 规则编辑页
///
/// 传入 null 表示新建规则，此时可以改类型；编辑已有规则时类型只读
class RuleEditPage extends StatefulWidget {
  const RuleEditPage({super.key, this.rule});

  final FilterRule? rule;

  @override
  State<RuleEditPage> createState() => _RuleEditPageState();
}

class _RuleEditPageState extends State<RuleEditPage> {
  late RuleType _type;
  late final TextEditingController _contentController;
  late Set<RuleScope> _scopes;
  late final bool _isHashOnly;
  late bool _enabled;

  bool get _isNew => widget.rule == null;

  @override
  void initState() {
    super.initState();
    final rule = widget.rule;
    _type = rule?.type ?? RuleType.keyword;
    _isHashOnly = rule?.isHashOnly ?? false;
    _enabled = rule?.enabled ?? true;
    _contentController = TextEditingController(
      text: _isHashOnly ? (rule?.midHash ?? '') : (rule?.content ?? ''),
    );
    _scopes = rule == null
        ? _defaultScopes(_type)
        : Set<RuleScope>.of(rule.scopes);
    if (_scopes.isEmpty) _scopes = _defaultScopes(_type);
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  Set<RuleScope> _defaultScopes(RuleType type) => {
    for (final scope in type.allowedScopes)
      if (scope != RuleScope.whisper) scope,
  };

  void _selectType(RuleType type) {
    if (!_isNew || type == _type) return;
    setState(() {
      _type = type;
      _scopes = _defaultScopes(type);
    });
  }

  void _toggleScope(RuleScope scope) {
    if (_isHashOnly || _type == RuleType.zone) return;
    if (_scopes.contains(scope)) {
      if (_scopes.length == 1) {
        SmartDialog.showToast('至少选择一个适用范围');
        return;
      }
      setState(() => _scopes.remove(scope));
    } else {
      setState(() => _scopes.add(scope));
    }
  }

  void _save() {
    final content = _isHashOnly ? '' : _contentController.text.trim();
    final rule = FilterRule(
      id: widget.rule?.id ?? FilterRule.nextId(),
      type: _type,
      content: content,
      scopes: Set<RuleScope>.of(_scopes),
      enabled: _enabled,
      midHash: _isHashOnly ? widget.rule?.midHash : null,
    );
    final error = rule.validate();
    if (error != null) {
      SmartDialog.showToast(error);
      return;
    }
    try {
      if (_isNew) {
        RuleStore.instance.add(rule);
      } else {
        RuleStore.instance.update(rule);
      }
    } on ArgumentError catch (e) {
      SmartDialog.showToast(e.message?.toString() ?? '保存失败');
      return;
    }
    SmartDialog.showToast('已保存');
    Get.back();
  }

  Future<void> _delete() async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: const Text('删除该规则'),
      content: const Text('删除后无法恢复'),
    );
    if (!confirmed || !mounted) return;
    try {
      RuleStore.instance.remove(widget.rule!.id);
    } on ArgumentError catch (e) {
      SmartDialog.showToast(e.message?.toString() ?? '删除失败');
      return;
    }
    SmartDialog.showToast('已删除');
    Get.back();
  }

  String _typeTitle(RuleType type) => '${type.label}屏蔽';

  String _contentLabel(RuleType type) => switch (type) {
    .keyword => '关键词',
    .regex => '正则表达式',
    .zone => '分区名',
    .user => 'UID',
  };

  String _contentHint(RuleType type) => switch (type) {
    .keyword => '输入要屏蔽的关键词，不区分大小写',
    .regex => '输入正则表达式，无需头尾斜杠',
    .zone => '输入要屏蔽的分区名，支持正则',
    .user => '只输入数字 UID',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomPadding = MediaQuery.viewPaddingOf(context).bottom + 100;
    final scopes = _isHashOnly
        ? const [RuleScope.danmaku]
        : [
            for (final scope in _scopeOrder)
              if (_type.allowedScopes.contains(scope)) scope,
          ];
    return SimpleScaffold(
      appBar: AppBar(
        title: Text(_isNew ? '添加规则' : '编辑规则'),
        actions: [
          TextButton(onPressed: _save, child: const Text('保存')),
        ],
      ),
      body: ViewSafeArea(
        child: ViewInsetsSafeArea(
          child: ListView(
            padding: EdgeInsets.fromLTRB(16, 8, 16, bottomPadding),
            children: [
              Text('规则类型', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              for (final type in RuleType.values) _typeTile(theme, type),
              const SizedBox(height: 16),
              TextField(
                controller: _contentController,
                readOnly: _isHashOnly,
                keyboardType: _type == RuleType.user && !_isHashOnly
                    ? TextInputType.number
                    : TextInputType.text,
                inputFormatters: _type == RuleType.user && !_isHashOnly
                    ? [FilteringTextInputFormatter.digitsOnly]
                    : null,
                decoration: InputDecoration(
                  labelText: _isHashOnly ? '哈希' : _contentLabel(_type),
                  hintText: _isHashOnly ? null : _contentHint(_type),
                  helperText: _isHashOnly ? '只有哈希的用户规则不能修改哈希' : null,
                ),
              ),
              const SizedBox(height: 20),
              Text('适用范围', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              for (final scope in scopes) _scopeTile(theme, scope),
              if (!_isNew) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text('启用', style: theme.textTheme.titleMedium),
                    ),
                    Transform.scale(
                      scale: 0.8,
                      alignment: Alignment.centerRight,
                      child: Switch(
                        value: _enabled,
                        onChanged: (value) =>
                            setState(() => _enabled = value),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Center(
                  child: TextButton(
                    onPressed: _delete,
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                    child: const Text('删除'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _typeTile(ThemeData theme, RuleType type) {
    final selected = _type == type;
    final editable = _isNew;
    final color = selected
        ? theme.colorScheme.primary
        : editable
        ? null
        : theme.colorScheme.outline;
    return InkWell(
      onTap: editable ? () => _selectType(type) : null,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 22,
              color: selected ? theme.colorScheme.primary : color,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _typeTitle(type),
                    style: theme.textTheme.bodyLarge?.copyWith(color: color),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _typeDescriptions[type] ?? '',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scopeTile(ThemeData theme, RuleScope scope) {
    final checked = _scopes.contains(scope);
    final fixed = _isHashOnly || _type == RuleType.zone;
    return InkWell(
      onTap: fixed ? null : () => _toggleScope(scope),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Checkbox(
              value: checked,
              onChanged: fixed ? null : (_) => _toggleScope(scope),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(scope.label, style: theme.textTheme.bodyLarge),
                  const SizedBox(height: 2),
                  Text(
                    _scopeDescriptions[scope] ?? '',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
