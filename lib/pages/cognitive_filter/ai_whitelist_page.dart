import 'package:PiliPlus/common/widgets/dialog/dialog.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/view_safe_area.dart';
import 'package:PiliPlus/pages/cognitive_filter/widgets.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/ai_whitelist.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/ai_whitelist_rules.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// AI 屏蔽白名单
///
/// 命中白名单的文字不会送去 AI 判定，规则屏蔽不受影响
class AiWhitelistPage extends StatelessWidget {
  const AiWhitelistPage({super.key});

  Future<void> _openEditor(
    BuildContext context, [
    AiWhitelistEntry? entry,
  ]) async {
    final result = await showDialog<_WhitelistDraft>(
      context: context,
      builder: (context) => _WhitelistDialog(entry: entry),
    );
    if (result == null) return;
    if (entry == null) {
      AiWhitelist.instance.add(result.type, result.content);
    } else {
      AiWhitelist.instance.update(
        AiWhitelistEntry(
          id: entry.id,
          type: result.type,
          content: result.content,
          enabled: entry.enabled,
        ),
      );
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    AiWhitelistEntry entry,
  ) async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: const Text('确定删除该白名单？'),
    );
    if (confirmed) AiWhitelist.instance.remove(entry.id);
  }

  Widget _entryTile(
    BuildContext context,
    ThemeData theme,
    AiWhitelistEntry entry,
  ) {
    return CfTile(
      title: entry.content,
      titleMaxLines: 2,
      subtitle: entry.type.label,
      onTap: () => _openEditor(context, entry),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '删除',
            icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
            onPressed: () => _confirmDelete(context, entry),
          ),
          Transform.scale(
            scale: 0.8,
            child: Switch(
              value: entry.enabled,
              onChanged: (value) =>
                  AiWhitelist.instance.setEnabled(entry.id, value),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomPadding = MediaQuery.viewPaddingOf(context).bottom + 100;
    return SimpleScaffold(
      appBar: AppBar(title: const Text('白名单')),
      body: ViewSafeArea(
        child: ValueListenableBuilder<int>(
          valueListenable: AiWhitelist.instance.version,
          builder: (context, _, _) {
            final entries = AiWhitelist.instance.entries;
            return ListView.builder(
              padding: EdgeInsets.only(bottom: bottomPadding),
              itemCount: entries.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return CfTile(
                    icon: Icons.add,
                    title: '添加白名单',
                    onTap: () => _openEditor(context),
                  );
                }
                return _entryTile(context, theme, entries[index - 1]);
              },
            );
          },
        ),
      ),
    );
  }
}

typedef _WhitelistDraft = ({AiWhitelistType type, String content});

class _WhitelistDialog extends StatefulWidget {
  const _WhitelistDialog({this.entry});

  final AiWhitelistEntry? entry;

  @override
  State<_WhitelistDialog> createState() => _WhitelistDialogState();
}

class _WhitelistDialogState extends State<_WhitelistDialog> {
  late AiWhitelistType _type = widget.entry?.type ?? AiWhitelistType.keyword;
  late final TextEditingController _controller = TextEditingController(
    text: widget.entry?.content ?? '',
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final content = _controller.text.trim();
    final error = validateAiWhitelistContent(_type, content);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Get.back(result: (type: _type, content: content));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.entry == null ? '添加白名单' : '编辑白名单'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            children: [
              for (final type in AiWhitelistType.values)
                ChoiceChip(
                  label: Text(type.label),
                  selected: _type == type,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _type = type),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: 1,
            maxLines: 3,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            decoration: InputDecoration(
              errorText: _error,
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: Get.back,
          child: Text(
            '取消',
            style: TextStyle(color: ColorScheme.of(context).outline),
          ),
        ),
        TextButton(onPressed: _submit, child: const Text('确定')),
      ],
    );
  }
}
