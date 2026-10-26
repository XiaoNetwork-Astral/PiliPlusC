import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/view_insets_safe_area.dart';
import 'package:PiliPlus/common/widgets/view_safe_area.dart';
import 'package:PiliPlus/models/cognitive_filter/filter_rule.dart';
import 'package:PiliPlus/models/cognitive_filter/rule_scope.dart';
import 'package:PiliPlus/models/cognitive_filter/rule_type.dart';
import 'package:PiliPlus/utils/cognitive_filter/rule_source.dart';
import 'package:PiliPlus/utils/cognitive_filter/rule_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// 范围在界面里的显示顺序
const List<RuleScope> ruleScopeOrder = [
  RuleScope.danmaku,
  RuleScope.reply,
  RuleScope.dynamic,
  RuleScope.video,
  RuleScope.zone,
  RuleScope.live,
  RuleScope.whisper,
];

/// 新建规则时默认勾选的范围，私信和视频分区需要用户自己勾选
Set<RuleScope> defaultRuleScopes(RuleType type) => {
  for (final scope in type.allowedScopes)
    if (scope != RuleScope.whisper && scope != RuleScope.zone) scope,
};

/// 规则编辑页
///
/// 传入 null 表示新建规则，此时可以选类型；编辑已有规则时类型不能改。
/// 默认读写屏蔽规则，传入 [source] 后也可以编辑 AI 白名单；[allowedScopes]
/// 用于收窄可选的适用范围。
class RuleEditPage extends StatefulWidget {
  const RuleEditPage({
    super.key,
    this.rule,
    this.source,
    this.allowedScopes,
  });

  final FilterRule? rule;

  /// 数据源，为空时使用屏蔽规则
  final RuleSource? source;

  /// 可选的适用范围，为空表示不限
  final Set<RuleScope>? allowedScopes;

  @override
  State<RuleEditPage> createState() => _RuleEditPageState();
}

class _RuleEditPageState extends State<RuleEditPage> {
  late RuleType _type;
  late final TextEditingController _contentController;
  late Set<RuleScope> _scopes;

  bool get _isNew => widget.rule == null;

  RuleSource get _source => widget.source ?? RuleStore.instance;

  /// 某类型新建时的默认范围，收窄到 [RuleEditPage.allowedScopes]
  Set<RuleScope> _defaultScopes(RuleType type) {
    final allowed = widget.allowedScopes;
    final defaults = defaultRuleScopes(type);
    if (allowed == null) return defaults;
    final scopes = defaults.intersection(allowed);
    if (scopes.isNotEmpty) return scopes;
    final fallback = type.allowedScopes.intersection(allowed);
    return fallback.isEmpty ? defaults : fallback;
  }

  /// 界面里显示的适用范围，只显示允许的范围
  List<RuleScope> get _visibleScopes {
    final allowed = widget.allowedScopes;
    if (allowed == null) return ruleScopeOrder;
    return [
      for (final scope in ruleScopeOrder)
        if (allowed.contains(scope)) scope,
    ];
  }

  @override
  void initState() {
    super.initState();
    final rule = widget.rule;
    _type = rule?.type ?? RuleType.keyword;
    _contentController = TextEditingController(text: rule?.content ?? '');
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

  void _selectType(RuleType type) {
    if (type == _type) return;
    setState(() {
      _type = type;
      _scopes = _defaultScopes(type);
    });
  }

  void _toggleScope(RuleScope scope, bool selected) {
    if (!selected && _scopes.length == 1) return;
    setState(() {
      if (selected) {
        _scopes.add(scope);
      } else {
        _scopes.remove(scope);
      }
    });
  }

  void _save() {
    final rule = FilterRule(
      id: widget.rule?.id ?? FilterRule.nextId(),
      type: _type,
      content: _contentController.text.trim(),
      scopes: Set<RuleScope>.of(_scopes),
      enabled: widget.rule?.enabled ?? true,
    );
    final error = rule.validate();
    if (error != null) {
      SmartDialog.showToast(error);
      return;
    }
    try {
      if (_isNew) {
        _source.add(rule);
      } else {
        _source.update(rule);
      }
    } on ArgumentError catch (e) {
      SmartDialog.showToast(e.message?.toString() ?? '保存失败');
      return;
    }
    Get.back();
  }

  String _contentLabel(RuleType type) => switch (type) {
    .keyword => '关键词',
    .regex => '正则表达式',
    .user => 'UID',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomPadding = MediaQuery.viewPaddingOf(context).bottom + 100;
    final sectionStyle = theme.textTheme.labelLarge?.copyWith(
      color: theme.colorScheme.outline,
    );
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
              if (_isNew) ...[
                Text('类型', style: sectionStyle),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final type in RuleType.values)
                      ChoiceChip(
                        label: Text(type.label),
                        selected: _type == type,
                        showCheckmark: false,
                        onSelected: (_) => _selectType(type),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
              TextField(
                controller: _contentController,
                autofocus: _isNew,
                keyboardType: _type == RuleType.user
                    ? TextInputType.number
                    : TextInputType.text,
                inputFormatters: _type == RuleType.user
                    ? [FilteringTextInputFormatter.digitsOnly]
                    : null,
                decoration: InputDecoration(
                  labelText: _contentLabel(_type),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
              Text('适用范围', style: sectionStyle),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final scope in _visibleScopes)
                    FilterChip(
                      label: Text(scope.label),
                      selected: _scopes.contains(scope),
                      onSelected: _type.allowedScopes.contains(scope)
                          ? (selected) => _toggleScope(scope, selected)
                          : null,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
