import 'package:PiliPlus/common/widgets/dialog/dialog.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/view_safe_area.dart';
import 'package:PiliPlus/models/cognitive_filter/filter_surface.dart';
import 'package:PiliPlus/pages/cognitive_filter/judge_history_detail_page.dart';
import 'package:PiliPlus/pages/cognitive_filter/widgets.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/ai_runtime.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/ai_whitelist.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/judge_history.dart';
import 'package:PiliPlus/utils/cognitive_filter/rule_store.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

enum _HistoryFilter {
  all('全部'),
  rule('规则屏蔽'),
  ai('AI 屏蔽');

  const _HistoryFilter(this.label);

  final String label;
}

enum _EntryAction { copy, deleteRule, whitelist }

/// 屏蔽历史
///
/// 规则屏蔽和 AI 屏蔽放在一起，进入时读取一次，不做订阅
class JudgeHistoryPage extends StatefulWidget {
  const JudgeHistoryPage({super.key});

  @override
  State<JudgeHistoryPage> createState() => _JudgeHistoryPageState();
}

class _JudgeHistoryPageState extends State<JudgeHistoryPage> {
  late List<JudgeHistoryEntry> _entries;
  _HistoryFilter _filter = _HistoryFilter.all;

  @override
  void initState() {
    super.initState();
    _entries = AiFilterRuntime.instance.history;
  }

  List<JudgeHistoryEntry> get _shown => switch (_filter) {
    .all => _entries,
    .rule => [
      for (final entry in _entries)
        if (entry.isRule) entry,
    ],
    .ai => [
      for (final entry in _entries)
        if (!entry.isRule) entry,
    ],
  };

  Future<void> _clear() async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: const Text('确定清空屏蔽历史？'),
    );
    if (!confirmed || !mounted) return;
    AiFilterRuntime.instance.clearHistory();
    setState(() => _entries = AiFilterRuntime.instance.history);
  }

  Future<void> _onAction(JudgeHistoryEntry entry, _EntryAction action) async {
    switch (action) {
      case .copy:
        await Clipboard.setData(ClipboardData(text: entry.text));
      case .deleteRule:
        final id = entry.ruleId;
        if (id != null) RuleStore.instance.remove(id);
      case .whitelist:
        AiWhitelist.instance.addKeywordFromText(
          entry.text,
          surface: FilterSurface.values
              .where((surface) => surface.label == entry.surface)
              .firstOrNull,
        );
    }
  }

  String _two(int value) => value.toString().padLeft(2, '0');

  String _dateText(DateTime time) =>
      '${time.year}-${_two(time.month)}-${_two(time.day)}';

  String _clockText(DateTime time) =>
      '${_two(time.hour)}:${_two(time.minute)}:${_two(time.second)}';

  Widget _buildBadges(JudgeHistoryEntry entry) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          CfBadge(
            entry.isRule ? '规则屏蔽' : 'AI 屏蔽',
            tone: entry.isRule ? CfBadgeTone.secondary : CfBadgeTone.primary,
          ),
          CfBadge(entry.surface),
          if (entry.isRule && entry.ruleType.isNotEmpty)
            CfBadge(entry.ruleType),
          if (entry.label.isNotEmpty) CfBadge(entry.label),
          if (!entry.isRule) CfBadge(entry.score.toStringAsFixed(2)),
        ],
      ),
    );
  }

  Widget _buildTrailing(ThemeData theme, JudgeHistoryEntry entry) {
    final style = theme.textTheme.labelMedium!.copyWith(
      color: theme.colorScheme.outline,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(_dateText(entry.time), style: style),
            Text(_clockText(entry.time), style: style),
          ],
        ),
        PopupMenuButton<_EntryAction>(
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(
            minimumSize: const Size(32, 40),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          icon: Icon(
            Icons.more_vert,
            size: 20,
            color: theme.colorScheme.outline,
          ),
          onSelected: (action) => _onAction(entry, action),
          itemBuilder: (context) => [
            const PopupMenuItem(value: _EntryAction.copy, child: Text('复制文字')),
            if (entry.isRule && entry.ruleId != null)
              const PopupMenuItem(
                value: _EntryAction.deleteRule,
                child: Text('删除这条规则'),
              ),
            if (!entry.isRule)
              const PopupMenuItem(
                value: _EntryAction.whitelist,
                child: Text('加入白名单'),
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = _shown;
    return SimpleScaffold(
      appBar: AppBar(
        title: const Text('屏蔽历史'),
        actions: [
          TextButton(onPressed: _clear, child: const Text('清空')),
        ],
      ),
      body: ViewSafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final filter in _HistoryFilter.values)
                    ChoiceChip(
                      label: Text(filter.label),
                      selected: _filter == filter,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _filter = filter),
                    ),
                ],
              ),
            ),
            Expanded(
              child: shown.isEmpty
                  ? Center(
                      child: Text(
                        '暂无记录',
                        style: TextStyle(color: theme.colorScheme.outline),
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.only(
                        bottom: MediaQuery.viewPaddingOf(context).bottom + 100,
                      ),
                      itemCount: shown.length,
                      itemBuilder: (context, index) {
                        final entry = shown[index];
                        return CfTile(
                          contentPadding: const EdgeInsetsDirectional.only(
                            start: 16,
                            end: 10,
                          ),
                          title: entry.text,
                          titleMaxLines: 2,
                          subtitleWidget: _buildBadges(entry),
                          trailing: _buildTrailing(theme, entry),
                          onTap: () => Get.to(
                            () => JudgeHistoryDetailPage(entry: entry),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
